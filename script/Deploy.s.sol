// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AUM0} from "../src/AUM0.sol";

/// v1 venue: USDG quote + NVDA on the fork-proven 0.05% pool. More assets
/// join by deploying a wider instance; the contract itself has no owner and
/// no setters, so a venue is what it is forever.
contract Deploy is Script {
    address constant ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant USDG   = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant NVDA   = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;

    function run() external {
        address[] memory tokens = new address[](1);
        tokens[0] = NVDA;
        address[] memory feeds = new address[](1);
        feeds[0] = NVDA_FEED;
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;
        uint8[] memory decs = new uint8[](1);
        decs[0] = 18;

        vm.startBroadcast();
        AUM0 aum = new AUM0(ROUTER, USDG, 6, 7 days, tokens, feeds, fees, decs);
        vm.stopBroadcast();
        console2.log("AUM0 deployed at:", address(aum));
    }
}
