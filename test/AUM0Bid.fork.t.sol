// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0Bid} from "../src/AUM0Bid.sol";
import {IERC20} from "../src/AUM0.sol";

/// The bid edition against the live chain. Two things are worth proving here
/// and nowhere else: that a real pool fill is priced correctly against the real
/// feeds, and that a market maker holding the real stock can beat that pool.
///   forge test --match-contract BidForkTest --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract BidForkTest is Test {
    address constant ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant USDG   = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant NVDA   = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant NVDA_F = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    address constant ASML   = 0x47F93d52cBeC7C6D2CfC080e154002370a60dAEA;   // thin pool, one percent tier
    address constant ASML_F = 0xB4106147E8cce40b7d46124090d373A71b70f87D;

    address alice = address(0xA11CE);
    address maker = address(0x9A4E4);
    address router_worker = address(0xC0FFEE);

    function _venue() internal returns (AUM0Bid) {
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        uint24[] memory fees = new uint24[](1);
        uint8[] memory decs = new uint8[](1);
        tokens[0] = NVDA; feeds[0] = NVDA_F; fees[0] = 500; decs[0] = 18;
        return new AUM0Bid(ROUTER, USDG, 6, 7 days, tokens, feeds, fees, decs);
    }

    function _thinVenue() internal returns (AUM0Bid) {
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](1);
        uint24[] memory fees = new uint24[](1);
        uint8[] memory decs = new uint8[](1);
        tokens[0] = ASML; feeds[0] = ASML_F; fees[0] = 10000; decs[0] = 18;
        return new AUM0Bid(ROUTER, USDG, 6, 7 days, tokens, feeds, fees, decs);
    }

    /// a wider band, because the point of this test is a pool that really does
    /// cost the wallet something
    function _lawWide(AUM0Bid aum, address who, uint256 cash) internal {
        deal(USDG, who, cash);
        vm.startPrank(who);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        IERC20(ASML).approve(address(aum), type(uint256).max);
        uint16[] memory t = new uint16[](2);
        t[0] = 5000; t[1] = 5000;
        aum.setTarget(t, 100, 800, 100e6);
        vm.stopPrank();
    }

    function _law(AUM0Bid aum, address who, uint256 cash) internal {
        deal(USDG, who, cash);
        vm.startPrank(who);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        IERC20(NVDA).approve(address(aum), type(uint256).max);
        uint16[] memory t = new uint16[](2);
        t[0] = 5000; t[1] = 5000;
        aum.setTarget(t, 100, 200, 100e6);
        vm.stopPrank();
    }

    /// A real pool fill costs the wallet the pool's fee and its slippage, and
    /// the contract takes exactly that out of the worker's pay.
    function test_aRealPoolFillIsPricedAgainstTheRealFeed() public {
        if (block.chainid != 4663) { vm.skip(true); return; }
        AUM0Bid aum = _venue();
        _law(aum, alice, 20000e6);

        vm.prank(router_worker);
        aum.rebalance(alice, _pool(10000e6));

        uint256 paid = IERC20(USDG).balanceOf(router_worker);
        emit log_named_decimal_uint("pool fill, worker kept", paid, 6);
        emit log_named_uint("drift after (bps)", aum.drift(alice));
        assertLt(paid, 100e6, "the pool's fee came out of the worker's pay");
        assertLt(aum.drift(alice), 200, "and the wallet landed on its law");
    }

    /// Where it matters. ASML sits in a thin pool on a one percent fee tier, so
    /// routing a real size through it costs the wallet plainly. A market maker
    /// holding the stock can hand it over at the feed and beat that, and the
    /// contract notices: it pays the maker in full and docks the router for
    /// what the pool took.
    function test_onAThinPoolTheMakerWinsAndIsPaidForIt() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        AUM0Bid poolVenue = _thinVenue();
        _lawWide(poolVenue, alice, 20000e6);
        vm.prank(router_worker);
        poolVenue.rebalance(alice, _pool(10000e6));
        uint256 viaPool = poolVenue.heldBy(alice, 1);
        uint256 poolPay = IERC20(USDG).balanceOf(router_worker);

        AUM0Bid mmVenue = _thinVenue();
        address bob = address(0xB0B);
        _lawWide(mmVenue, bob, 20000e6);

        (, int256 answer,,,) = IFeedLike(ASML_F).latestRoundData();
        uint256 atFeed = (10000e6 * 1e20) / uint256(answer);
        deal(ASML, maker, atFeed * 2);
        vm.prank(maker);
        IERC20(ASML).approve(address(mmVenue), type(uint256).max);

        AUM0Bid.Trade[] memory tr = new AUM0Bid.Trade[](1);
        tr[0] = AUM0Bid.Trade({sellAsset: 0, buyAsset: 1, amountIn: 10000e6, fill: AUM0Bid.Fill.INVENTORY, amountOut: atFeed});
        vm.prank(maker);
        mmVenue.rebalance(bob, tr);
        uint256 viaMaker = mmVenue.heldBy(bob, 1);
        uint256 makerPay = IERC20(USDG).balanceOf(maker) - 10000e6;

        emit log_named_decimal_uint("ASML received via the pool  ", viaPool, 18);
        emit log_named_decimal_uint("ASML received from the maker", viaMaker, 18);
        emit log_named_decimal_uint("worker pay, pool            ", poolPay, 6);
        emit log_named_decimal_uint("worker pay, maker           ", makerPay, 6);

        assertGt(viaMaker, viaPool, "the wallet got more stock for the same cash");
        assertGt(makerPay, poolPay, "and the worker who delivered it kept more");
        assertEq(IERC20(ASML).balanceOf(address(mmVenue)), 0, "the manager held nothing");
    }

    /// Whichever route is better on the day, the contract pays for what was
    /// delivered. When the pool happens to beat the feed, the router keeps the
    /// bounty entire, and nothing about that is special cased.
    function test_whenThePoolBeatsTheFeedTheRouterIsPaidInFull() public {
        if (block.chainid != 4663) { vm.skip(true); return; }
        AUM0Bid aum = _venue();
        _law(aum, alice, 20000e6);

        uint256 heldBefore = IERC20(NVDA).balanceOf(alice);
        vm.prank(router_worker);
        aum.rebalance(alice, _pool(10000e6));

        (, int256 answer,,,) = IFeedLike(NVDA_F).latestRoundData();
        uint256 atFeed = (10000e6 * 1e20) / uint256(answer);
        uint256 got = IERC20(NVDA).balanceOf(alice) - heldBefore;
        uint256 pay = IERC20(USDG).balanceOf(router_worker);
        emit log_named_decimal_uint("pool delivered", got, 18);
        emit log_named_decimal_uint("feed would be ", atFeed, 18);
        emit log_named_decimal_uint("worker kept   ", pay, 6);
        if (got >= atFeed) assertGt(pay, 99e6, "beat the feed, so nothing was deducted");
        else assertLt(pay, 100e6, "fell short of the feed, so the shortfall was deducted");
    }

    function _pool(uint256 amountIn) internal pure returns (AUM0Bid.Trade[] memory tr) {
        tr = new AUM0Bid.Trade[](1);
        tr[0] = AUM0Bid.Trade({sellAsset: 0, buyAsset: 1, amountIn: amountIn, fill: AUM0Bid.Fill.POOL, amountOut: 0});
    }
}

interface IFeedLike {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}
