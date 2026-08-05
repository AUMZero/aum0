// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0, IERC20} from "../src/AUM0.sol";

/// Fork test against live Hood Chain: a real account, a real target, and a
/// real rebalance filled on the real NVDA/USDG pool through the live router.
///   forge test --match-contract ForkTest --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract ForkTest is Test {
    address constant ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant USDG   = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant NVDA   = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    uint24 constant NVDA_POOL_FEE = 500; // the fork-proven 0.05% pool

    address alice = address(0xA11CE);
    address keeper = address(0xCAFE);

    function test_liveRebalanceOnRealPool() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        address[] memory tokens = new address[](1);
        tokens[0] = NVDA;
        address[] memory feeds = new address[](1);
        feeds[0] = NVDA_FEED;
        uint24[] memory fees = new uint24[](1);
        fees[0] = NVDA_POOL_FEE;
        uint8[] memory decs = new uint8[](1);
        decs[0] = 18;

        AUM0 aum = new AUM0(ROUTER, USDG, 6, 7 days, tokens, feeds, fees, decs);

        // fund alice with real USDG lifted from the pool's own reserves
        deal(USDG, alice, 200e6);
        vm.startPrank(alice);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        aum.deposit(0, 200e6);
        uint16[] memory t = new uint16[](2);
        t[0] = 5000; t[1] = 5000; // half cash, half NVDA
        aum.setTarget(t, 100, 150, 5e5); // band 1.5%, bounty 0.5 USDG
        vm.stopPrank();

        uint256 before = aum.drift(alice);
        emit log_named_uint("drift before (bps)", before);

        AUM0.Trade[] memory trades = new AUM0.Trade[](1);
        trades[0] = AUM0.Trade({sellAsset: 0, buyAsset: 1, amountIn: 100e6});
        vm.prank(keeper);
        aum.rebalance(alice, trades);

        uint256 after_ = aum.drift(alice);
        emit log_named_uint("drift after (bps)", after_);
        emit log_named_uint("keeper bounty (USDG 1e6)", IERC20(USDG).balanceOf(keeper));
        emit log_named_decimal_uint("NVDA held", aum.balanceOf(alice, 1), 18);
        emit log_named_decimal_uint("portfolio USD", aum.valueOf(alice), 18);

        assertLt(after_, before, "a stranger moved a real account toward its target");
        assertLt(after_, 200, "landed close");
        assertGt(IERC20(USDG).balanceOf(keeper), 49e4, "and got paid in proportion to the help");
    }
}
