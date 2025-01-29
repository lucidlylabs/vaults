// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {PoolV2} from "../src/Poolv2.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";
import {Aggregator} from "../src/Aggregator.sol";

contract PoolRemoveToken is Test {
    PoolV2 pool;
    PoolToken poolToken;
    Vault vault;
    IRateProvider rp;
    Aggregator agg;

    uint256 constant VB_MASK = 2 ** 96 - 1;
    uint256 constant RATE_MASK = 2 ** 80 - 1;
    uint128 constant RATE_SHIFT = 96;
    uint128 constant PACKED_WEIGHT_SHIFT = 176;

    uint256 constant WEIGHT_SCALE = 1_000_000_000_000;
    uint256 constant WEIGHT_MASK = 2 ** 20 - 1;
    uint128 constant TARGET_WEIGHT_SHIFT = 20;
    uint128 constant LOWER_BAND_SHIFT = 40;
    uint128 constant UPPER_BAND_SHIFT = 60;
    uint256 constant MAX_POW_REL_ERR = 100; // 1e-16

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    uint256 private decimals = 8;
    address public poolOwner;

    MockToken public token0 = new MockToken("name0", "symbol0", 8);
    MockToken public token1 = new MockToken("name1", "symbol1", 18);
    MockToken public token2 = new MockToken("name2", "symbol2", 6);
    MockToken public token3 = new MockToken("name3", "symbol3", 8);

    address[] public tokens = new address[](4);
    uint256[] public weights = new uint256[](4);
    address[] rateProviders = new address[](4);

    uint256[] public seedAmounts = new uint256[](4);

    address jake = makeAddr("jake"); // pool and staking owner
    address alice = makeAddr("alice"); // first LP
    address bob = makeAddr("bob"); // second LP

    function setUp() public {
        rp = IRateProvider(new MockRateProvider());
        agg = new Aggregator();

        MockRateProvider(address(rp)).setRate(address(token0), 2 ether);
        MockRateProvider(address(rp)).setRate(address(token1), 3 ether);
        MockRateProvider(address(rp)).setRate(address(token2), 4 ether);
        MockRateProvider(address(rp)).setRate(address(token3), 1 ether);

        // set tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        // set weights
        weights[0] = 20 * PRECISION / 100;
        weights[1] = 30 * PRECISION / 100;
        weights[2] = 40 * PRECISION / 100;
        weights[3] = 10 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(rp);
        rateProviders[1] = address(rp);
        rateProviders[2] = address(rp);
        rateProviders[3] = address(rp);

        amplification = 500 * 1e18;

        // deploy pool token
        poolToken = new PoolToken("XYZ Pool Token", "lXYZ", 18, jake);

        // deploy pool
        pool = new PoolV2(address(poolToken), amplification, tokens, rateProviders, weights, jake);

        // deploy staking contract
        vault = new Vault(address(poolToken), "XYZ Vault Share", "XYZVS", 100, 100, jake, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3 bps
        vault.setProtocolFeeAddress(jake);
        vault.setDepositFeeInBps(100); // 100 bps
        vm.stopPrank();

        // mint tokens to first lp
        deal(address(token0), alice, 100_000_000 * 1e8); // 100,000,000 SWBTCWBTC_CURVE
        deal(address(token1), alice, 100_000_000 * 1e18); // 100,000,000 SWBTC
        deal(address(token2), alice, 100_000_000 * 1e8); // 100,000,000 cbBTC
        deal(address(token3), alice, 100_000_000 * 1e8); // 100,000,000 SWBTC

        uint256 total = 10_000 * 1e18; // considering we seed 10000 WBTC worth of assets

        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];

            vm.startPrank(alice);
            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of an asset in WBTC, scaled to 18 precision
            uint256 amount = (total * weights[i] * 1e18) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
            seedAmounts[i] = amount;
        }

        // seed pool
        vm.startPrank(alice);
        uint256 lpAmount = pool.addLiquidity(seedAmounts, 0 ether, alice);
        poolToken.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(lpAmount, alice);
        vault.transfer(address(vault), shares / 10);
        vm.stopPrank();
    }

    function _calculateSeedAmounts(uint256 total, address sender) internal returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];

            vm.startPrank(sender);
            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token);

            // considering quoteTokenDecimals is <= 18
            // this is redundant code
            uint256 amount = (total * weights[i] * 1e18 * 10 ** (18 - ERC20(token).decimals()))
                / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
            amounts[i] = amount;
        }
        return amounts;
    }

    function test__poolRemoveToken() public {
        deal(address(token0), jake, 100_000_000 * 1e8);
        deal(address(token1), jake, 100_000_000 * 1e18);
        deal(address(token2), jake, 100_000_000 * 1e8);
        deal(address(token3), jake, 100_000_000 * 1e8);

        uint256[] memory amounts = new uint256[](4);
        uint256 total = 5000 * 1e18;

        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];

            vm.startPrank(jake);
            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token);
            uint256 amount = (total * weights[i] * 1e18) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
            amounts[i] = amount;
        }
        amounts[3] = 0;

        vm.startPrank(jake);
        uint256 lpAdded = pool.addLiquidity(amounts, 0, jake);
        vm.stopPrank();

        uint256 cachedToken3Balance = token3.balanceOf(jake);
        uint256 cachedPoolTokenSupply = poolToken.totalSupply();
        uint256 cachedPoolSupply = pool.supply();

        uint256[] memory newWeights = new uint256[](pool.numTokens() - 1);

        // new composition
        newWeights[0] = 20 * PRECISION / 100;
        newWeights[1] = 30 * PRECISION / 100;
        newWeights[2] = 50 * PRECISION / 100;

        // new amplification
        uint256 ampl = pool.amplification();

        uint256 lpBalanceBeforeRemoving = poolToken.balanceOf(jake);

        vm.startPrank(jake);
        poolToken.approve(address(pool), type(uint256).max);
        pool.removeToken(3, lpAdded, ampl, newWeights, 7 days);
        vm.stopPrank();

        uint256 weightSum = 0;
        for (uint256 i = 0; i < pool.numTokens(); i++) {
            (uint256 weight,,,) = pool.weight(i);
            weightSum += weight;
        }

        uint256 lpBalanceAfterRemoving = poolToken.balanceOf(jake);
        assert(lpBalanceBeforeRemoving > lpBalanceAfterRemoving);
        uint256 lpSpentByJake = lpBalanceBeforeRemoving - lpBalanceAfterRemoving;
        uint256 token3Balance = token3.balanceOf(jake);

        assert(pool.supply() < cachedPoolSupply);
        assert(poolToken.totalSupply() < cachedPoolTokenSupply);
        assert(token3Balance > cachedToken3Balance);
        uint256 changeInToken3Balance = token3Balance - cachedToken3Balance;
        uint256 token3WorthReceived = changeInToken3Balance * rp.rate(address(token3)) / 1e8;

        if (lpSpentByJake > token3WorthReceived) {
            assert((lpSpentByJake - token3WorthReceived) * 1e18 / lpSpentByJake < 99 * 1e18 / 100);
        }

        assert(pool.supply() == poolToken.totalSupply());
        assertEq(weightSum, PRECISION, "Weight sum mismatch");

        uint256[] memory newAmounts = new uint256[](3);
        address[] memory newTokens = new address[](3);
        address[] memory newRateProviders = new address[](3);

        for (uint256 t = 0; t < 3; t++) {
            newTokens[t] = tokens[t];
            newRateProviders[t] = rateProviders[t];
            newAmounts[t] = ERC20(tokens[t]).balanceOf(address(pool));
            deal(tokens[t], jake, newAmounts[t]);
        }

        // deploying new pool with just 3 tokens
        vm.startPrank(jake);
        PoolToken poolToken2 = new PoolToken("**", "**", 19, jake);
        PoolV2 pool2 = new PoolV2(address(poolToken2), ampl, newTokens, newRateProviders, newWeights, jake);
        Vault vault2 = new Vault(address(poolToken2), "**", "**", 100, 100, jake, jake, jake);

        poolToken2.setPool(address(pool2));
        pool2.setVaultAddress(address(vault2));
        pool2.setSwapFeeRate(3 * PRECISION / 10_000);
        vault2.setProtocolFeeAddress(jake);
        vault2.setDepositFeeInBps(100);

        for (uint256 t = 0; t < 3; t++) {
            SafeTransferLib.safeApprove(newTokens[t], address(pool2), newAmounts[t]);
        }
        uint256 lpAmount2 = pool2.addLiquidity(newAmounts, 0, jake);
        SafeTransferLib.safeApprove(address(poolToken2), address(vault2), lpAmount2);
        vault2.deposit(lpAmount2, jake);

        assert(pool.supply() == pool2.supply());
        assert(poolToken.totalSupply() == poolToken2.totalSupply());
    }
}
