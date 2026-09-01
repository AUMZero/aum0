// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0Wallet} from "../src/AUM0Wallet.sol";
import {IERC20} from "../src/AUM0.sol";
import {DeployWallet} from "../script/DeployWallet.s.sol";

/// The v3 venue against the live chain: a wallet that deposits nothing, grants
/// an allowance, and gets a five stock portfolio built inside it.
///   forge test --match-contract WalletVenueForkTest --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract WalletVenueForkTest is Test {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    address alice = address(0xA11CE);
    address keeper = address(0xCAFE);

    function test_fivePositionsBuiltInsideTheWallet() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        DeployWallet d = new DeployWallet();
        AUM0Wallet aum = d.deployForTest();

        deal(USDG, alice, 500e6);

        vm.startPrank(alice);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        // 20% cash, then NVDA 20, SPCX 20, TSLA 15, AAPL 15, MSFT 10
        uint16[] memory t = new uint16[](16);
        t[0] = 2000; t[1] = 2000; t[2] = 2000; t[3] = 1500; t[4] = 1500; t[5] = 1000;
        aum.setTarget(t, 100, 200, 1e6);
        vm.stopPrank();

        uint256 before = aum.drift(alice);
        emit log_named_uint("drift before (bps)", before);
        emit log_named_decimal_uint("wallet value before", aum.valueOf(alice), 18);

        AUM0Wallet.Trade[] memory trades = new AUM0Wallet.Trade[](5);
        trades[0] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: 1, amountIn: 97e6});
        trades[1] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: 2, amountIn: 97e6});
        trades[2] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: 3, amountIn: 72e6});
        trades[3] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: 4, amountIn: 72e6});
        trades[4] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: 5, amountIn: 48e6});

        vm.prank(keeper);
        aum.rebalance(alice, trades);

        emit log_named_uint("drift after (bps)", aum.drift(alice));
        emit log_named_decimal_uint("keeper earned (USDG)", IERC20(USDG).balanceOf(keeper), 6);
        for (uint256 i = 1; i <= 5; ++i) {
            emit log_named_decimal_uint("held in HER wallet", aum.heldBy(alice, i), 18);
        }

        assertLt(aum.drift(alice), before, "the wallet moved toward its law");
        assertLt(aum.drift(alice), 700, "and landed close across five stocks");

        // the point of the whole design
        for (uint256 i; i < 6; ++i) {
            (address token,,,) = aum.assetAt(i);
            assertEq(IERC20(token).balanceOf(address(aum)), 0, "the manager holds nothing, ever");
        }
    }
}
