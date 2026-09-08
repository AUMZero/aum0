// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0Merit} from "../src/AUM0Merit.sol";
import {DeployMerit} from "../script/DeployMerit.s.sol";
import {IERC20} from "../src/AUM0.sol";

/// The merit edition against the live chain. Real feeds, real pools, real
/// prices, and a manager who only gets paid when the allocation they published
/// is standing above where this follower last paid them.
///   forge test --match-contract MeritForkTest --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract MeritForkTest is Test {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant SPY  = 0x117cc2133c37B721F49dE2A7a74833232B3B4C0C;
    uint256 constant N = 28;

    address manager = address(0x111A6E5);
    address follower = address(0xF0110E5);
    address worker = address(0xC0FFEE);

    function _venue() internal returns (AUM0Merit) {
        return new DeployMerit().deployForTest();
    }

    function _w(uint16 cash, uint16 nvda, uint16 spy) internal pure returns (uint16[] memory t) {
        t = new uint16[](N);
        t[0] = cash; t[1] = nvda; t[8] = spy;
    }

    function _ready(AUM0Merit aum, address who) internal {
        deal(USDG, who, 10000e6);
        vm.startPrank(who);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        IERC20(NVDA).approve(address(aum), type(uint256).max);
        IERC20(SPY).approve(address(aum), type(uint256).max);
        vm.stopPrank();
    }

    /// A manager publishes with a promise carved in, a stranger follows keeping
    /// their own money, a worker walks the wallet onto the law through real
    /// pools, and the manager is paid nothing, because on the day the work
    /// happened the policy stood exactly where the follower joined it.
    function test_aManagerIsNotPaidForStandingStill() public {
        if (block.chainid != 4663) { vm.skip(true); return; }
        AUM0Merit aum = _venue();

        vm.prank(manager);
        uint256 id = aum.publish(_w(2000, 4000, 4000), new uint16[](0), 0, 0, 1000, 5000, 1000);

        _ready(aum, follower);
        vm.prank(follower);
        aum.follow(id, 100, 1000, 100e6);

        uint256 before_ = aum.drift(follower);
        AUM0Merit.Trade[] memory tr = new AUM0Merit.Trade[](2);
        tr[0] = AUM0Merit.Trade({sellAsset: 0, buyAsset: 1, amountIn: 3900e6, fill: AUM0Merit.Fill.POOL, amountOut: 0});
        tr[1] = AUM0Merit.Trade({sellAsset: 0, buyAsset: 8, amountIn: 3900e6, fill: AUM0Merit.Fill.POOL, amountOut: 0});
        vm.prank(worker);
        aum.rebalance(follower, tr);

        (,, uint256 index) = aum.covenantOf(id);
        emit log_named_uint("drift before", before_);
        emit log_named_uint("drift after ", aum.drift(follower));
        emit log_named_decimal_uint("worker kept ", IERC20(USDG).balanceOf(worker), 6);
        emit log_named_decimal_uint("manager got ", IERC20(USDG).balanceOf(manager), 6);
        emit log_named_decimal_uint("policy index", index, 18);

        assertLt(aum.drift(follower), 600, "the follower was served through the real pools");
        assertGt(IERC20(USDG).balanceOf(worker), 0, "the worker was paid for real work");
        assertEq(IERC20(USDG).balanceOf(manager), 0, "the manager was paid nothing for standing still");
        assertEq(IERC20(USDG).balanceOf(address(aum)), 0, "the venue held nothing");
    }

    /// The promise holds against the live venue too. A manager who swore no
    /// holding would exceed half cannot put the world into one name, today or
    /// any day after.
    function test_thePromiseHoldsOnTheLiveChain() public {
        if (block.chainid != 4663) { vm.skip(true); return; }
        AUM0Merit aum = _venue();

        vm.prank(manager);
        uint256 id = aum.publish(_w(2000, 4000, 4000), new uint16[](0), 0, 0, 1000, 5000, 1000);

        uint16[] memory all = new uint16[](N);
        all[0] = 1000; all[1] = 9000;         // ninety percent into one name
        vm.prank(manager);
        vm.expectRevert(AUM0Merit.CovenantBroken.selector);
        aum.revise(id, all, new uint16[](0), 0, 0);

        uint16[] memory thin = new uint16[](N);
        thin[0] = 500; thin[1] = 5000; thin[8] = 4500;   // and the cash floor holds
        vm.prank(manager);
        vm.expectRevert(AUM0Merit.CovenantBroken.selector);
        aum.revise(id, thin, new uint16[](0), 0, 0);

        (uint16 maxAsset, uint16 minCash,) = aum.covenantOf(id);
        emit log_named_uint("no holding over bps", maxAsset);
        emit log_named_uint("cash never under bps", minCash);
        assertEq(maxAsset, 5000);
        assertEq(minCash, 1000);
    }
}
