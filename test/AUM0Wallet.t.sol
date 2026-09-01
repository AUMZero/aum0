// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0Wallet} from "../src/AUM0Wallet.sol";
import {ISwapRouter} from "../src/AUM0.sol";

/// Enforces allowance for real, because in wallet mode the allowance is the
/// entire security perimeter.
contract StrictERC20 {
    string public name;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, uint8 d) { name = n; decimals = d; }
    function mint(address to, uint256 v) external { balanceOf[to] += v; }
    function approve(address s, uint256 v) external returns (bool) { allowance[msg.sender][s] = v; return true; }
    function transfer(address to, uint256 v) external returns (bool) {
        if (balanceOf[msg.sender] < v) return false;
        balanceOf[msg.sender] -= v; balanceOf[to] += v; return true;
    }
    function transferFrom(address f, address to, uint256 v) external returns (bool) {
        if (balanceOf[f] < v) return false;
        uint256 a = allowance[f][msg.sender];
        if (a < v) return false;
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        balanceOf[f] -= v; balanceOf[to] += v; return true;
    }
}

contract MockFeed {
    int256 public answer;
    constructor(int256 a) { answer = a; }
    function set(int256 a) external { answer = a; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}

/// Pays out to `recipient`, which is what wallet mode depends on.
contract MockRouter {
    StrictERC20 public usdg;
    mapping(address => MockFeed) public feedOf;
    mapping(address => uint8) public decOf;
    uint256 public slippageBps;

    constructor(StrictERC20 _usdg) { usdg = _usdg; }
    function register(StrictERC20 token, MockFeed feed) external {
        feedOf[address(token)] = feed; decOf[address(token)] = token.decimals();
    }
    function setSlippage(uint256 bps) external { slippageBps = bps; }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata p) external returns (uint256 out) {
        StrictERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        if (p.tokenIn == address(usdg)) {
            uint256 price = uint256(feedOf[p.tokenOut].answer());
            out = (p.amountIn * 1e8 * (10 ** decOf[p.tokenOut])) / price / (10 ** usdg.decimals());
        } else {
            uint256 price = uint256(feedOf[p.tokenIn].answer());
            out = (p.amountIn * price * (10 ** usdg.decimals())) / 1e8 / (10 ** decOf[p.tokenIn]);
        }
        out = (out * (10000 - slippageBps)) / 10000;
        StrictERC20(p.tokenOut).mint(p.recipient, out);
    }
}

