// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0Bid} from "../src/AUM0Bid.sol";
import {StrictERC20, MockFeed, MockRouter} from "./AUM0Wallet.t.sol";

/// The claim under test: a worker is paid for the price it delivered, not for
/// having shown up first. Everything else about the firm is unchanged.
contract AUM0BidTest is Test {
    AUM0Bid aum;
    StrictERC20 usdg;
    StrictERC20 nvda;
    MockFeed nvdaFeed;
    MockRouter router;

    address alice = address(0xA11CE);
    address honest = address(0xC0FFEE);
    address greedy = address(0xBADBAD);

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
        aum = new AUM0Bid(address(router), address(usdg), 6, 7 days, tokens, feeds, fees, decs);

        usdg.mint(alice, 20000e6);          // twenty thousand dollars, where slippage matters
        vm.startPrank(alice);
        usdg.approve(address(aum), type(uint256).max);
        nvda.approve(address(aum), type(uint256).max);
        uint16[] memory t = new uint16[](2);
        t[0] = 5000; t[1] = 5000;
        aum.setTarget(t, 100, 200, 100e6);   // a hundred dollar bounty cap, 2% band
        vm.stopPrank();
    }

    function _pool(uint256 amountIn) internal pure returns (AUM0Bid.Trade[] memory tr) {
        tr = new AUM0Bid.Trade[](1);
        tr[0] = AUM0Bid.Trade({sellAsset: 0, buyAsset: 1, amountIn: amountIn, fill: AUM0Bid.Fill.POOL, amountOut: 0});
    }

    /// A clean fill at the feed keeps the whole bounty.
    function test_aCleanFillIsPaidInFull() public {
        vm.prank(honest);
        aum.rebalance(alice, _pool(10000e6));

        uint256 paid = usdg.balanceOf(honest);
        emit log_named_decimal_uint("clean fill, worker paid", paid, 6);
        assertGt(paid, 99e6, "close to the full hundred");
        assertLt(aum.drift(alice), 100, "and the wallet is on its law");
    }

    /// The old flaw, priced out. A worker who takes a percent of the trade for
    /// itself has already been paid by the wallet, so the bounty is gone.
    function test_aWorkerWhoTakesTheSlippageIsPaidNothing() public {
        router.setSlippage(150);            // 1.5%: inside the 2% band, so it is accepted

        vm.prank(greedy);
        aum.rebalance(alice, _pool(10000e6));

        uint256 paid = usdg.balanceOf(greedy);
        emit log_named_decimal_uint("greedy fill, worker paid", paid, 6);
        assertEq(paid, 0, "the wallet already paid for that fill");
    }

    /// Between the two: pay falls as the fill gets worse, and it is the wallet's
    /// own loss that does the subtracting, dollar for dollar.
    function test_payFallsWithTheQualityOfTheFill() public {
        uint256[3] memory bps = [uint256(0), 20, 60];
        uint256 last = type(uint256).max;
        for (uint256 i; i < bps.length; ++i) {
            uint256 snap = vm.snapshotState();
            router.setSlippage(bps[i]);
            address worker = address(uint160(0xE0E0 + i));
            vm.prank(worker);
            aum.rebalance(alice, _pool(10000e6));
            uint256 paid = usdg.balanceOf(worker);
            emit log_named_decimal_uint("paid", paid, 6);
            assertLt(paid, last, "a worse fill always pays less");
            last = paid;
            vm.revertToState(snap);
        }
    }

    /// The new way to fill: the worker is the counterparty and never touches a
    /// pool. Delivering at the feed costs the wallet nothing, so the worker
    /// keeps the entire bounty, and the wallet got a better price than any pool
    /// charging a fee could have given it.
    function test_aMarketMakerCanFillFromItsOwnInventoryAndBeatThePool() public {
        nvda.mint(honest, 100e18);
        vm.prank(honest);
        nvda.approve(address(aum), type(uint256).max);

        AUM0Bid.Trade[] memory tr = new AUM0Bid.Trade[](1);
        tr[0] = AUM0Bid.Trade({
            sellAsset: 0, buyAsset: 1, amountIn: 10000e6,
            fill: AUM0Bid.Fill.INVENTORY,
            amountOut: 50e18                       // ten thousand dollars at the two hundred dollar feed
        });

        uint256 before = nvda.balanceOf(alice);
        vm.prank(honest);
        aum.rebalance(alice, tr);

        assertEq(nvda.balanceOf(alice) - before, 50e18, "filled exactly at the feed");
        // the worker holds the ten thousand it was paid for the stock, plus the bounty
        uint256 bounty = usdg.balanceOf(honest) - 10000e6;
        emit log_named_decimal_uint("inventory fill, bounty", bounty, 6);
        assertGt(bounty, 99e6, "and the bounty was paid in full");
        assertEq(usdg.balanceOf(address(aum)), 0, "the manager kept nothing");
        assertEq(nvda.balanceOf(address(aum)), 0, "of either side");
    }

    /// A market maker willing to fill above the feed is paid in full as well:
    /// the wallet cannot lose on the leg, so there is nothing to deduct.
    function test_fillingBetterThanTheFeedIsAlsoPaidInFull() public {
        nvda.mint(honest, 100e18);
        vm.prank(honest);
        nvda.approve(address(aum), type(uint256).max);

        AUM0Bid.Trade[] memory tr = new AUM0Bid.Trade[](1);
        tr[0] = AUM0Bid.Trade({
            sellAsset: 0, buyAsset: 1, amountIn: 10000e6,
            fill: AUM0Bid.Fill.INVENTORY, amountOut: 50.5e18   // a better rate than the feed
        });
        vm.prank(honest);
        aum.rebalance(alice, tr);

        assertGt(usdg.balanceOf(honest) - 10000e6, 99e6, "paid in full");
        assertGt(aum.valueOf(alice), 20000e18, "and the wallet is worth more than it started");
    }

    /// An inventory worker who delivers a bad rate is caught by the same wall
    /// as everyone else.
    function test_anInventoryFillOutsideTheBandReverts() public {
        nvda.mint(honest, 100e18);
        vm.prank(honest);
        nvda.approve(address(aum), type(uint256).max);

        AUM0Bid.Trade[] memory tr = new AUM0Bid.Trade[](1);
        tr[0] = AUM0Bid.Trade({
            sellAsset: 0, buyAsset: 1, amountIn: 10000e6,
            fill: AUM0Bid.Fill.INVENTORY, amountOut: 45e18     // ten percent short
        });
        vm.prank(honest);
        vm.expectRevert();
        aum.rebalance(alice, tr);
    }

    /// Promising inventory you do not have costs the wallet nothing.
    function test_anInventoryWorkerWhoCannotDeliverGetsNothing() public {
        AUM0Bid.Trade[] memory tr = new AUM0Bid.Trade[](1);
        tr[0] = AUM0Bid.Trade({
            sellAsset: 0, buyAsset: 1, amountIn: 10000e6,
            fill: AUM0Bid.Fill.INVENTORY, amountOut: 50e18
        });
        vm.prank(greedy);
        vm.expectRevert(AUM0Bid.TransferFailed.selector);
        aum.rebalance(alice, tr);

        assertEq(usdg.balanceOf(alice), 20000e6, "her money never moved");
    }

    /// The pay schedule itself. Slippage on the x axis, what the worker keeps
    /// on the y. Every other keeper's line is flat.
    function test_thePayScheduleIsAStraightLineToZero() public {
        uint256[13] memory bps = [uint256(0), 10, 20, 30, 40, 50, 60, 80, 100, 120, 150, 180, 199];
        for (uint256 i; i < bps.length; ++i) {
            uint256 snap = vm.snapshotState();
            router.setSlippage(bps[i]);
            address worker = address(uint160(0xF0F0 + i));
            vm.prank(worker);
            aum.rebalance(alice, _pool(10000e6));
            emit log_named_decimal_uint(
                string.concat("slippage ", vm.toString(bps[i]), " bps -> pay"),
                usdg.balanceOf(worker), 6);
            vm.revertToState(snap);
        }
    }

    /// The three walls are untouched.
    function test_wall1_overshootStillReverts() public {
        vm.prank(honest);
        vm.expectRevert(abi.encodeWithSelector(AUM0Bid.DriftNotImproved.selector, 10000, 10000));
        aum.rebalance(alice, _pool(20000e6));
    }

    function test_wall3_theManagerHoldsNothing() public {
        vm.prank(honest);
        aum.rebalance(alice, _pool(10000e6));
        assertEq(usdg.balanceOf(address(aum)), 0);
        assertEq(nvda.balanceOf(address(aum)), 0);
    }
}
