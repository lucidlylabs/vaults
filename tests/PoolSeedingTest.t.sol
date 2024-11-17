// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {SWBTCRateProvider} from "../src/RateProvider/swell-btc/SwBTCRateProvider.sol";
import {ISWBTC} from "../src/RateProvider/swell-btc/ISWBTC.sol";
import {ICurveStableSwapNG} from "../src/RateProvider/ICurveStableSwapNG.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";

// contract PoolAdd is Test {
//     Pool pool;
//     PoolToken poolToken;
//     Vault staking;
//     IRateProvider rp;
//
//     uint256 public constant PRECISION = 1e18;
//     uint256 public constant MAX_NUM_TOKENS = 32;
//     uint256 public amplification;
//
//     uint256 private decimals = 8;
//     address public poolOwner;
//
//     address private SWBTCWBTC_CURVE = 0x73e4BeC1A111869F395cBB24F6676826BF86d905;
//     address private SWBTC = 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE;
//     address private GAUNTLET_WBTC_CORE = 0x443df5eEE3196e9b2Dd77CaBd3eA76C3dee8f9b2;
//
//     MockToken public token0 = MockToken(SWBTCWBTC_CURVE);
//     MockToken public token1 = MockToken(SWBTC);
//     MockToken public token2 = MockToken(GAUNTLET_WBTC_CORE);
//
//     address[] public tokens = new address[](3);
//     uint256[] public weights = new uint256[](3);
//     address[] rateProviders = new address[](3);
//
//     uint256[] public seedAmounts = new uint256[](3);
//
//     address jake = makeAddr("jake"); // pool and staking owner
//     address alice = makeAddr("alice"); // first LP
//     address bob = makeAddr("bob"); // second LP
//
//     function setUp() public {
//         vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));
//
//         rp = new SWBTCRateProvider();
//
//         // set tokens
//         tokens[0] = address(token0);
//         tokens[1] = address(token1);
//         tokens[2] = address(token2);
//
//         // set weights
//         weights[0] = 40 * PRECISION / 100;
//         weights[1] = 30 * PRECISION / 100;
//         weights[2] = 30 * PRECISION / 100;
//
//         // set rateProviders
//         rateProviders[0] = address(rp);
//         rateProviders[1] = address(rp);
//         rateProviders[2] = address(rp);
//
//         // amplification = calculateWProd(weights);
//         amplification = 500 * 1e18;
//
//         // deploy pool token
//         poolToken = new PoolToken("XYZ Pool Token", "lXYZ", 18, jake);
//
//         // deploy pool
//         pool = new Pool(address(poolToken), amplification, tokens, rateProviders, weights, jake);
//
//         // deploy staking contract
//         staking = new Vault(address(pool), "XYZ Vault Token", "XYZ-VS", 200, jake, jake);
//
//         // set staking on pool
//         vm.startPrank(jake);
//         poolToken.setPool(address(pool));
//         pool.setStaking(address(staking));
//         vm.stopPrank();
//
//         // mint tokens to first lp
//         deal(address(token0), alice, 100_000_000 * 1e18); // 100,000,000 SWBTCWBTC_CURVE
//         deal(address(token1), alice, 100_000_000 * 1e8); // 100,000,000 SWBTC
//         deal(address(token2), alice, 100_000_000 * 1e18); // 100,000,000 GAUNTLET_WBTC_CORE
//
//         uint256 total = 10_000 * 1e8; // considering we seed 10000 WBTC worth of assets
//
//         for (uint256 i = 0; i < 3; i++) {
//             address token = tokens[i];
//             address rateProvider = rateProviders[i];
//
//             vm.startPrank(alice);
//
//             require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
//
//             vm.stopPrank();
//
//             uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of an asset in WBTC, scaled to 18 precision
//             uint256 amount =
//                 (total * weights[i] * 1e18 * 1e10) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
//
//             seedAmounts[i] = amount;
//
//             console.log("amount of token", i, "to be seeded:", amount);
//         }
//     }
//
//     function testAddLiquidityInitial() public {
//         uint256 total = 10_000 * 1e18; // 10000 WBTC worth of assets
//
//         vm.startPrank(alice);
//
//         {
//             vm.expectRevert(bytes4(keccak256(bytes("Pool__SlippageLimitExceeded()"))));
//             pool.addLiquidity(seedAmounts, 3 * 10_000 * 1e18, alice);
//         }
//
//         uint256 lpAmount = pool.addLiquidity(seedAmounts, 0 ether, alice);
//         vm.stopPrank();
//
//         uint256 lpBalanceOfAlice = poolToken.balanceOf(alice);
//
//         require(lpAmount == lpBalanceOfAlice, "amounts do not match");
//
//         // precision
//         if (lpBalanceOfAlice > total) {
//             assert((lpBalanceOfAlice - total) * 1e16 / total < 2);
//         } else {
//             assert((total - lpBalanceOfAlice) * 1e16 / total < 2);
//         }
//         assert(poolToken.totalSupply() == lpBalanceOfAlice);
//         assert(pool.supply() == lpBalanceOfAlice);
//         (, uint256 sumTerm) = pool.virtualBalanceProdSum();
//
//         // rounding
//         if (sumTerm > total) {
//             assert((sumTerm - total) <= 4);
//         } else {
//             assert((total - sumTerm) <= 4);
//         }
//     }
// }
