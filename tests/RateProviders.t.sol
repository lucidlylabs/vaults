// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {console} from "../lib/forge-std/src/console.sol";

import {UsdeVaultRateProvider} from "../src/RateProvider/ethena-usde/EthenaVaultRateProvider.sol";
import {EthenaVaultV2RateProvider} from "../src/RateProvider/ethena-usde/EthenaVaultV2RateProvider.sol";
import {PufEthVaultV2RateProvider} from "../src/RateProvider/puffer-pufeth/PufEthVaultV2RateProvider.sol";
import {StakeeaseVaultRateProvider} from "../src/RateProvider/stakeease-sxeth/StakeeaseVaultRateProvider.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {AnglesLiquidVaultRateProvider} from "../src/RateProvider/angles-liquid/AnglesLiquidVaultRateProvider.sol";

// pufEth vault assets
address constant PUFETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
address constant PUFETH_WSTETH_CURVE = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
address constant WETH_PUFETH_CURVE = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;
address constant GAUNTLET_WETH_CORE = 0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658;

// usde vault assets
address constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
address constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
address constant YPTSUSDE = 0x57fC2D9809F777Cd5c8C433442264B6E8bE7Fce4;
address constant GAUNTLET_USDC_PRIME = 0xdd0f28e19C1780eb6396170735D45153D261490d;

// contract RateProviders is Test {
//     IRateProvider usdeRateProvider;
//     IRateProvider pufEthRateProvider;
//     uint256 private constant PRECISION = 1e18;

//     function setUp() public {
//         vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));
//         usdeRateProvider = new EthenaVaultV2RateProvider();
//         pufEthRateProvider = new PufEthVaultV2RateProvider();
//     }

//     function test__FetchPufEthPrice() public view {
//         uint256 rate = pufEthRateProvider.rate(PUFETH);
//         console.log("PUFETH/ETH rate:", rate);
//     }

//     function test__FetchPufEthWstEthLpPrice() public view {
//         uint256 rate = pufEthRateProvider.rate(PUFETH_WSTETH_CURVE);
//         console.log("WSTETHLP/ETH rate:", rate);
//     }

//     function test__FetchWethPufEthLpPrice() public view {
//         uint256 rate = pufEthRateProvider.rate(WETH_PUFETH_CURVE);
//         console.log("WETHLP/ETH rate:", rate);
//     }

//     function test__GauntletWethCorePrice() public view {
//         uint256 rate = pufEthRateProvider.rate(GAUNTLET_WETH_CORE);
//         console.log("GWC share/ETH:", rate);
//     }

//     function test__FetchSusdePrice() public view {
//         uint256 rate = usdeRateProvider.rate(SUSDE);
//         console.log("SUSDE/USD rate:", rate);
//     }

//     function test__FetchMtEthenaPrice() public view {
//         uint256 rate = usdeRateProvider.rate(SDAISUSDE_CURVE);
//         console.log("MtEthena/USD rate:", rate);
//     }

//     function test__FetchYptsusdePrice() public view {
//         uint256 rate = usdeRateProvider.rate(YPTSUSDE);
//         console.log("YPTSUSDE/USD rate:", rate);
//     }

//     function test__FetchGauntletPrimePrice() public view {
//         uint256 rate = usdeRateProvider.rate(GAUNTLET_USDC_PRIME);
//         console.log("Gauntlet USDC prime share rate:", rate);
//     }
// }

// contract RateProviders is Test {
//     uint256 private constant PRECISION = 1e18;
//     address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
//     address private constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
//     address private constant FRAXUSDE_CURVE = 0x5dc1BF6f1e983C0b21EfB003c105133736fA0743;
//     address private constant USDEDAI_CURVE = 0xF36a4BA50C603204c3FC6d2dA8b78A7b69CBC67d;
//     address private constant USDE_LPT_PENDLE_MARCH2025 = 0xB451A36c8B6b2EAc77AD0737BA732818143A0E25;
//     address private constant PENDLE_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
//     address private constant WSXETH = 0x082F581C1105b4aaf2752D6eE5410984bd66Dd21;
//     address private constant SXETHWETH_CURVE = 0x8b0fb150FbA4fc25cd4f6F5bd8a8F6944ad65Af0;
//     address private constant SWBTCWBTC_CURVE = 0x73e4BeC1A111869F395cBB24F6676826BF86d905;
//     address private constant SWBTC = 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE;
//     address private constant GAUNTLET_WBTC_CORE = 0x443df5eEE3196e9b2Dd77CaBd3eA76C3dee8f9b2;

//     address immutable WRAPPED_ANGLES_S = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;
//     address immutable WRAPPED_S = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
//     address immutable WRAPPED_ANGLES_S_RATE_PROVIDER = 0x2d087C0999223997b77cc33BE5E7E8eC79396cea;
//     address immutable SPECTRA_LP_WRAPPED_ANGLES_S = 0xEc81ee88906ED712deA0a17A3Cd8A869eBFA89A0;
//     address immutable SILO_BORROWABLE_WS_DEPOSIT_TOKEN = 0x47d8490Be37ADC7Af053322d6d779153689E13C1;

//     IRateProvider rateProvider;
//     IRateProvider sxethRateProvider;
//     IRateProvider swbtcRateProvider;
//     IRateProvider anglesRateProvider;

//     function setUp() public {
//         vm.createSelectFork(vm.rpcUrl("https://rpc.ankr.com/sonic_mainnet"));
//         rateProvider = new AnglesLiquidVaultRateProvider();
//         sxethRateProvider = new StakeeaseVaultRateProvider();
//     }

    // function testToken0Price() public view {
    //     uint256 rate = rateProvider.rate(SUSDE);
    //     console.log("token0", rate);
    // }

    // function testToken1Price() public view {
    //     uint256 rate = rateProvider.rate(SDAISUSDE_CURVE);
    //     console.log("token1", rate);
    // }

    // function testToken2Price() public view {
    //     uint256 rate = rateProvider.rate(FRAXUSDE_CURVE);
    //     console.log("token2", rate);
    // }

    // function testToken3Price() public view {
    //     uint256 rate = rateProvider.rate(USDEDAI_CURVE);
    //     console.log("token3", rate);
    // }

    // function testToken4Price() public view {
    //     uint256 rate = rateProvider.rate(USDE_LPT_PENDLE_MARCH2025);
    //     console.log("token4", rate);
    // }

    // function testInvalidParam() public {
    //     vm.expectRevert(bytes4(keccak256(bytes("RateProvider__InvalidParam()"))));
    //     rateProvider.rate(address(0x1));
    // }

    // function testSxeth0() public view {
    //     uint256 rate = sxethRateProvider.rate(WSXETH);
    //     console.log(rate);
    // }

    // function testSxeth1() public view {
    //     uint256 rate = sxethRateProvider.rate(SXETHWETH_CURVE);
    //     console.log(rate);
    // }

    // function testSPrice() public view {
    //     uint256 rate = rateProvider.rate(WRAPPED_S);
    //     console.log(rate);
    // }

    // function testWrappedSPrice() public view {
    //     uint256 rate = rateProvider.rate(WRAPPED_ANGLES_S);
    //     console.log(rate);
    // }

    // function testLPWrappedSPrice() public view {
    //     uint256 rate = rateProvider.rate(SPECTRA_LP_WRAPPED_ANGLES_S);
    //     console.log(rate);
    // }

//     function testSiloPrice() public view {
//         uint256 rate = rateProvider.rate(SILO_BORROWABLE_WS_DEPOSIT_TOKEN);
//         console.log(rate);
//     }
// }
