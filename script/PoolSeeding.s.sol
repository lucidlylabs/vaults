// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "../tests/PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {UsdeVaultRateProvider} from "../src/RateProvider/ethena-usde/EthenaVaultRateProvider.sol";
import {StakeeaseVaultRateProvider} from "../src/RateProvider/stakeease-sxeth/StakeeaseVaultRateProvider.sol";

contract PoolSeeding is Script {
    Pool pool = Pool(0x001DF2Cc0c3433beAd3703575F13841d2EBC078f);
    PoolToken poolToken = PoolToken(0x4d733dF57E137b074A6CA88D26cbe1bc79608033);
    Vault vault = Vault(0x4CC72CAfB1d87068Cae2da03243317F96E863a9E);
    MockRateProvider rateProvider = MockRateProvider(0xF1c0629A8B37A02fE2123f4B8F2A38C58961C6D4);

    uint256 public amplification;
    uint256 private PRECISION = 1e18;
    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
    address private constant FRAXUSDE_CURVE = 0x5dc1BF6f1e983C0b21EfB003c105133736fA0743;
    address private constant USDEDAI_CURVE = 0xF36a4BA50C603204c3FC6d2dA8b78A7b69CBC67d;
    address private constant USDE_LPT_PENDLE_MARCH2025 = 0xB451A36c8B6b2EAc77AD0737BA732818143A0E25;

    MockToken token0 = MockToken(SUSDE);
    MockToken token1 = MockToken(SDAISUSDE_CURVE);
    MockToken token2 = MockToken(FRAXUSDE_CURVE);
    MockToken token3 = MockToken(USDEDAI_CURVE);
    MockToken token4 = MockToken(USDE_LPT_PENDLE_MARCH2025);

    address[] public tokens = new address[](5);
    uint256[] public weights = new uint256[](5);
    address[] public rateProviders = new address[](5);

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);
        tokens[4] = address(token4);

        weights[0] = 20 * PRECISION / 100;
        weights[1] = 40 * PRECISION / 100;
        weights[2] = 5 * PRECISION / 100;
        weights[3] = 15 * PRECISION / 100;
        weights[4] = 20 * PRECISION / 100;

        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);
        rateProviders[2] = address(rateProvider);
        rateProviders[3] = address(rateProvider);
        rateProviders[4] = address(rateProvider);

        uint256 total = 1350 ether;

        uint256[] memory amounts = new uint256[](5);

        for (uint256 i = 0; i < 5; i++) {
            address token = tokens[i];
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            uint256 amount = (total * weights[i]) / rateProvider.rate(token);
            amounts[i] = amount;

            console.log("amount of token", MockToken(token).symbol(), " to be added =", amount);
            console.log("balance =", MockToken(token).balanceOf(ADMIN_ADDRESS));
        }

        uint256 lpReceived = pool.addLiquidity(amounts, 0, ADMIN_ADDRESS);

        poolToken.approve(address(vault), lpReceived);
        uint256 shares = vault.deposit(lpReceived, ADMIN_ADDRESS);
        vault.transfer(ADMIN_ADDRESS, shares / 90);

        vm.stopBroadcast();
    }
}

contract SeedSxETHPool is Script {
    Pool pool = Pool(0x188B679c0bAf56b9838584AfaC82D713e68112fC);
    PoolToken poolToken = PoolToken(0x34e523B10B85c41515807811456613Cf2a077C77);
    Vault vault = Vault(0xCDE68b2DB42cfA27ad9A653eEAc4f23297227175);
    MockRateProvider rateProvider = MockRateProvider(0x144Bec263C77E9d20946d2A8A96507d68c4922D5);

    uint256 public amplification;
    uint256 private PRECISION = 1e18;
    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private constant WSXETH = 0x082F581C1105b4aaf2752D6eE5410984bd66Dd21;
    address private constant SXETHWETH_CURVE = 0x8b0fb150FbA4fc25cd4f6F5bd8a8F6944ad65Af0;

    MockToken token0 = MockToken(WSXETH);
    MockToken token1 = MockToken(SXETHWETH_CURVE);

    address[] public tokens = new address[](2);
    uint256[] public weights = new uint256[](2);
    address[] public rateProviders = new address[](2);

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        tokens[0] = address(token0);
        tokens[1] = address(token1);

        weights[0] = 90 * PRECISION / 100;
        weights[1] = 10 * PRECISION / 100;

        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);

        uint256 total = 0.05 ether;

        uint256[] memory amounts = new uint256[](2);

        for (uint256 i = 0; i < 2; i++) {
            address token = tokens[i];
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            uint256 amount = (total * weights[i]) / rateProvider.rate(token);
            amounts[i] = amount;

            console.log("amount of token", MockToken(token).symbol(), " to be added =", amount);
            console.log("balance =", MockToken(token).balanceOf(ADMIN_ADDRESS));
        }

        pool.addLiquidity(amounts, 0, ADMIN_ADDRESS);

        poolToken.approve(address(vault), poolToken.balanceOf(ADMIN_ADDRESS));
        uint256 shares = vault.deposit(poolToken.balanceOf(ADMIN_ADDRESS), ADMIN_ADDRESS);
        vault.transfer(ADMIN_ADDRESS, shares / 90);

        vm.stopBroadcast();
    }
}