contract AUM0WalletTest is Test {
    AUM0Wallet aum;
    StrictERC20 usdg;
    StrictERC20 nvda;
    MockFeed nvdaFeed;
    MockRouter router;

    address alice = address(0xA11CE);
    address keeper = address(0xCAFE);

    function setUp() public {
        usdg = new StrictERC20("USDG", 6);
        nvda = new StrictERC20("NVDA", 18);
        nvdaFeed = new MockFeed(200e8);
        router = new MockRouter(usdg);
        router.register(nvda, nvdaFeed);

        address[] memory tokens = new address[](1);
        tokens[0] = address(nvda);
        address[] memory feeds = new address[](1);
        feeds[0] = address(nvdaFeed);
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;
        uint8[] memory decs = new uint8[](1);
        decs[0] = 18;
        aum = new AUM0Wallet(address(router), address(usdg), 6, 7 days, tokens, feeds, fees, decs);

        usdg.mint(alice, 200e6);
        vm.startPrank(alice);
        usdg.approve(address(aum), type(uint256).max);
        nvda.approve(address(aum), type(uint256).max);
        uint16[] memory t = new uint16[](2);
        t[0] = 5000; t[1] = 5000;
        aum.setTarget(t, 100, 150, 1e6);
        vm.stopPrank();
    }

    function _buy(uint256 amountIn) internal pure returns (AUM0Wallet.Trade[] memory tr) {
        tr = new AUM0Wallet.Trade[](1);
        tr[0] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: 1, amountIn: amountIn});
    }

    /// The whole pitch: the manager holds nothing, before or after.
    function test_theManagerNeverHoldsAnything() public {
        assertEq(usdg.balanceOf(alice), 200e6);
        assertEq(nvda.balanceOf(alice), 0);

        vm.prank(keeper);
        aum.rebalance(alice, _buy(100e6));

        assertEq(nvda.balanceOf(address(aum)), 0, "manager holds no stock");
        assertEq(usdg.balanceOf(address(aum)), 0, "manager holds no cash");
        assertGt(nvda.balanceOf(alice), 0, "the stock is in her own wallet");
        assertLt(aum.drift(alice), 200, "and the wallet landed on its law");
    }

    /// Quitting is revoking. There is nothing to withdraw.
    function test_revokingTheAllowanceEndsTheRelationship() public {
        vm.prank(alice);
        usdg.approve(address(aum), 0);

        vm.prank(keeper);
        vm.expectRevert(AUM0Wallet.TransferFailed.selector);
        aum.rebalance(alice, _buy(100e6));

        assertEq(usdg.balanceOf(alice), 200e6, "her money never moved");
    }

    /// A smaller allowance is a smaller mandate, enforced by the token itself.
    function test_allowanceCapsWhatCanEverMove() public {
        vm.prank(alice);
        usdg.approve(address(aum), 40e6);

        vm.prank(keeper);
        vm.expectRevert(AUM0Wallet.TransferFailed.selector);
        aum.rebalance(alice, _buy(100e6));
    }

    /// Wall one, measured on real wallet balances.
    function test_wall1_aTradeThatDoesNotHelpReverts() public {
        vm.prank(keeper);
        aum.rebalance(alice, _buy(100e6)); // now on target

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(AUM0Wallet.DriftBelowThreshold.selector, aum.drift(alice), 100));
        aum.rebalance(alice, _buy(10e6));
    }

    /// Wall one again: overshooting the target is refused outright.
    function test_wall1_overshootReverts() public {
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(AUM0Wallet.DriftNotImproved.selector, 10000, 10000));
        aum.rebalance(alice, _buy(200e6)); // all cash into stock: equally wrong, other side
    }

    /// Wall two: a fill worse than the account's band is refused.
    function test_wall2_badFillReverts() public {
        router.setSlippage(300); // 3%, band is 1.5%
        vm.prank(keeper);
        vm.expectRevert();
        aum.rebalance(alice, _buy(100e6));
    }

    /// The bounty comes out of the owner's own wallet, and only on help.
    function test_bountyIsPaidFromTheWallet() public {
        vm.prank(keeper);
        aum.rebalance(alice, _buy(100e6));

        uint256 paid = usdg.balanceOf(keeper);
        assertGt(paid, 0, "the worker was paid");
        assertApproxEqAbs(paid, 1e6, 2e4, "roughly the full bounty for the full journey");
        assertEq(usdg.balanceOf(alice) + paid + 100e6, 200e6, "and it came from her, not from thin air");
    }

    /// Splitting the work farms nothing: the payouts telescope.
    function test_bountySplitProof() public {
        vm.prank(keeper);
        aum.rebalance(alice, _buy(50e6));
        vm.prank(keeper);
        aum.rebalance(alice, _buy(30e6));
        vm.prank(keeper);
        aum.rebalance(alice, _buy(20e6));
        uint256 split = usdg.balanceOf(keeper);

        // same journey, one call, fresh wallet
        address bob = address(0xB0B);
        usdg.mint(bob, 200e6);
        vm.startPrank(bob);
        usdg.approve(address(aum), type(uint256).max);
        nvda.approve(address(aum), type(uint256).max);
        uint16[] memory t = new uint16[](2);
        t[0] = 5000; t[1] = 5000;
        aum.setTarget(t, 100, 150, 1e6);
        vm.stopPrank();

        address keeper2 = address(0xBEEF);
        vm.prank(keeper2);
        aum.rebalance(bob, _buy(100e6));
        uint256 single = usdg.balanceOf(keeper2);

        assertApproxEqAbs(split, single, 3e4, "three calls cost what one call costs");
    }

    /// A wallet that never carved a law reads as zero, not as a revert. The
    /// site asks every visitor for their drift before they have one.
    function test_unconfiguredWalletReadsZeroInsteadOfReverting() public {
        address stranger = address(0xDEAD5);
        assertEq(aum.drift(stranger), 0, "no law, no distance from it");
        assertEq(aum.valueOf(stranger), 0);
    }

    /// Stock the owner already held counts as theirs, with no deposit step.
    function test_stockAlreadyInTheWalletIsUnderManagement() public {
        nvda.mint(alice, 3e18); // $600 of stock appears, unannounced
        assertGt(aum.valueOf(alice), 790e18, "the manager sees the whole wallet");
        assertGt(aum.drift(alice), 2400, "and knows a 200/600 wallet is off a 50/50 law");
    }
}
