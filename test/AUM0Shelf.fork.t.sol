// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AUM0Shelf} from "../src/AUM0Shelf.sol";
import {IERC20} from "../src/AUM0.sol";
import {DeployShelf} from "../script/DeployShelf.s.sol";

/// The shelf against the live chain: one carver manufactures a fund, two
/// wallets of different sizes adopt it, one keeper serves them both on the
/// real pools. Nobody deposits anything and nobody collects a fee.
///   forge test --match-contract ShelfForkTest --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract ShelfForkTest is Test {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    address carver = address(0xCA23E2);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address keeper = address(0xCAFE);

    function test_oneFundTwoWalletsOnTheRealPools() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        DeployShelf d = new DeployShelf();
        AUM0Shelf aum = d.deployForTest();

        // the carver manufactures a fund: 20% cash, NVDA 20, SPCX 20, TSLA 15, AAPL 15, MSFT 10
        uint16[] memory law = new uint16[](16);
        law[0] = 2000; law[1] = 2000; law[2] = 2000; law[3] = 1500; law[4] = 1500; law[5] = 1000;
        vm.prank(carver);
        bytes32 lawId = aum.carveLaw(law);

        deal(USDG, alice, 500e6);
        deal(USDG, bob, 120e6);
        vm.startPrank(alice);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        aum.adopt(lawId, 100, 200, 1e6);
        vm.stopPrank();
        vm.startPrank(bob);
        IERC20(USDG).approve(address(aum), type(uint256).max);
        aum.adopt(lawId, 100, 200, 1e6);
        vm.stopPrank();

        emit log_named_uint("alice drift before (bps)", aum.drift(alice));
        emit log_named_uint("bob drift before (bps)", aum.drift(bob));

        AUM0Shelf.Trade[] memory forAlice = new AUM0Shelf.Trade[](5);
        forAlice[0] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 1, amountIn: 97e6});
        forAlice[1] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 2, amountIn: 97e6});
        forAlice[2] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 3, amountIn: 72e6});
        forAlice[3] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 4, amountIn: 72e6});
        forAlice[4] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 5, amountIn: 48e6});

        AUM0Shelf.Trade[] memory forBob = new AUM0Shelf.Trade[](5);
        forBob[0] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 1, amountIn: 23e6});
        forBob[1] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 2, amountIn: 23e6});
        forBob[2] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 3, amountIn: 17e6});
        forBob[3] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 4, amountIn: 17e6});
        forBob[4] = AUM0Shelf.Trade({sellAsset: 0, buyAsset: 5, amountIn: 11e6});

        vm.prank(keeper);
        aum.rebalance(alice, forAlice);
        vm.prank(keeper);
        aum.rebalance(bob, forBob);

        emit log_named_uint("alice drift after (bps)", aum.drift(alice));
        emit log_named_uint("bob drift after (bps)", aum.drift(bob));
        emit log_named_decimal_uint("keeper earned (USDG)", IERC20(USDG).balanceOf(keeper), 6);

        assertLt(aum.drift(alice), 700, "alice landed on the fund");
        assertLt(aum.drift(bob), 700, "bob landed on the same fund");
        assertEq(IERC20(USDG).balanceOf(carver), 0, "the carver is paid nothing");

        // the point of the whole design
        for (uint256 i; i < 16; ++i) {
            (address token,,,) = aum.assetAt(i);
            assertEq(IERC20(token).balanceOf(address(aum)), 0, "the manager holds nothing, ever");
        }
    }
}
