// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0, ISwapRouter} from "../src/AUM0.sol";

contract MockERC20 {
    string public name;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, uint8 d) { name = n; decimals = d; }
    function mint(address to, uint256 v) external { balanceOf[to] += v; }
    function transfer(address to, uint256 v) external returns (bool) {
        if (balanceOf[msg.sender] < v) return false;
        balanceOf[msg.sender] -= v; balanceOf[to] += v; return true;
    }
    function transferFrom(address f, address to, uint256 v) external returns (bool) {
        if (balanceOf[f] < v) return false;
        balanceOf[f] -= v; balanceOf[to] += v; return true;
    }
    function approve(address, uint256) external pure returns (bool) { return true; }
}

contract MockFeed {
    int256 public answer;
    constructor(int256 a) { answer = a; }
    function set(int256 a) external { answer = a; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}

/// Swaps at the feed price, shaded by a configurable slippage so the band
/// check has something real to catch.
contract MockRouter {
    MockERC20 public usdg;
    mapping(address => MockFeed) public feedOf;
    mapping(address => uint8) public decOf;
    uint256 public slippageBps; // taken out of every fill

    constructor(MockERC20 _usdg) { usdg = _usdg; }
    function register(MockERC20 token, MockFeed feed) external {
        feedOf[address(token)] = feed; decOf[address(token)] = token.decimals();
    }
    function setSlippage(uint256 bps) external { slippageBps = bps; }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata p) external returns (uint256 out) {
        MockERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        if (p.tokenIn == address(usdg)) {
            // buy stock: usd -> token at feed price
            uint256 price = uint256(feedOf[p.tokenOut].answer());
            out = (p.amountIn * 1e8 * (10 ** decOf[p.tokenOut])) / price / (10 ** usdg.decimals());
        } else {
            uint256 price = uint256(feedOf[p.tokenIn].answer());
            out = (p.amountIn * price * (10 ** usdg.decimals())) / 1e8 / (10 ** decOf[p.tokenIn]);
        }
        out = (out * (10000 - slippageBps)) / 10000;
        MockERC20(p.tokenOut).mint(msg.sender, out);
    }
}

