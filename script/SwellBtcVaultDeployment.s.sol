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
import {SwBtcRateProvider} from "../src/RateProvider/swell-btc/SwBTCRateProvider.sol";
import {PoolOwner} from "../src/PoolOwner.sol";

contract SwBtcVaultRateProviderDeploymentScript is Script {
    IRateProvider rateProvider;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);
        rateProvider = new SwBtcRateProvider();
        vm.stopBroadcast();
    }
}

contract SwBtcVaultDeploymentScript is Script {
    PoolToken poolToken;
    Pool pool;
    Vault vault;
    PoolOwner ownerContract;
    IRateProvider rateProvider;

    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private SWBTCWBTC_CURVE = 0x73e4BeC1A111869F395cBB24F6676826BF86d905;
    address private SWBTC = 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE;
    address private GAUNTLET_WBTC_CORE = 0x443df5eEE3196e9b2Dd77CaBd3eA76C3dee8f9b2;

    uint256 PRECISION = 1e18;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = new SwBtcRateProvider();

        address[] memory tokens = new address[](3);
        uint256[] memory weights = new uint256[](3);
        address[] memory rateProviders = new address[](3);

        tokens[0] = address(SWBTCWBTC_CURVE);
        tokens[1] = address(SWBTC);
        tokens[2] = address(GAUNTLET_WBTC_CORE);

        weights[0] = 20 * PRECISION / 100;
        weights[1] = 20 * PRECISION / 100;
        weights[2] = 60 * PRECISION / 100;

        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);
        rateProviders[2] = address(rateProvider);

        poolToken = new PoolToken("Lucidly swBTC Vault Pool Token", "swBTC-VPT", 18, ADMIN_ADDRESS);
        pool = new Pool(address(poolToken), 10 * PRECISION, tokens, rateProviders, weights, ADMIN_ADDRESS);
        vault = new Vault(
            address(poolToken), "Lucidly swBTC Vault", "swBTC-VS", 100, 100, ADMIN_ADDRESS, ADMIN_ADDRESS, ADMIN_ADDRESS
        );

        ownerContract = new PoolOwner(address(pool));

        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000);
        vm.stopBroadcast();
    }
}
