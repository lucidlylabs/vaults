// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

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

contract EthenaVaultRpDeploymentScript is Script {
    IRateProvider rateProvider;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = new UsdeVaultRateProvider();

        vm.stopBroadcast();
    }
}

contract EthenaVaultDeploymentScript is Script {
    PoolToken poolToken;
    Pool pool;
    Vault vault;
    IRateProvider rateProvider;

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

    uint256 private PRECISION = 1e18;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = IRateProvider(0xF1c0629A8B37A02fE2123f4B8F2A38C58961C6D4);

        address[] memory tokens = new address[](5);
        uint256[] memory weights = new uint256[](5);
        address[] memory rateProviders = new address[](5);

        // tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);
        tokens[4] = address(token4);

        // set weights
        weights[0] = 20 * PRECISION / 100;
        weights[1] = 40 * PRECISION / 100;
        weights[2] = 5 * PRECISION / 100;
        weights[3] = 15 * PRECISION / 100;
        weights[4] = 20 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);
        rateProviders[2] = address(rateProvider);
        rateProviders[3] = address(rateProvider);
        rateProviders[4] = address(rateProvider);

        address admin = vm.addr(adminPk);
        poolToken = new PoolToken("Lucidly USDE Pool Token", "lUSDe-Token", 18, admin);

        pool = new Pool(address(poolToken), 450 * PRECISION, tokens, rateProviders, weights, admin);

        vault = new Vault(address(poolToken), "Lucidly USDE Vault", "USDE-VS", 100, 100, admin, admin, admin);

        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3bps
        vault.setEntryFeeInBps(100);
        vault.setEntryFeeAddress(0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5);

        vm.stopBroadcast();
    }
}
