// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0Wallet} from "../src/AUM0Wallet.sol";
import {IERC20} from "../src/AUM0.sol";
import {DeployWalletV4} from "../script/DeployWalletV4.s.sol";

/// The widened venue against the live chain. The thing worth proving is not
/// that more tickers fit in an array: it is that a portfolio with a bond leg
/// can be built and held here, which was impossible while the venue was all
/// equities.
///   forge test --match-contract V4ForkTest --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract V4ForkTest is Test {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    // asset 0 is the quote, so the deploy list sits at 1..26
    uint256 constant SPY = 8;
    uint256 constant QQQ = 16;
    uint256 constant SGOV = 17;  // the treasury bill
    uint256 constant SLV = 18;
    uint256 constant FIRST_NEW = 16;

    address alice = address(0xA11CE);
    address keeper = address(0xCAFE);

    function test_sixtyFortyOnChain() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        DeployWalletV4 d = new DeployWalletV4();
        AUM0Wallet aum = d.deployForTest();
        assertEq(aum.assetCount(), 27, "quote plus twenty six");

        deal(USDG, alice, 1000e6);
        vm.startPrank(alice);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        // the oldest portfolio in finance: sixty stocks, forty bonds, a little cash
        uint16[] memory t = new uint16[](27);
        t[0] = 500;        // cash, to pay the worker
        t[SPY] = 5700;     // the market
        t[SGOV] = 3800;    // treasury bills
        aum.setTarget(t, 100, 200, 1e6);
        vm.stopPrank();

        uint256 before = aum.drift(alice);
        emit log_named_uint("drift before (bps)", before);

        AUM0Wallet.Trade[] memory trades = new AUM0Wallet.Trade[](2);
        trades[0] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: SPY, amountIn: 553e6});
        trades[1] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: SGOV, amountIn: 369e6});

        vm.prank(keeper);
        aum.rebalance(alice, trades);

        emit log_named_uint("drift after (bps)", aum.drift(alice));
        emit log_named_decimal_uint("SPY held", aum.heldBy(alice, SPY), 18);
        emit log_named_decimal_uint("SGOV held", aum.heldBy(alice, SGOV), 18);
        emit log_named_decimal_uint("keeper earned (USDG)", IERC20(USDG).balanceOf(keeper), 6);

        assertLt(aum.drift(alice), before, "moved toward the law");
        assertLt(aum.drift(alice), 600, "and landed on a sixty forty");
        assertGt(aum.heldBy(alice, SGOV), 0, "the bond leg is real and in her wallet");
        assertEq(IERC20(USDG).balanceOf(address(aum)), 0, "the manager holds nothing");
    }

    /// Every new asset must price and trade, or it does not belong in the venue.
    function test_everyNewAssetPricesAndTrades() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        DeployWalletV4 d = new DeployWalletV4();
        AUM0Wallet aum = d.deployForTest();

        deal(USDG, alice, 4000e6);
        vm.startPrank(alice);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        // an equal slice of all eleven new assets, the rest in cash
        uint16[] memory t = new uint16[](27);
        t[0] = 4500;                                              // 4500 + eleven slices of 500
        for (uint256 i = FIRST_NEW; i < FIRST_NEW + 11; ++i) t[i] = 500;
        aum.setTarget(t, 100, 300, 1e6);
        vm.stopPrank();

        uint256 before = aum.drift(alice);
        emit log_named_uint("drift before (bps)", before);

        AUM0Wallet.Trade[] memory buys = new AUM0Wallet.Trade[](11);
        for (uint256 i; i < 11; ++i) {
            buys[i] = AUM0Wallet.Trade({sellAsset: 0, buyAsset: FIRST_NEW + i, amountIn: 190e6});
        }
        vm.prank(keeper);
        aum.rebalance(alice, buys);

        emit log_named_uint("drift after (bps)", aum.drift(alice));
        for (uint256 i = FIRST_NEW; i < FIRST_NEW + 11; ++i) {
            (address token,,,) = aum.assetAt(i);
            assertGt(aum.heldBy(alice, i), 0, "the new asset landed in her wallet");
            assertEq(IERC20(token).balanceOf(address(aum)), 0, "and none of it stayed with the manager");
        }
        emit log_named_decimal_uint("wallet value (usd)", aum.valueOf(alice), 18);
        assertLt(aum.drift(alice), before, "eleven new assets, one transaction");
    }
}
