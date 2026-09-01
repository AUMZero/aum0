// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AUM0Wallet} from "../src/AUM0Wallet.sol";

/// Wallet-edition venue: USDG quote + the fifteen Hood Chain stocks that have
/// both a live feed and a real USDG pool, each pinned to its deepest sensible
/// fee tier, measured on-chain 2026-08-31. Frozen at deploy forever.
contract DeployWallet is Script {
    address constant ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant USDG   = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    function run() external {
        vm.startBroadcast();
        AUM0Wallet aum = _deploy();
        vm.stopBroadcast();
        console2.log("AUM0 wallet edition deployed at:", address(aum));
    }

    function deployForTest() external returns (AUM0Wallet) {
        return _deploy();
    }

    function _deploy() internal returns (AUM0Wallet) {
        address[] memory tokens = new address[](15);
        address[] memory feeds  = new address[](15);
        uint24[]  memory fees   = new uint24[](15);
        uint8[]   memory decs   = new uint8[](15);

        // ticker           token                                        feed                                         pool
        _set(tokens, feeds, fees, 0,  0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC, 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15, 500);   // NVDA  $2.86M
        _set(tokens, feeds, fees, 1,  0x4a0E65A3EcceC6dBe60AE065F2e7bb85Fae35eEa, 0xB265810950ba6c5C0Ff821c9963014a56fD8Bffb, 500);   // SPCX  $510k
        _set(tokens, feeds, fees, 2,  0x322F0929c4625eD5bAd873c95208D54E1c003b2d, 0x4A1166a659A55625345e9515b32adECea5547C38, 3000);  // TSLA  $98k
        _set(tokens, feeds, fees, 3,  0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9, 0x6B22A786bAa607d76728168703a39Ea9C99f2cD0, 3000);  // AAPL  $95k
        _set(tokens, feeds, fees, 4,  0xe93237C50D904957Cf27E7B1133b510C669c2e74, 0x45C3C877C15E6BA2EBB19eA114Ea508d14C1Af2E, 3000);  // MSFT  $90k
        _set(tokens, feeds, fees, 5,  0x12f190a9F9d7D37a250758b26824B97CE941bF54, 0xD5a1508ceD74c084eBf3cBe853e2C968fB2a651C, 3000);  // AMZN  $81k
        _set(tokens, feeds, fees, 6,  0xfF080c8ce2E5feadaCa0Da81314Ae59D232d4afD, 0x425EEFdCf05ed6526C3cE61Af99429A228a6d596, 3000);  // MU    $74k
        _set(tokens, feeds, fees, 7,  0x117cc2133c37B721F49dE2A7a74833232B3B4C0C, 0x319724394D3A0e3669269846abE664Cd621f9f6A, 500);   // SPY   $28k
        _set(tokens, feeds, fees, 8,  0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A, 0x820ABedFF239034956B7A9d2F0a331f9F075eB4c, 3000);  // PLTR  $25k
        _set(tokens, feeds, fees, 9,  0xB90A19fF0Af67f7779afF50A882A9CfF42446400, 0xfb133Fa4B7b385802B693a293606682Df47109A3, 10000); // SNDK  $15k
        _set(tokens, feeds, fees, 10, 0xc72b96e0E48ecd4DC75E1e45396e26300BC39681, 0x3f390C5C24628Ac7C489515402235FeAD71D1913, 3000);  // INTC  $14k
        _set(tokens, feeds, fees, 11, 0x86923f96303D656E4aa86D9d42D1e57ad2023fdC, 0x943A29E7ae51A4798823ca9eEd2ed533B2A22C72, 3000);  // AMD   $13k
        _set(tokens, feeds, fees, 12, 0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3, 0xF6f373a037c30F0e5010d854385cA89185AE638b, 500);   // GOOGL $10k
        _set(tokens, feeds, fees, 13, 0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35, 0x7C38C00C30BEe9378381E7B6135d7283356D71b1, 3000);  // META  $7.7k
        _set(tokens, feeds, fees, 14, 0xd917B029C761D264c6A312BBbcDA868658eF86a6, 0x451B1295aA84FD6d6b58af1a5002eA1b1A1913A0, 3000);  // USAR  $5.9k
        for (uint256 i; i < 15; ++i) decs[i] = 18;
        return new AUM0Wallet(ROUTER, USDG, 6, 7 days, tokens, feeds, fees, decs);
    }

    function _set(address[] memory t, address[] memory f, uint24[] memory p, uint256 i, address token, address feed, uint24 fee) internal pure {
        t[i] = token; f[i] = feed; p[i] = fee;
    }
}
