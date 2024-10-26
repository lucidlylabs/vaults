// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {UsdeVaultRateProvider} from "../src/RateProvider/ethena-usde/EthenaVaultRateProvider.sol";
import {StakeeaseVaultRateProvider} from "../src/RateProvider/stakeease-sxeth/StakeeaseVaultRateProvider.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";

contract RateProviders is Test {
    uint256 private constant PRECISION = 1e18;
    address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
    address private constant FRAXUSDE_CURVE = 0x5dc1BF6f1e983C0b21EfB003c105133736fA0743;
    address private constant USDEDAI_CURVE = 0xF36a4BA50C603204c3FC6d2dA8b78A7b69CBC67d;
    address private constant USDE_LPT_PENDLE_MARCH2025 = 0xB451A36c8B6b2EAc77AD0737BA732818143A0E25;
    address private constant PENDLE_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
    address private constant WSXETH = 0x082F581C1105b4aaf2752D6eE5410984bd66Dd21;
    address private constant SXETHWETH_CURVE = 0x8b0fb150FbA4fc25cd4f6F5bd8a8F6944ad65Af0;

    IRateProvider rateProvider;
    IRateProvider sxethRateProvider;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("https://eth.merkle.io"));
        rateProvider = new UsdeVaultRateProvider();
        sxethRateProvider = new StakeeaseVaultRateProvider();
    }

    function testToken0Price() public view {
        uint256 rate = rateProvider.rate(SUSDE);
        console.log("token0", rate);
    }

    function testToken1Price() public view {
        uint256 rate = rateProvider.rate(SDAISUSDE_CURVE);
        console.log("token1", rate);
    }

    function testToken2Price() public view {
        uint256 rate = rateProvider.rate(FRAXUSDE_CURVE);
        console.log("token2", rate);
    }

    function testToken3Price() public view {
        uint256 rate = rateProvider.rate(USDEDAI_CURVE);
        console.log("token3", rate);
    }

    function testToken4Price() public view {
        uint256 rate = rateProvider.rate(USDE_LPT_PENDLE_MARCH2025);
        console.log("token4", rate);
    }

    function testInvalidParam() public {
        vm.expectRevert(bytes4(keccak256(bytes("RateProvider__InvalidParam()"))));
        rateProvider.rate(address(0x1));
    }

    function testSxeth0() public view {
        uint256 rate = sxethRateProvider.rate(WSXETH);
        console.log(rate);
    }

    function testSxeth1() public view {
        uint256 rate = sxethRateProvider.rate(SXETHWETH_CURVE);
        console.log(rate);
    }
}
