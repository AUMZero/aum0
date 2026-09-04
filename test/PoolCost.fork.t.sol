// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../src/AUM0.sol";

/// What the chain's own pools actually charge, asset by asset, at a size a
/// real portfolio trades. Ten thousand dollars of USDG into each of the venue's
/// twenty six assets, against that asset's official feed at the same block.
/// Nothing here is a model. It is the pool answering.
///   forge test --match-contract PoolCostTest --fork-url https://rpc.mainnet.chain.robinhood.com -vv
contract PoolCostTest is Test {
    address constant ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant USDG   = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant BID    = 0xb0C34AC5e846e0159f711Db84802D512E916A51F;

    uint256 constant SIZE = 10_000e6;

    address buyer = address(0xB0FFEE);

    function test_whatTheHoodPoolsChargeOnTenThousandDollars() public {
        if (block.chainid != 4663) { vm.skip(true); return; }

        uint256 n = IBid(BID).assetCount();
        emit log_named_uint("block", block.number);
        emit log_string("symbol   shortfall vs feed      cost of $10,000");

        uint256 worstBps; string memory worstSym;
        uint256 sum; uint256 counted; uint256 overOnePct;

        for (uint256 i = 1; i < n; ++i) {
            (address token, address feed, uint24 fee,) = IBid(BID).assetAt(i);

            uint256 snap = vm.snapshotState();
            deal(USDG, buyer, SIZE);
            vm.startPrank(buyer);
            IERC20(USDG).approve(ROUTER, SIZE);
            uint256 out;
            try IRouter(ROUTER).exactInputSingle(IRouter.ExactInputSingleParams({
                tokenIn: USDG, tokenOut: token, fee: fee, recipient: buyer,
                amountIn: SIZE, amountOutMinimum: 0, sqrtPriceLimitX96: 0
            })) returns (uint256 o) { out = o; } catch { out = 0; }
            vm.stopPrank();

            string memory sym = IERC20Meta(token).symbol();
            if (out == 0) {
                emit log_string(string.concat(_pad(sym), "  no fill at this size"));
                vm.revertToState(snap);
                continue;
            }

            (, int256 answer,,,) = IFeed(feed).latestRoundData();
            uint256 atFeed = (SIZE * 1e20) / uint256(answer);
            uint256 bps = out >= atFeed ? 0 : ((atFeed - out) * 10000) / atFeed;
            uint256 dollars = (bps * 10_000e18) / 10000;

            emit log_string(string.concat(
                _pad(sym), "  ", _bps(bps), "        ", _usd(dollars)
            ));

            sum += bps; counted++;
            if (bps > 100) overOnePct++;
            if (bps > worstBps) { worstBps = bps; worstSym = sym; }
            vm.revertToState(snap);
        }

        emit log_string("");
        emit log_named_uint("assets measured                  ", counted);
        emit log_named_uint("average shortfall (bps)          ", sum / counted);
        emit log_named_uint("assets costing over one percent  ", overOnePct);
        emit log_named_string("worst                            ", worstSym);
        emit log_named_uint("worst shortfall (bps)            ", worstBps);
        emit log_string("");
        emit log_string("A hundred dollar bounty is 100 bps of a ten thousand dollar leg.");
        emit log_string("Every asset above that line costs the wallet more than the whole");
        emit log_string("bounty, which is exactly what the bid edition refuses to pay for.");
    }

    function _pad(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (b.length >= 8) return s;
        bytes memory out = new bytes(8);
        for (uint256 i; i < 8; ++i) out[i] = i < b.length ? b[i] : bytes1(" ");
        return string(out);
    }

    function _bps(uint256 v) internal pure returns (string memory) {
        return string.concat(_pad(vm.toString(v)), " bps");
    }

    function _usd(uint256 wad) internal pure returns (string memory) {
        return string.concat("$", vm.toString(wad / 1e18), ".",
            _two((wad % 1e18) / 1e16));
    }

    function _two(uint256 v) internal pure returns (string memory) {
        return v < 10 ? string.concat("0", vm.toString(v)) : vm.toString(v);
    }
}

interface IBid {
    function assetCount() external view returns (uint256);
    function assetAt(uint256) external view returns (address, address, uint24, uint8);
}
interface IFeed { function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80); }
interface IERC20Meta { function symbol() external view returns (string memory); }
interface IRouter {
    struct ExactInputSingleParams {
        address tokenIn; address tokenOut; uint24 fee; address recipient;
        uint256 amountIn; uint256 amountOutMinimum; uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256);
}
