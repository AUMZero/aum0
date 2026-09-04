// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AUM0Shelf} from "../src/AUM0Shelf.sol";
import {StrictERC20, MockFeed, MockRouter} from "../test/AUM0Wallet.t.sol";

/// Local dev harness for the shelf web page. Deploys a mock venue (fifteen
/// stocks at real-ish prices) plus the shelf onto a plain anvil chain, then
/// seeds it: three funds carved, four wallets adopted, four rebalances done.
/// Never meant for a real chain: the tokens are mints and the router is a
/// mock. Run:
///   anvil --port 8545 --chain-id 4663
///   forge script script/SeedShelfLocal.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract SeedShelfLocal is Script {
    // anvil's standard prefunded dev keys; public knowledge, local only
    uint256 constant DEPLOYER = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant ALICE  = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant BOB    = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant CAROL  = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    uint256 constant DAVE   = 0x47e179ec197488593b187f80a4eb0eb7d49dda57b4afef42fd5498c5c6f0fc31;
    uint256 constant KEEPER = 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba;

    string[15] tickers = ["NVDA","SPCX","TSLA","AAPL","MSFT","AMZN","MU","SPY","PLTR","SNDK","INTC","AMD","GOOGL","META","USAR"];
    int256[15] prices = [int256(219e8), 143.54e8, 357.74e8, 326.61e8, 500.71e8, 255.12e8, 944.03e8, 763.48e8, 183.02e8, 1571.50e8, 88.74e8, 457.71e8, 335.57e8, 581.31e8, 17.44e8];

    StrictERC20 usdg;
    MockRouter router;
    AUM0Shelf shelf;
    bytes32 lawMag5;
    bytes32 lawSixty;
    bytes32 lawEqual;

    function run() external {
        vm.startBroadcast(DEPLOYER);
        _deployVenue();
        _mintAndCarve();
        vm.stopBroadcast();

        _join(ALICE, lawMag5);
        _join(DAVE, lawMag5);
        _join(CAROL, lawSixty);
        _join(BOB, lawEqual);

        vm.startBroadcast(KEEPER);
        _work();
        vm.stopBroadcast();

        console2.log("shelf:", address(shelf));
        console2.log("usdg:", address(usdg));
        console2.log("alice drift:", shelf.drift(vm.addr(ALICE)));
        console2.log("dave drift:", shelf.drift(vm.addr(DAVE)));
        console2.log("carol drift:", shelf.drift(vm.addr(CAROL)));
        console2.log("bob drift:", shelf.drift(vm.addr(BOB)));
    }

    function _deployVenue() internal {
        usdg = new StrictERC20("USDG", 6);
        router = new MockRouter(usdg);

        address[] memory tokens = new address[](15);
        address[] memory feeds = new address[](15);
        uint24[] memory fees = new uint24[](15);
        uint8[] memory decs = new uint8[](15);
        for (uint256 i; i < 15; ++i) {
            StrictERC20 t = new StrictERC20(tickers[i], 18);
            MockFeed f = new MockFeed(prices[i]);
            router.register(t, f);
            tokens[i] = address(t); feeds[i] = address(f); fees[i] = 3000; decs[i] = 18;
        }
        shelf = new AUM0Shelf(address(router), address(usdg), 6, 7 days, tokens, feeds, fees, decs);
    }

    function _mintAndCarve() internal {
        usdg.mint(vm.addr(ALICE), 500e6);
        usdg.mint(vm.addr(BOB), 160e6);
        usdg.mint(vm.addr(CAROL), 200e6);
        usdg.mint(vm.addr(DAVE), 250e6);

        uint16[] memory mag5 = _law16();
        mag5[0] = 2000; mag5[1] = 2000; mag5[2] = 2000; mag5[3] = 1500; mag5[4] = 1500; mag5[5] = 1000;
        lawMag5 = shelf.carveLaw(mag5);

        uint16[] memory sixty = _law16();
        sixty[0] = 4000; sixty[8] = 6000;
        lawSixty = shelf.carveLaw(sixty);

        uint16[] memory equal = _law16();
        for (uint256 i; i < 16; ++i) equal[i] = 625;
        lawEqual = shelf.carveLaw(equal);
    }

    function _work() internal {
        AUM0Shelf.Trade[] memory tr = new AUM0Shelf.Trade[](5);
        tr[0] = AUM0Shelf.Trade(0, 1, 97e6);
        tr[1] = AUM0Shelf.Trade(0, 2, 97e6);
        tr[2] = AUM0Shelf.Trade(0, 3, 72e6);
        tr[3] = AUM0Shelf.Trade(0, 4, 72e6);
        tr[4] = AUM0Shelf.Trade(0, 5, 48e6);
        shelf.rebalance(vm.addr(ALICE), tr);

        tr[0].amountIn = 48e6; tr[1].amountIn = 48e6; tr[2].amountIn = 36e6; tr[3].amountIn = 36e6; tr[4].amountIn = 24e6;
        shelf.rebalance(vm.addr(DAVE), tr);

        AUM0Shelf.Trade[] memory one = new AUM0Shelf.Trade[](1);
        one[0] = AUM0Shelf.Trade(0, 8, 116e6);
        shelf.rebalance(vm.addr(CAROL), one);

        AUM0Shelf.Trade[] memory legs = new AUM0Shelf.Trade[](15);
        for (uint256 i; i < 15; ++i) legs[i] = AUM0Shelf.Trade(0, i + 1, 9.7e6);
        shelf.rebalance(vm.addr(BOB), legs);
    }

    function _join(uint256 pk, bytes32 lawId) internal {
        vm.startBroadcast(pk);
        usdg.approve(address(shelf), type(uint256).max);
        shelf.adopt(lawId, 100, 200, 1e6);
        vm.stopBroadcast();
    }

    function _law16() internal pure returns (uint16[] memory t) {
        t = new uint16[](16);
    }
}
