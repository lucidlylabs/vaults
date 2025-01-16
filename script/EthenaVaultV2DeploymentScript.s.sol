// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {EthenaVaultV2RateProvider} from "../src/RateProvider/ethena-usde/EthenaVaultV2RateProvider.sol";
import {PoolOwner} from "../src/PoolOwner.sol";

contract EthenaVaultV2DeploymentScript is Script {
    PoolToken poolToken;
    Pool pool;
    Vault vault;
    PoolOwner ownerContract;
    IRateProvider rateProvider;

    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
    address private constant YPTSUSDE = 0x57fC2D9809F777Cd5c8C433442264B6E8bE7Fce4;
    address private constant GAUNTLET_USDC_PRIME = 0xdd0f28e19C1780eb6396170735D45153D261490d;

    MockToken token0 = MockToken(SUSDE);
    MockToken token1 = MockToken(SDAISUSDE_CURVE);
    MockToken token2 = MockToken(YPTSUSDE);
    MockToken token3 = MockToken(GAUNTLET_USDC_PRIME);

    uint256 private PRECISION = 1e18;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = new EthenaVaultV2RateProvider();

        address[] memory tokens = new address[](4);
        uint256[] memory weights = new uint256[](4);
        address[] memory rateProviders = new address[](4);

        // tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        // set weights
        weights[0] = 20 * PRECISION / 100;
        weights[1] = 60 * PRECISION / 100;
        weights[2] = 18 * PRECISION / 100;
        weights[3] = 2 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);
        rateProviders[2] = address(rateProvider);
        rateProviders[3] = address(rateProvider);

        address admin = vm.addr(adminPk);
        poolToken = new PoolToken("Lucidly SUSDE Pool Token", "lUSDE-Token", 18, admin);
        pool = new Pool(address(poolToken), 450 * PRECISION, tokens, rateProviders, weights, admin);
        vault = new Vault(address(poolToken), "Lucidly USDE Vault", "USDE-VS", 100, 100, admin, admin, admin);

        ownerContract = new PoolOwner(address(pool));

        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3bps
        vault.setDepositFeeInBps(100);
        vault.setProtocolFeeAddress(admin);

        vm.stopBroadcast();
    }
}
