// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AUM0Merit} from "../src/AUM0Merit.sol";

/// The merit edition on Base, over the portfolio most people actually hold:
/// dollars, ether and bitcoin. Both pools run to millions and both feeds are
/// official and update around the clock, so a rebalance here costs the wallet
/// seventeen basis points instead of the hundred and nine the thin venues
/// charged, and the worker who does it clears real money instead of cents.
///
/// Frozen at deploy forever, as always. No owner, no admin, no upgrade path.
contract DeployBase is Script {
    address constant ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;   // Uniswap SwapRouter02
    address constant USDC   = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH   = 0x4200000000000000000000000000000000000006;
    address constant CBBTC  = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant ETH_F  = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;   // ETH / USD
    address constant BTC_F  = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D;   // cbBTC / USD

    function run() external {
        vm.startBroadcast();
        AUM0Merit aum = _deploy();
        vm.stopBroadcast();
        console2.log("AUM0 merit edition on Base deployed at:", address(aum));
    }

    function deployForTest() external returns (AUM0Merit) {
        return _deploy();
    }

    function _deploy() internal returns (AUM0Merit) {
        address[] memory tokens = new address[](2);
        address[] memory feeds  = new address[](2);
        uint24[]  memory fees   = new uint24[](2);
        uint8[]   memory decs   = new uint8[](2);

        tokens[0] = WETH;  feeds[0] = ETH_F; fees[0] = 500; decs[0] = 18;
        tokens[1] = CBBTC; feeds[1] = BTC_F; fees[1] = 500; decs[1] = 8;

        // These feeds run around the clock, unlike a stock feed that sleeps
        // through the weekend, so the staleness window is a day and not a week.
        return new AUM0Merit(ROUTER, USDC, 6, 1 days, tokens, feeds, fees, decs);
    }
}
