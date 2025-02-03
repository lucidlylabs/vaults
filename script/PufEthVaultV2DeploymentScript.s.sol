// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {PufEthVaultV2RateProvider} from "../src/RateProvider/puffer-pufeth/PufEthVaultV2RateProvider.sol";
import {PoolOwner} from "../src/PoolOwner.sol";

contract PufEthVaultV2RpDeploymentScript is Script {
    IRateProvider rateProvider;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = new PufEthVaultV2RateProvider();

        vm.stopBroadcast();
    }
}

contract PufEthVaultV2DeploymentScript is Script {
    PoolToken poolToken;
    Pool pool;
    Vault vault;
    PoolOwner ownerContract;
    IRateProvider rateProvider;

    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private constant PUFETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    address private constant PUFETH_WSTETH_CURVE = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
    address private constant WETH_PUFETH_CURVE = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;
    address private constant GAUNTLET_WETH_CORE = 0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658;

    MockToken token0 = MockToken(PUFETH);
    MockToken token1 = MockToken(PUFETH_WSTETH_CURVE);
    MockToken token2 = MockToken(WETH_PUFETH_CURVE);
    MockToken token3 = MockToken(GAUNTLET_WETH_CORE);

    uint256 private PRECISION = 1e18;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = new PufEthVaultV2RateProvider();

        address[] memory tokens = new address[](4);
        uint256[] memory weights = new uint256[](4);
        address[] memory rateProviders = new address[](4);

        // tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        // set weights
        weights[0] = 10 * PRECISION / 100;
        weights[1] = 25 * PRECISION / 100;
        weights[2] = 60 * PRECISION / 100;
        weights[3] = 5 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);
        rateProviders[2] = address(rateProvider);
        rateProviders[3] = address(rateProvider);

        address admin = vm.addr(adminPk);
        poolToken = new PoolToken("Lucidly PufEth Pool Token", "lPufEth-Token", 18, admin);
        pool = new Pool(address(poolToken), 450 * PRECISION, tokens, rateProviders, weights, admin);
        vault = new Vault(address(poolToken), "Lucidly PufEth Vault", "PufEth-VS", 100, 100, admin, admin, admin);

        ownerContract = new PoolOwner(address(pool));

        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3bps
        vault.setEntryFeeInBps(100);
        vault.setEntryFeeAddress(admin);

        vm.stopBroadcast();
    }
}
