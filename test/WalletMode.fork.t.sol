// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../src/AUM0.sol";

interface IRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256);
}

/// The v3 mechanic, proven before it is built: tokens never leave the owner's
/// wallet except inside the rebalancing transaction itself, and the only
/// address this contract can ever send to is the owner.
contract WalletModeProbe {
    IRouter constant ROUTER = IRouter(0xCaf681a66D020601342297493863E78C959E5cb2);

    /// Pull from the owner's wallet, swap, hand the result straight back.
    /// `owner` is the only destination this function can name.
    function pullSwapReturn(address owner, address tokenIn, address tokenOut, uint24 fee, uint256 amountIn)
        external
        returns (uint256 out)
    {
        IERC20(tokenIn).transferFrom(owner, address(this), amountIn);
        IERC20(tokenIn).approve(address(ROUTER), amountIn);
        out = ROUTER.exactInputSingle(IRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: owner,          // straight to the wallet, never held here
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));
    }
}

contract WalletModeForkTest is Test {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    uint24  constant FEE  = 500;

    address alice = address(0xA11CE);

    function test_stocksNeverLeaveTheWallet() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        WalletModeProbe probe = new WalletModeProbe();
        deal(USDG, alice, 100e6);

        // alice grants an allowance. she deposits nothing.
        vm.prank(alice);
        IERC20(USDG).approve(address(probe), type(uint256).max);

        uint256 cashBefore = IERC20(USDG).balanceOf(alice);
        uint256 stockBefore = IERC20(NVDA).balanceOf(alice);
        emit log_named_decimal_uint("wallet USDG before", cashBefore, 6);
        emit log_named_decimal_uint("wallet NVDA before", stockBefore, 18);

        // a stranger runs the rebalance. alice is not in this transaction.
        vm.prank(address(0xCAFE));
        uint256 out = probe.pullSwapReturn(alice, USDG, NVDA, FEE, 50e6);

        uint256 cashAfter = IERC20(USDG).balanceOf(alice);
        uint256 stockAfter = IERC20(NVDA).balanceOf(alice);
        emit log_named_decimal_uint("wallet USDG after", cashAfter, 6);
        emit log_named_decimal_uint("wallet NVDA after", stockAfter, 18);
        emit log_named_decimal_uint("swap output", out, 18);

        assertEq(cashAfter, cashBefore - 50e6, "cash left the wallet only by the traded amount");
        assertGt(stockAfter, stockBefore, "the stock landed in her own wallet");
        assertEq(IERC20(NVDA).balanceOf(address(probe)), 0, "the manager holds nothing");
        assertEq(IERC20(USDG).balanceOf(address(probe)), 0, "the manager holds nothing");
    }
}