contract AUM0Test is Test {
    AUM0 aum;
    MockERC20 usdg;   // 6 decimals, like the real one
    MockERC20 nvda;   // 18 decimals
    MockERC20 tsla;
    MockFeed nvdaFeed;
    MockFeed tslaFeed;
    MockRouter mockRouter;

    address alice = address(0xA11CE);
    address keeper = address(0xCAFE);

    function setUp() public {
        usdg = new MockERC20("USDG", 6);
        nvda = new MockERC20("NVDA", 18);
        tsla = new MockERC20("TSLA", 18);
        nvdaFeed = new MockFeed(200e8);
        tslaFeed = new MockFeed(300e8);
        mockRouter = new MockRouter(usdg);
        mockRouter.register(nvda, nvdaFeed);
        mockRouter.register(tsla, tslaFeed);

        address[] memory tokens = new address[](2);
        tokens[0] = address(nvda); tokens[1] = address(tsla);
        address[] memory feeds = new address[](2);
        feeds[0] = address(nvdaFeed); feeds[1] = address(tslaFeed);
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500; fees[1] = 500;
        uint8[] memory decs = new uint8[](2);
        decs[0] = 18; decs[1] = 18;

        aum = new AUM0(address(mockRouter), address(usdg), 6, 7 days, tokens, feeds, fees, decs);

        usdg.mint(alice, 10_000e6);
        vm.startPrank(alice);
        usdg.approve(address(aum), type(uint256).max);
        aum.deposit(0, 10_000e6);
        // policy: 50% cash, 30% NVDA, 20% TSLA
        uint16[] memory t = new uint16[](3);
        t[0] = 5000; t[1] = 3000; t[2] = 2000;
        aum.setTarget(t, 100, 100, 1e6); // min drift 1%, band 1%, bounty 1 USDG
        vm.stopPrank();
    }

    function do_rebalance() internal {
        // all cash -> needs 3000 USDG of NVDA, 2000 USDG of TSLA
        AUM0.Trade[] memory trades = new AUM0.Trade[](2);
        trades[0] = AUM0.Trade({sellAsset: 0, buyAsset: 1, amountIn: 3000e6});
        trades[1] = AUM0.Trade({sellAsset: 0, buyAsset: 2, amountIn: 2000e6});
        vm.prank(keeper);
        aum.rebalance(alice, trades);
    }

    // -- the walls ----------------------------------------------------------

    function test_rebalanceMovesTowardTargetAndPaysBounty() public {
        uint256 before = aum.drift(alice);
        assertEq(before, 10000, "all cash = fully drifted"); // |100-50|+|0-30|+|0-20|

        do_rebalance();

        assertLt(aum.drift(alice), 50, "close to target");
        assertGt(usdg.balanceOf(keeper), 0.99e6, "stranger got paid in proportion");
    }

    function test_wall1_helpOnlyTradeThatWorsensReverts() public {
        do_rebalance();
        // now near target. Selling ALL the NVDA would worsen drift.
        uint256 nvdaBal = aum.balanceOf(alice, 1);
        AUM0.Trade[] memory bad = new AUM0.Trade[](1);
        bad[0] = AUM0.Trade({sellAsset: 1, buyAsset: 0, amountIn: nvdaBal});
        vm.prank(keeper);
        vm.expectRevert(); // drift below threshold OR not improved
        aum.rebalance(alice, bad);
    }

    function test_wall1_overshootReverts() public {
        // buying WAY too much NVDA increases drift past the start
        AUM0.Trade[] memory bad = new AUM0.Trade[](1);
        bad[0] = AUM0.Trade({sellAsset: 0, buyAsset: 1, amountIn: 9500e6});
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(AUM0.DriftNotImproved.selector, 10000, 13000));
        aum.rebalance(alice, bad);
    }

    function test_wall2_badFillReverts() public {
        mockRouter.setSlippage(300); // 3% shading, band is 1%
        AUM0.Trade[] memory trades = new AUM0.Trade[](1);
        trades[0] = AUM0.Trade({sellAsset: 0, buyAsset: 1, amountIn: 3000e6});
        vm.prank(keeper);
        vm.expectRevert();
        aum.rebalance(alice, trades);
    }

    function test_wall3_withdrawAlwaysWorks() public {
        do_rebalance();
        uint256 nvdaBal = aum.balanceOf(alice, 1);
        vm.startPrank(alice);
        aum.withdraw(1, nvdaBal);
        aum.withdraw(0, aum.balanceOf(alice, 0));
        vm.stopPrank();
        assertEq(nvda.balanceOf(alice), nvdaBal, "stock came home");
        assertEq(aum.balanceOf(alice, 1), 0);
    }

    // -- guards ---------------------------------------------------------------

    function test_noRebalanceBelowThreshold() public {
        do_rebalance(); // near target now
        AUM0.Trade[] memory t = new AUM0.Trade[](1);
        t[0] = AUM0.Trade({sellAsset: 0, buyAsset: 1, amountIn: 10e6});
        vm.prank(keeper);
        vm.expectRevert();
        aum.rebalance(alice, t); // drift < minDriftBps: no bounty farming
    }

    function test_driftReactsToPrices() public {
        do_rebalance();
        nvdaFeed.set(400e8); // NVDA doubles: portfolio now overweight NVDA
        assertGt(aum.drift(alice), 1000, "price move re-opens drift");
    }

    function test_stockToStockDirectForbidden() public {
        AUM0.Trade[] memory t = new AUM0.Trade[](1);
        t[0] = AUM0.Trade({sellAsset: 1, buyAsset: 2, amountIn: 1});
        vm.prank(keeper);
        vm.expectRevert();
        aum.rebalance(alice, t);
    }

    function test_unconfiguredAccountRejected() public {
        AUM0.Trade[] memory t = new AUM0.Trade[](0);
        vm.prank(keeper);
        vm.expectRevert(AUM0.NotConfigured.selector);
        aum.rebalance(address(0xD00D), t);
    }

    function test_weightsMustSum() public {
        uint16[] memory t = new uint16[](3);
        t[0] = 5000; t[1] = 3000; t[2] = 1000;
        vm.prank(alice);
        vm.expectRevert(AUM0.BadWeights.selector);
        aum.setTarget(t, 100, 100, 1e6);
    }

    function test_bountySplitProof() public {
        // two keepers each doing half the job earn, in total, what one keeper
        // doing all of it earns: splitting cannot farm the bounty
        AUM0.Trade[] memory half1 = new AUM0.Trade[](1);
        half1[0] = AUM0.Trade({sellAsset: 0, buyAsset: 1, amountIn: 3000e6});
        AUM0.Trade[] memory half2 = new AUM0.Trade[](1);
        half2[0] = AUM0.Trade({sellAsset: 0, buyAsset: 2, amountIn: 2000e6});
        address k2 = address(0xFEED);
        vm.prank(keeper);
        aum.rebalance(alice, half1);
        vm.prank(k2);
        aum.rebalance(alice, half2);
        uint256 total = usdg.balanceOf(keeper) + usdg.balanceOf(k2);
        assertLe(total, 1e6, "sum of split bounties never exceeds the cap");
        assertGt(total, 0.99e6, "and telescopes to the same total");
    }

    function test_bountyComesOnlyFromOwnCash() public {
        // drain alice's cash below the bounty, then a rebalance that would
        // otherwise succeed must revert rather than pay from thin air
        vm.startPrank(alice);
        aum.withdraw(0, 9999e6);
        vm.stopPrank();
        AUM0.Trade[] memory t = new AUM0.Trade[](1);
        t[0] = AUM0.Trade({sellAsset: 0, buyAsset: 1, amountIn: 5e5});
        vm.prank(keeper);
        vm.expectRevert();
        aum.rebalance(alice, t);
    }
}
