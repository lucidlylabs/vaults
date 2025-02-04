// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "../lib/forge-std/src/Script.sol";

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {PoolV2} from "../src/Poolv2.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {AnglesLiquidVaultRateProvider} from "../src/RateProvider/angles-liquid/AnglesLiquidVaultRateProvider.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";
import {Aggregator} from "../src/Aggregator.sol";
import {FeeSplitter} from "../src/utils/FeeSplitter.sol";

contract AnglesLiquidVaultDeploymentScript is Script {
    PoolToken poolToken;
    PoolV2 pool;
    Vault vault;
    IRateProvider rateProvider;

    address immutable WRAPPED_ANGLES_S = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;
    address immutable WRAPPED_S = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;

    ERC20 token0 = ERC20(WRAPPED_S);
    ERC20 token1 = ERC20(WRAPPED_ANGLES_S);

    uint256 private PRECISION = 1e18;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        address admin = vm.addr(adminPk);

        vm.startBroadcast(adminPk);

        rateProvider = new AnglesLiquidVaultRateProvider();

        address[] memory tokens = new address[](2);
        uint256[] memory weights = new uint256[](2);
        address[] memory rateProviders = new address[](2);

        tokens[0] = address(token0);
        tokens[1] = address(token1);

        weights[0] = 10 * PRECISION / 100;
        weights[1] = 90 * PRECISION / 100;

        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);

        uint256 amplification = 10_000e18;

        poolToken = new PoolToken("AnglesLiquid-PT", "anLPT", 18, admin);
        pool = new PoolV2(address(poolToken), amplification, tokens, rateProviders, weights, admin);
        vault = new Vault(address(poolToken), "Angles Liquid", "lanS", 100, 100, admin, admin, admin);

        poolToken.setPool(address(pool));
        poolToken.setVaultAddress(address(vault));

        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000);

        vault.setEntryFeeAddress(admin);
        vault.setEntryFeeInBps(10);

        FeeSplitter splitter = new FeeSplitter(
            address(poolToken), 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5, 0x7e431e5fF0EE4cAD26347C0674aFa9c30502b535
        );

        vault.setPerformanceFeeRecipient(address(splitter));
        vault.setPerformanceFeeInBps(1000);

        vm.stopBroadcast();
    }
}

contract DeployAggregatorContract is Script {
    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        new Aggregator();

        vm.stopBroadcast();
    }
}
