// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0, IERC20} from "../src/AUM0.sol";
import {DeployV2} from "../script/DeployV2.s.sol";

/// Fork test for the v2 venue: one account carves a five stock portfolio and a
/// keeper fills all five legs through the live pools in a single rebalance.
///   forge test --match-contract V2ForkTest --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract V2ForkTest is Test {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    address alice = address(0xA11CE);
    address keeper = address(0xCAFE);

    function test_fiveStockPortfolioOneRebalance() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        DeployV2 d = new DeployV2();
        AUM0 aum = d.deployForTest();

        deal(USDG, alice, 500e6);
        vm.startPrank(alice);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        aum.deposit(0, 500e6);
        // 20% cash, then NVDA 20, SPCX 20, TSLA 15, AAPL 15, MSFT 10
        uint16[] memory t = new uint16[](16);
        t[0] = 2000; t[1] = 2000; t[2] = 2000; t[3] = 1500; t[4] = 1500; t[5] = 1000;
        aum.setTarget(t, 100, 200, 1e6); // band 2%, bounty 1 USDG
        vm.stopPrank();

        uint256 before = aum.drift(alice);
        emit log_named_uint("drift before (bps)", before);

        AUM0.Trade[] memory trades = new AUM0.Trade[](5);
        trades[0] = AUM0.Trade({sellAsset: 0, buyAsset: 1, amountIn: 97e6});   // NVDA
        trades[1] = AUM0.Trade({sellAsset: 0, buyAsset: 2, amountIn: 97e6});   // SPCX
        trades[2] = AUM0.Trade({sellAsset: 0, buyAsset: 3, amountIn: 72e6});   // TSLA
        trades[3] = AUM0.Trade({sellAsset: 0, buyAsset: 4, amountIn: 72e6});   // AAPL
        trades[4] = AUM0.Trade({sellAsset: 0, buyAsset: 5, amountIn: 48e6});   // MSFT
        vm.prank(keeper);
        aum.rebalance(alice, trades);

        uint256 after_ = aum.drift(alice);
        emit log_named_uint("drift after (bps)", after_);
        emit log_named_uint("keeper bounty (USDG 1e6)", IERC20(USDG).balanceOf(keeper));
        for (uint256 i = 1; i <= 5; ++i) {
            emit log_named_decimal_uint("stock held", aum.balanceOf(alice, i), 18);
        }
        emit log_named_decimal_uint("portfolio USD", aum.valueOf(alice), 18);

        assertLt(after_, before, "five legs, one call, strictly closer to the law");
        // residual = 3% sizing margin + the bounty leaving cash; both by design
        assertLt(after_, 700, "landed close across five stocks");
    }
}
