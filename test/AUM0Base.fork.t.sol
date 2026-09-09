// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {AUM0Merit} from "../src/AUM0Merit.sol";
import {IERC20} from "../src/AUM0.sol";

/// What a rebalance actually costs on Base, measured the same way it was
/// measured on Hood Chain: the contract itself prices every fill against the
/// official feed and reports what the wallet lost. On Hood the stock pools ate
/// 109 bps of a ten thousand dollar pass, and the worst of them ate 664. This
/// is the same question asked of a market that has real depth.
///   forge test --match-contract BaseCostForkTest --fork-url https://mainnet.base.org -vv
contract BaseCostForkTest is Test {
    address constant USDC  = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH  = 0x4200000000000000000000000000000000000006;
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant ETH_F = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant BTC_F = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D;
    address constant ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;   // SwapRouter02

    address owner = address(0x0A11CE);
    address worker = address(0xC0FFEE);

    function _venue() internal returns (AUM0Merit) {
        address[] memory tokens = new address[](2);
        address[] memory feeds = new address[](2);
        uint24[] memory fees = new uint24[](2);
        uint8[] memory decs = new uint8[](2);
        tokens[0] = WETH;  feeds[0] = ETH_F; fees[0] = 500; decs[0] = 18;
        tokens[1] = CBBTC; feeds[1] = BTC_F; fees[1] = 500; decs[1] = 8;
        return new AUM0Merit(ROUTER, USDC, 6, 7 days, tokens, feeds, fees, decs);
    }

    /// Twenty thousand dollars moved through the real pools, ten into ether and
    /// ten into bitcoin, priced against the official feeds by the contract.
    function test_whatARealRebalanceCostsHere() public {
        if (block.chainid != 8453) { vm.skip(true); return; }
        AUM0Merit aum = _venue();

        deal(USDC, owner, 30000e6);
        vm.startPrank(owner);
        IERC20(USDC).approve(address(aum), type(uint256).max);
        IERC20(WETH).approve(address(aum), type(uint256).max);
        IERC20(CBBTC).approve(address(aum), type(uint256).max);
        uint16[] memory t = new uint16[](3);
        t[0] = 3400; t[1] = 3300; t[2] = 3300;
        aum.setTarget(t, 100, 1000, 100e6);   // a hundred dollar bounty at full drift
        vm.stopPrank();

        uint256 before_ = aum.drift(owner);

        AUM0Merit.Trade[] memory tr = new AUM0Merit.Trade[](2);
        tr[0] = AUM0Merit.Trade({sellAsset: 0, buyAsset: 1, amountIn: 10000e6, fill: AUM0Merit.Fill.POOL, amountOut: 0});
        tr[1] = AUM0Merit.Trade({sellAsset: 0, buyAsset: 2, amountIn: 10000e6, fill: AUM0Merit.Fill.POOL, amountOut: 0});

        vm.recordLogs();
        vm.prank(worker);
        aum.rebalance(owner, tr);

        // the contract's own verdict on the fills: earned, slippage, paid
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 priced = keccak256("Priced(address,address,uint256,uint256,uint256)");
        uint256 earned; uint256 slip; uint256 paid;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == priced) (earned, slip, paid) = abi.decode(logs[i].data, (uint256, uint256, uint256));
        }

        emit log_named_uint("drift before        ", before_);
        emit log_named_uint("drift after         ", aum.drift(owner));
        emit log_named_decimal_uint("bounty earned       ", earned, 6);
        emit log_named_decimal_uint("lost to the pools   ", slip, 6);
        emit log_named_decimal_uint("worker actually paid", paid, 6);
        emit log_named_uint("cost of $20,000 in bps", (slip * 10000) / 20000e6);

        assertLt(aum.drift(owner), 300, "the wallet landed on its law");
        assertLt((slip * 10000) / 20000e6, 30, "and the round trip cost under thirty bps");
        assertEq(IERC20(USDC).balanceOf(address(aum)), 0, "the venue held nothing");
    }
}



import {DeployBase} from "../script/DeployBase.s.sol";

contract BaseDeployForkTest is Test {
    function test_theVenueDeploysAndReadsBase() public {
        if (block.chainid != 8453) { vm.skip(true); return; }
        AUM0Merit aum = new DeployBase().deployForTest();
        assertEq(aum.assetCount(), 3, "dollars, ether, bitcoin");
        (address t0,,,) = aum.assetAt(1);
        (address t1,,, uint8 d1) = aum.assetAt(2);
        assertEq(t0, 0x4200000000000000000000000000000000000006, "ether");
        assertEq(t1, 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf, "bitcoin");
        assertEq(d1, 8, "counted in its own decimals");
        emit log_named_uint("assets", aum.assetCount());
    }
}
