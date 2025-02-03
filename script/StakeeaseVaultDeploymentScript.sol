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
import {StakeeaseVaultRateProvider} from "../src/RateProvider/stakeease-sxeth/StakeeaseVaultRateProvider.sol";

contract DeployRateProvider is Script {
    IRateProvider rateProvider;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = new StakeeaseVaultRateProvider();

        vm.stopBroadcast();
    }
}

contract DeployVault is Script {
    PoolToken poolToken;
    Pool pool;
    Vault vault;
    IRateProvider rateProvider;

    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private constant WSXETH = 0x082F581C1105b4aaf2752D6eE5410984bd66Dd21;
    address private constant SXETHWETH_CURVE = 0x8b0fb150FbA4fc25cd4f6F5bd8a8F6944ad65Af0;

    MockToken token0 = MockToken(WSXETH);
    MockToken token1 = MockToken(SXETHWETH_CURVE);

    uint256 private PRECISION = 1e18;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = IRateProvider(0x144Bec263C77E9d20946d2A8A96507d68c4922D5);

        address[] memory tokens = new address[](2);
        uint256[] memory weights = new uint256[](2);
        address[] memory rateProviders = new address[](2);

        // tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);

        // set weights
        weights[0] = 90 * PRECISION / 100;
        weights[1] = 10 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);

        address admin = vm.addr(adminPk);
        poolToken = new PoolToken("Lucidly sxETH Pool Token", "lsxETH-Token", 18, admin);

        pool = new Pool(address(poolToken), 450 * PRECISION, tokens, rateProviders, weights, admin);

        vault = new Vault(address(poolToken), "Lucidly sxETH Vault", "sxETH-VS", 100, 100, admin, admin, admin);

        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3bps
        vault.setEntryFeeInBps(100);
        vault.setEntryFeeAddress(0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5);

        vm.stopBroadcast();
    }
}
