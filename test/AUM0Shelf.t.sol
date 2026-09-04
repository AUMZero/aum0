// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {AUM0Shelf} from "../src/AUM0Shelf.sol";
import {StrictERC20, MockFeed, MockRouter} from "./AUM0Wallet.t.sol";

contract AUM0ShelfTest is Test {
    AUM0Shelf aum;
    StrictERC20 usdg;
    StrictERC20 nvda;
    MockFeed nvdaFeed;
    MockRouter router;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address keeper = address(0xCAFE);
    bytes32 fiftyFifty;

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
        aum = new AUM0Shelf(address(router), address(usdg), 6, 7 days, tokens, feeds, fees, decs);

        fiftyFifty = aum.carveLaw(_law(5000, 5000));

        usdg.mint(alice, 200e6);
        vm.startPrank(alice);
        usdg.approve(address(aum), type(uint256).max);
        nvda.approve(address(aum), type(uint256).max);
        aum.adopt(fiftyFifty, 100, 150, 1e6);
        vm.stopPrank();
    }

    function _law(uint16 cash, uint16 stock) internal pure returns (uint16[] memory t) {
        t = new uint16[](2);
        t[0] = cash; t[1] = stock;
    }

    function _buy(uint256 amountIn) internal pure returns (AUM0Shelf.Trade[] memory tr) {
        tr = new AUM0Shelf.Trade[](1);
        tr[0] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 1, amountIn: amountIn});
    }

    function _sell(uint256 amountIn) internal pure returns (AUM0Shelf.Trade[] memory tr) {
        tr = new AUM0Shelf.Trade[](1);
        tr[0] = AUM0Shelf.Trade({sellAsset: 1, buyAsset: 0, amountIn: amountIn});
    }

    /// The same allocation is the same fund, no matter who carves it or when.
    function test_theShelfHoldsEachFundExactlyOnce() public {
        vm.recordLogs();
        vm.prank(bob);
        bytes32 again = aum.carveLaw(_law(5000, 5000));

        assertEq(again, fiftyFifty, "same numbers, same fund");
        assertEq(vm.getRecordedLogs().length, 0, "and the second carve changes nothing");
        assertEq(aum.lawOf(fiftyFifty).length, 2);
    }

    function test_adoptingAMissingLawReverts() public {
        vm.prank(bob);
        vm.expectRevert(AUM0Shelf.NoSuchLaw.selector);
        aum.adopt(keccak256("no such fund"), 100, 150, 1e6);
    }

    function test_lawsMustSumAndFitTheVenue() public {
        vm.expectRevert(AUM0Shelf.BadWeights.selector);
        aum.carveLaw(_law(5000, 4999));

        uint16[] memory tooLong = new uint16[](3);
        tooLong[0] = 10000;
        vm.expectRevert(AUM0Shelf.BadWeights.selector);
        aum.carveLaw(tooLong);
    }

    /// The whole pitch, shelf edition: one fund, many wallets, no fund token,
    /// no deposits, and the manager holds nothing throughout.
    function test_twoWalletsOneFund() public {
        usdg.mint(bob, 1000e6);
        vm.startPrank(bob);
        usdg.approve(address(aum), type(uint256).max);
        nvda.approve(address(aum), type(uint256).max);
        aum.adopt(fiftyFifty, 100, 150, 1e6);
        vm.stopPrank();

        vm.prank(keeper);
        aum.rebalance(alice, _buy(100e6));
        vm.prank(keeper);
        aum.rebalance(bob, _buy(500e6));

        assertLt(aum.drift(alice), 200, "alice sits on the law");
        assertLt(aum.drift(bob), 200, "bob sits on the same law");
        assertEq(usdg.balanceOf(address(aum)), 0, "the manager holds no cash");
        assertEq(nvda.balanceOf(address(aum)), 0, "the manager holds no stock");
        assertGt(nvda.balanceOf(alice), 0);
        assertGt(nvda.balanceOf(bob), 0);
    }

    /// Switching funds is one transaction, and the keeper follows the new law.
    function test_reAdoptSwitchesFunds() public {
        vm.prank(keeper);
        aum.rebalance(alice, _buy(100e6)); // on the 50/50 law

        bytes32 allCash = aum.carveLaw(_law(10000, 0));
        vm.prank(alice);
        aum.adopt(allCash, 100, 150, 1e6);

        assertGt(aum.drift(alice), 4000, "under the new law she is far off target");

        vm.prank(keeper);
        aum.rebalance(alice, _sell(nvda.balanceOf(alice)));
        assertLt(aum.drift(alice), 200, "and the keeper walks her onto it");
        assertEq(nvda.balanceOf(alice), 0, "stock sold back to cash, in her own wallet");
    }

    /// Wall one still stands under an adopted law.
    function test_wall1_overshootReverts() public {
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(AUM0Shelf.DriftNotImproved.selector, 10000, 10000));
        aum.rebalance(alice, _buy(200e6));
    }

    /// Wall two still stands under an adopted law.
    function test_wall2_badFillReverts() public {
        router.setSlippage(300); // 3%, band is 1.5%
        vm.prank(keeper);
        vm.expectRevert();
        aum.rebalance(alice, _buy(100e6));
    }

    /// The carver of a law is paid nothing, ever. The worker is paid by the
    /// wallet, and the contract keeps nothing.
    function test_carverEarnsNothingWorkerEarnsBounty() public {
        address carver = address(0xCA23E2);
        vm.prank(carver);
        bytes32 lawId = aum.carveLaw(_law(3000, 7000));
        vm.prank(alice);
        aum.adopt(lawId, 100, 150, 1e6);

        vm.prank(keeper);
        aum.rebalance(alice, _buy(140e6));

        assertEq(usdg.balanceOf(carver), 0, "manufacturing a fund pays nothing");
        assertGt(usdg.balanceOf(keeper), 0, "doing the work pays");
        assertEq(usdg.balanceOf(address(aum)), 0, "the company keeps nothing");
    }

    function test_revokingTheAllowanceEndsTheRelationship() public {
        vm.prank(alice);
        usdg.approve(address(aum), 0);

        vm.prank(keeper);
        vm.expectRevert(AUM0Shelf.TransferFailed.selector);
        aum.rebalance(alice, _buy(100e6));

        assertEq(usdg.balanceOf(alice), 200e6, "her money never moved");
    }

    function test_unconfiguredWalletReadsZeroInsteadOfReverting() public {
        address stranger = address(0xDEAD5);
        assertEq(aum.drift(stranger), 0, "no law, no distance from it");
        assertEq(aum.valueOf(stranger), 0);
    }
}
