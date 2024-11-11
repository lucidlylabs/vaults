// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {MasterVault} from "../src/Staking.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "../tests/PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {UsdeVaultRateProvider} from "../src/RateProvider/ethena-usde/EthenaVaultRateProvider.sol";

contract PoolActivities is Script {
    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;
    address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
    address private constant FRAXUSDE_CURVE = 0x5dc1BF6f1e983C0b21EfB003c105133736fA0743;
    address private constant USDEDAI_CURVE = 0xF36a4BA50C603204c3FC6d2dA8b78A7b69CBC67d;
    address private constant USDE_LPT_PENDLE_MARCH2025 = 0xB451A36c8B6b2EAc77AD0737BA732818143A0E25;

    address private constant POOL = 0x001DF2Cc0c3433beAd3703575F13841d2EBC078f;
    address private constant POOL_TOKEN = 0x4d733dF57E137b074A6CA88D26cbe1bc79608033;
    address private constant VAULT = 0x4CC72CAfB1d87068Cae2da03243317F96E863a9E;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        Pool pool = Pool(POOL);
        // PoolToken poolToken = PoolToken(POOL_TOKEN);

        // Redeem from vault
        uint256 sharesBalance = MasterVault(VAULT).balanceOf(ADMIN_ADDRESS);
        uint256 lpReceived = MasterVault(VAULT).redeem(sharesBalance / 1000, ADMIN_ADDRESS, ADMIN_ADDRESS);

        uint256[] memory minAmounts = new uint256[](5);
        for (uint256 i = 0; i < minAmounts.length; i++) {
            minAmounts[i] = 0;
        }

        // call removeLiquidity()
        pool.removeLiquidity(lpReceived / 2, minAmounts, ADMIN_ADDRESS);

        // callRemoveLiquiditySingle()
        uint256 tokenAmountRemoved = pool.removeLiquiditySingle(0, lpReceived / 2, 0, ADMIN_ADDRESS);
        console.log("token removed:", tokenAmountRemoved);

        uint256 token0Balance = ERC20(pool.tokens(0)).balanceOf(ADMIN_ADDRESS);

        // call swap()
        pool.swap(0, 2, token0Balance / 10, 0, ADMIN_ADDRESS);

        vm.stopBroadcast();
    }
}

contract Pool2Activities is Script {
    address private constant WSXETH = 0x082F581C1105b4aaf2752D6eE5410984bd66Dd21;
    address private constant SXETHWETH_CURVE = 0x8b0fb150FbA4fc25cd4f6F5bd8a8F6944ad65Af0;
    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private constant POOL = 0x188B679c0bAf56b9838584AfaC82D713e68112fC;
    address private constant POOL_TOKEN = 0x34e523B10B85c41515807811456613Cf2a077C77;
    address private constant VAULT = 0xCDE68b2DB42cfA27ad9A653eEAc4f23297227175;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        Pool pool = Pool(POOL);
        // PoolToken poolToken = PoolToken(POOL_TOKEN);

        // Redeem from vault
        uint256 sharesBalance = MasterVault(VAULT).balanceOf(ADMIN_ADDRESS);
        uint256 lpReceived = MasterVault(VAULT).redeem(sharesBalance / 1000, ADMIN_ADDRESS, ADMIN_ADDRESS);

        uint256[] memory minAmounts = new uint256[](2);
        for (uint256 i = 0; i < minAmounts.length; i++) {
            minAmounts[i] = 0;
        }

        // call removeLiquidity()
        pool.removeLiquidity(lpReceived / 2, minAmounts, ADMIN_ADDRESS);

        // callRemoveLiquiditySingle()
        uint256 tokenAmountRemoved = pool.removeLiquiditySingle(0, lpReceived / 2, 0, ADMIN_ADDRESS);
        console.log("token removed:", tokenAmountRemoved);

        uint256 token0Balance = ERC20(pool.tokens(0)).balanceOf(ADMIN_ADDRESS);

        // call swap()
        pool.swap(0, 1, token0Balance / 10, 0, ADMIN_ADDRESS);

        vm.stopBroadcast();
    }
}
