// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {console} from "forge-std/console.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";

contract PoolAdd is Test {
    Pool pool;
    PoolToken poolToken;
    Vault staking;
    MockRateProvider mrp;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    address public poolOwner;

    MockToken public token0;
    MockToken public token1;
    MockToken public token2;
    MockToken public token3;
    MockToken public token4;
    MockToken public token5;
    MockToken public token6;
    MockToken public token7;

    address[] public tokens = new address[](4);
    uint256[] public weights = new uint256[](4);
    address[] rateProviders = new address[](4);

    address jake = makeAddr("jake"); // pool and staking owner
    address alice = makeAddr("alice"); // first LP
    address bob = makeAddr("bob"); // second LP

    function setUp() public {
        // 1. deploy tokens
        // 2. deploy pool
        // 3. configure pool
        // 4. deploy vault

        token0 = new MockToken("token0", "t0", 18);
        token1 = new MockToken("token1", "t1", 18);
        token2 = new MockToken("token2", "t2", 18);
        token3 = new MockToken("token3", "t3", 18);

        mrp = new MockRateProvider();

        mrp.setRate(address(token0), 2 ether);
        mrp.setRate(address(token1), 3 ether);
        mrp.setRate(address(token2), 4 ether);
        mrp.setRate(address(token3), 5 ether);

        // set tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        // set weights
        weights[0] = 10 * PRECISION / 100;
        weights[1] = 20 * PRECISION / 100;
        weights[2] = 30 * PRECISION / 100;
        weights[3] = 40 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(mrp);
        rateProviders[1] = address(mrp);
        rateProviders[2] = address(mrp);
        rateProviders[3] = address(mrp);

        // amplification = calculateWProd(weights);
        amplification = 167_237_825_366_714_712_064;

        // deploy pool token
        poolToken = new PoolToken("XYZ Pool Token", "XYZ-PT", 18, jake);

        // deploy pool
        pool = new Pool(address(poolToken), amplification, tokens, rateProviders, weights, jake);

        // deploy staking contract
        staking = new Vault(address(pool), "XYZ Mastervault Token", "XYZ-MVT", 200, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(staking));
        vm.stopPrank();
    }

    function testAddLiquidityInitial() public {
        uint256 total = 10_000_000 ether;
        uint256[] memory amounts = _mintTokensToAliceBalanced(total);

        vm.startPrank(alice);

        {
            vm.expectRevert(bytes4(keccak256(bytes("Pool__SlippageLimitExceeded()"))));
            pool.addLiquidity(amounts, 2 * total, alice);
        }

        uint256 lpAmount = pool.addLiquidity(amounts, 0 ether, alice);
        vm.stopPrank();

        uint256 lpBalanceOfAlice = poolToken.balanceOf(alice);

        assert(lpAmount == lpBalanceOfAlice);

        // precision
        if (lpBalanceOfAlice > total) {
            assert((lpBalanceOfAlice - total) * 1e16 / total < 2);
        } else {
            assert((total - lpBalanceOfAlice) * 1e16 / total < 2);
        }
        assert(poolToken.totalSupply() == lpBalanceOfAlice);
        assert(pool.supply() == lpBalanceOfAlice);
        (, uint256 sumTerm) = pool.virtualBalanceProdSum();

        // rounding
        if (sumTerm > total) {
            assert((sumTerm - total) <= 4);
        } else {
            assert((total - sumTerm) <= 4);
        }
    }

    function _mintTokensToAliceBalanced(uint256 total) internal returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](4);

        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];
            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();
            uint256 amount = (total * weights[i]) / MockRateProvider(rateProvider).rate(token);
            MockToken(token).mint(alice, amount);
            amounts[i] = amount;
        }

        return amounts;
    }

    function testAddLiquidityMultiple() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();

        // mint tokens
        uint256[] memory amounts1 = new uint256[](numTokens);
        uint256[] memory amounts2 = new uint256[](numTokens);
        uint256 total1 = 10_000_000 * PRECISION;
        uint256 total2 = PRECISION / 10_000;

        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];

            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();

            amounts1[i] = total1 * weights[i] / mrp.rate(token);
            amounts2[i] = total2 * weights[i] / mrp.rate(token);

            MockToken(token).mint(alice, amounts1[i] + amounts2[i]);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts1, 0, alice);
        vm.stopPrank();

        // 2nd small deposit
        uint256 exp = estimator.getAddLp(amounts2);

        vm.startPrank(alice);
        uint256 lpAmount = pool.addLiquidity(amounts2, 0, bob);
        vm.stopPrank();

        uint256 balanceOfBob = poolToken.balanceOf(bob);
        assert(balanceOfBob == lpAmount);
        assert(balanceOfBob == exp);

        if (estimator.getVirtualBalance(amounts2) > total2) {
            assert((estimator.getVirtualBalance(amounts2) - total2) <= numTokens);
        } else {
            assert(total2 - (estimator.getVirtualBalance(amounts2)) <= numTokens);
        }

        // rounding is in favor of pool
        assert(balanceOfBob < total2);
        // even with 10M ETH in the pool we can reach decent precision on small amounts
        assert(((total2 - balanceOfBob) / total2) * 1e5 < 2);

        (, uint256 vbSum) = pool.virtualBalanceProdSum();

        if (vbSum > total1 + total2) {
            assert(vbSum - total1 - total2 <= 4);
        } else {
            assert(total1 + total2 - vbSum <= 4);
        }
    }

    function testAddLiquiditySingleSided() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 10 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            MockToken(token).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            uint256 amount = total * weights[i] / mrp.rate(token);
            amounts[i] = amount;
            MockToken(token).mint(alice, amount);
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        uint256 prev = 0;
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 snapshot = vm.snapshot();

            address token = tokens[i];
            uint256 amount = PRECISION * PRECISION / mrp.rate(token);

            vm.startPrank(alice);
            MockToken(token).mint(alice, amount);
            vm.stopPrank();

            uint256[] memory amounts2 = new uint256[](numTokens);

            for (uint256 j = 0; j < numTokens; j++) {
                if (j == i) amounts2[j] = amount;
                else amounts2[j] = 0;
            }

            uint256 exp = estimator.getAddLp(amounts2);

            vm.startPrank(alice);
            uint256 lpAmount = pool.addLiquidity(amounts2, 0, bob);
            vm.stopPrank();

            uint256 balBob = poolToken.balanceOf(bob);
            assert(balBob == exp);
            assert(balBob == lpAmount);
            assert(balBob < PRECISION);

            // small penalty because pool is now out of balance
            // uint256 penalty = (PRECISION - balBob) * PRECISION / PRECISION;

            // later assets have a higher weight so penalty is smaller
            assert(balBob > prev);
            prev = balBob;

            vm.revertTo(snapshot);
        }
    }

    function testBonus() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 10 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            MockToken(token).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            uint256 amount = total * weights[i] / mrp.rate(token);
            amounts[i] = amount;
            MockToken(token).mint(alice, amount);
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        uint256[] memory amounts2 = new uint256[](numTokens);
        // deposit all tokens but one
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            uint256 amount = PRECISION * weights[i] / mrp.rate(token);
            amounts2[i] = amount;
            MockToken(token).mint(alice, amount);
        }
        uint256 amount0 = amounts2[0];
        amounts2[0] = 0;

        vm.startPrank(alice);
        pool.addLiquidity(amounts2, 0, alice);
        vm.stopPrank();

        // deposit the other asset, receive bonus to balance the pool back
        uint256[] memory amounts3 = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 0) amounts3[i] = amount0;
            else amounts3[i] = 0;
        }

        uint256 exp = estimator.getAddLp(amounts3);

        vm.startPrank(alice);
        uint256 res = pool.addLiquidity(amounts3, 0, bob);
        vm.stopPrank();

        uint256 bal = poolToken.balanceOf(bob);

        assert(bal == res);
        assert(bal == exp);
        assert(bal > weights[0]);
    }

    function testBalancedFee() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        // mint tokens
        uint256 numTokens = pool.numTokens();
        uint256 total1 = 1000 * PRECISION;
        uint256 total2 = PRECISION;
        uint256[] memory amounts1 = new uint256[](numTokens);
        uint256[] memory amounts2 = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            MockToken(token).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            uint256 amount1 = total1 * weights[i] / mrp.rate(token);
            uint256 amount2 = total2 * weights[i] / mrp.rate(token);
            amounts1[i] = amount1;
            amounts2[i] = amount2;

            MockToken(token).mint(alice, amount1 + amount2);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts1, 0, alice);
        vm.stopPrank();

        // second small deposit
        uint256 ss = vm.snapshot();

        // baseline: no fee
        vm.startPrank(alice);
        pool.addLiquidity(amounts2, 0, bob);
        vm.stopPrank();

        uint256 balNoFee = poolToken.balanceOf(bob);

        vm.revertTo(ss);

        // set a fee
        vm.startPrank(jake);
        pool.setSwapFeeRate(PRECISION / 100);
        vm.stopPrank();

        uint256 exp = estimator.getAddLp(amounts2);

        vm.startPrank(alice);
        pool.addLiquidity(amounts2, 0, bob);
        vm.stopPrank();

        uint256 bal = poolToken.balanceOf(bob);

        assert(bal == exp);
        assert(balNoFee > bal);

        assert((balNoFee - bal) * PRECISION / balNoFee < 100);
    }

    function testFee() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            MockToken(token).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            uint256 _amount = total * weights[i] / mrp.rate(token);
            amounts[i] = _amount;
            MockToken(token).mint(alice, _amount);
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        // second small deposit
        uint256 amount = PRECISION * PRECISION / mrp.rate(tokens[0]);
        MockToken(tokens[0]).mint(alice, amount);

        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 0) amounts[i] = amount;
            else amounts[i] = 0;
        }

        uint256 ss = vm.snapshot();

        // baseline: no fee
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, bob);
        vm.stopPrank();

        uint256 balNoFee = poolToken.balanceOf(bob);

        vm.revertTo(ss);

        vm.startPrank(jake);
        pool.setSwapFeeRate(PRECISION / 100); // 1%
        vm.stopPrank();

        uint256 exp = estimator.getAddLp(amounts);

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, bob);
        vm.stopPrank();

        uint256 bal = poolToken.balanceOf(bob);
        assert(bal == exp);

        assert(balNoFee > bal);

        // single side deposit is charged half the fee
        uint256 rate = (balNoFee - bal) * PRECISION / balNoFee;
        exp = PRECISION / 200;

        assert((exp - rate) * PRECISION / exp < 3 * 1e14);
    }

    function testRateUpdate() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1_000_000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            MockToken(token).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            uint256 _amount = total * weights[i] / mrp.rate(token);
            amounts[i] = _amount;
            MockToken(token).mint(alice, _amount);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        // rate update of each token, and then a single side deposit

        // 0.0034ETH increase on 100ETH per 60 mins if APR = 30%
        uint256 factor = 100_000_034 * PRECISION / 100_000_000;
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];

            for (uint256 j = 0; j < numTokens; j++) {
                if (j == i) amounts[j] = PRECISION;
                else amounts[j] = 0;
            }

            MockToken(token).mint(alice, PRECISION);

            uint256 base;
            {
                uint256 ss = vm.snapshot();
                vm.startPrank(alice);
                pool.addLiquidity(amounts, 0, bob);
                vm.stopPrank();
                base = poolToken.balanceOf(bob);
                vm.revertTo(ss);
            }

            uint256 exp;
            uint256 bal;
            uint256 exp2;
            uint256 bal2;
            {
                uint256 ss1 = vm.snapshot();
                mrp.setRate(token, mrp.rate(token) * factor / PRECISION);

                // add liquidity after rate increase
                exp = estimator.getAddLp(amounts);
                vm.startPrank(alice);
                pool.addLiquidity(amounts, 0, bob);
                vm.stopPrank();
                bal = poolToken.balanceOf(bob);
                assert(bal == exp);

                // staking address received rewards
                // uint256 exp2 = total * weights[i] / (PRECISION * 100);

                // int(total * weights[i] // PRECISION*(factor-1))
                exp2 = total * weights[i] * PRECISION / (PRECISION * (factor - PRECISION));
                bal2 = poolToken.balanceOf(address(staking));

                assert(bal2 < exp2);
                // assert((exp2 - bal2) * PRECISION / exp2 < PRECISION / 1e3);
                vm.revertTo(ss1);
            }

            // the rate update brought pool out of balance so increase in lp tokens is less than `factor`
            assert(bal > base);
            uint256 bal_factor = bal * PRECISION / base;
            assert(bal_factor < factor);
            assert((factor - bal_factor) * PRECISION / factor < PRECISION / 1000);
        }
    }

    function testRampWeight() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            MockToken(token).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            uint256 _amount = total * weights[i] / mrp.rate(token);
            amounts[i] = _amount;
            MockToken(token).mint(alice, _amount);
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, address(staking));
        vm.stopPrank();

        uint256 ampl = PRECISION;
        uint256 activeA = estimator.getEffectiveAmplification();
        uint256 targetA = estimator.getEffectiveTargetAmplification();

        /// @TODO revisit
        // assert(_abs(activeA, ampl) * PRECISION / ampl < 5 * 100);

        assert(activeA == targetA);

        MockToken(tokens[1]).mint(alice, PRECISION);
        MockToken(tokens[2]).mint(alice, PRECISION);

        uint256 ss = vm.snapshot();
        uint256[] memory amt1 = new uint256[](numTokens);
        for (uint256 j = 0; j < numTokens; j++) {
            if (j == 1) amt1[j] = PRECISION;
            else amt1[j] = 0;
        }
        vm.startPrank(alice);
        pool.addLiquidity(amt1, 0, bob);
        vm.stopPrank();
        uint256 base_1 = poolToken.balanceOf(bob);
        vm.revertTo(ss);

        uint256 ss1 = vm.snapshot();
        uint256[] memory amt2 = new uint256[](numTokens);
        for (uint256 j = 0; j < numTokens; j++) {
            if (j == 2) amt2[j] = PRECISION;
            else amt2[j] = 0;
        }
        vm.startPrank(alice);
        pool.addLiquidity(amt2, 0, bob);
        vm.stopPrank();
        uint256 base_2 = poolToken.balanceOf(bob);
        vm.revertTo(ss1);

        uint256[] memory weights2 = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            weights2[i] = weights[i];
        }

        weights2[1] += PRECISION / 10;

        vm.startPrank(jake);
        vm.expectRevert(bytes4(keccak256(bytes("Pool__WeightsDoNotAddUp()"))));
        uint256 newAmplification = 167_237_825_366_714_744_832;
        pool.setRamp(newAmplification, weights2, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();

        weights2[2] -= PRECISION / 10;

        uint256 ts = vm.getBlockTimestamp();

        vm.startPrank(jake);
        pool.setRamp(calculateWProd(weights2), weights2, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();

        // estimator calculates correct target amplification
        targetA = estimator.getEffectiveTargetAmplification();
        /// TODO - revisit `assert abs(tar - ampl) / ampl < 3e-16` in original yETH codebase
        // (ampl - tarA) / ampl < 5e-16
        assert((ampl - targetA) * PRECISION / ampl < 5 * 100);

        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 1) amounts[i] = PRECISION;
            else amounts[i] = 0;
        }

        // halfway ramp
        vm.warp(ts + 7 days / 2);
        uint256 exp;
        uint256 amplMid;
        {
            uint256 ss2 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getAddLp(amounts);
            amplMid = estimator.getEffectiveAmplification();
            vm.revertTo(ss2);
        }

        vm.warp(ts + 7 days / 2);

        uint256 mid_1;
        {
            uint256 ss3 = vm.snapshot();
            vm.startPrank(alice);
            pool.addLiquidity(amounts, 0, bob);
            vm.stopPrank();
            mid_1 = poolToken.balanceOf(bob);
            assert(mid_1 - exp <= 5);
            vm.revertTo(ss3);
        }

        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 2) amounts[i] = PRECISION;
            else amounts[i] = 0;
        }
        vm.warp(ts + 7 days / 2);

        {
            uint256 ss4 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getAddLp(amounts);
            vm.revertTo(ss4);
        }

        vm.warp(ts + 7 days / 2);
        uint256 mid_2;
        {
            uint256 ss5 = vm.snapshot();
            vm.startPrank(alice);
            pool.addLiquidity(amounts, 0, bob);
            vm.stopPrank();
            mid_2 = poolToken.balanceOf(bob);
            assert(_abs(mid_2, exp) <= 21);
            vm.revertTo(ss5);
        }

        // token 1 share is below weight -> bonus
        assert(mid_1 > base_1);
        // token 2 share is above weight -> penalty
        assert(mid_2 < base_2);

        // effective amplification changes slightly during ramp
        assert(_abs(amplMid, ampl) * PRECISION / ampl < 4 * PRECISION / 100);

        // end of ramp
        vm.warp(ts + 7 days);
        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 1) amounts[i] = PRECISION;
            else amounts[i] = 0;
        }

        uint256 amplEnd;
        {
            uint256 ss6 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getAddLp(amounts);
            amplEnd = estimator.getEffectiveAmplification();
            vm.revertTo(ss6);
        }
        vm.warp(ts + 7 days);
        uint256 end_1;
        {
            uint256 ss7 = vm.snapshot();
            vm.startPrank(alice);
            pool.addLiquidity(amounts, 0, bob);
            vm.stopPrank();
            end_1 = poolToken.balanceOf(bob);
            assert(_abs(end_1, exp) <= 21);
            vm.revertTo(ss7);
        }
        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 2) amounts[i] = PRECISION;
            else amounts[i] = 0;
        }
        vm.warp(ts + 7 days);
        {
            uint256 ss8 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getAddLp(amounts);
            vm.revertTo(ss8);
        }
        vm.warp(ts + 7 days);
        uint256 end_2;
        {
            uint256 ss9 = vm.snapshot();
            vm.startPrank(alice);
            pool.addLiquidity(amounts, 0, bob);
            vm.stopPrank();
            end_2 = poolToken.balanceOf(bob);
            assert(_abs(end_2, exp) <= 18);
            vm.revertTo(ss9);
        }

        // token 1 share is more below weight -> bigger bonus
        assert(end_1 > mid_1);

        // token 2 share is more above weight -> bigger penalty
        assert(end_2 < mid_2);

        // effective amplification is back to expected value after ramp
        assert(_abs(amplEnd, ampl) * PRECISION / ampl < 5 * 100);
    }

    function testRampAmplification() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            MockToken(token).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            uint256 _amount = total * weights[i] / mrp.rate(token);
            amounts[i] = _amount;
            MockToken(token).mint(alice, _amount);
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, address(staking));
        vm.stopPrank();

        uint256 amount = 10 * PRECISION;
        MockToken(tokens[1]).mint(alice, amount);

        uint256 base;
        {
            uint256 ss = vm.snapshot();
            uint256[] memory amt1 = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; i++) {
                if (i == 1) amt1[i] = amount;
                else amt1[i] = 0;
            }
            vm.startPrank(alice);
            pool.addLiquidity(amt1, 0, bob);
            vm.stopPrank();
            base = poolToken.balanceOf(bob);
            vm.revertTo(ss);
        }

        uint256 ampl = 10 * PRECISION;
        uint256 ts = vm.getBlockTimestamp();
        vm.startPrank(jake);
        pool.setRamp(10 * pool.amplification(), weights, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();

        uint256 tar = estimator.getEffectiveTargetAmplification();
        assert(_abs(tar, ampl) * PRECISION / ampl < 5 * 100);

        // halfway ramp
        uint256 expHalf = (ampl + PRECISION) / 2;
        vm.warp(ts + 7 days / 2);
        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 1) amounts[i] = amount;
            else amounts[i] = 0;
        }
        uint256 exp;
        uint256 amplHalf;
        {
            uint256 ss1 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getAddLp(amounts);
            amplHalf = estimator.getEffectiveAmplification();
            vm.revertTo(ss1);
        }
        vm.warp(ts + 7 days / 2);
        uint256 mid;
        {
            uint256 ss2 = vm.snapshot();
            vm.startPrank(alice);
            pool.addLiquidity(amounts, 0, bob);
            vm.stopPrank();
            mid = poolToken.balanceOf(bob);
            assert(_abs(mid, exp) <= 16);
            vm.revertTo(ss2);
        }

        // higher amplification -> lower penalty
        assert(mid > base);

        // effective amplification is in between begin and target
        assert(_abs(amplHalf, expHalf) * PRECISION / expHalf < 5 * 100);

        // end of ramp
        vm.warp(ts + 7 days);
        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 1) amounts[i] = amount;
            else amounts[i] = 0;
        }
        uint256 amplEnd;
        {
            uint256 ss3 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getAddLp(amounts);
            amplEnd = estimator.getEffectiveAmplification();
            vm.revertTo(ss3);
        }

        vm.warp(ts + 7 days);
        uint256 end;
        {
            uint256 ss4 = vm.snapshot();
            vm.startPrank(alice);
            pool.addLiquidity(amounts, 0, bob);
            vm.stopPrank();
            end = poolToken.balanceOf(bob);
            assert(_abs(end, exp) <= 9);
            vm.revertTo(ss4);
        }

        // even lower penalty
        assert(end > mid);

        // effective amplification is equal to target
        assert(_abs(amplEnd, ampl) * PRECISION / ampl < 5 * 100);
    }

    // function testRampCommutative() public {
    //     uint256 numTokens = pool.numTokens();
    //     uint256[] memory amounts = new uint256[](numTokens);

    //     amounts[0] = 12 * PRECISION;
    //     amounts[1] = 25 * PRECISION;
    //     amounts[2] = 27 * PRECISION;
    //     amounts[3] = 36 * PRECISION;

    //     for (uint256 i = 0; i < numTokens; i++) {
    //         address token = tokens[i];
    //         vm.startPrank(alice);
    //         MockToken(token).approve(address(pool), type(uint256).max);
    //         amounts[i] = amounts[i] * PRECISION / mrp.rate(token);
    //         MockToken(token).mint(alice, amounts[i]);
    //         vm.stopPrank();
    //     }

    //     // deposit
    //     vm.startPrank(alice);
    //     pool.addLiquidity(amounts, 0, address(staking));
    //     vm.stopPrank();

    //     // ramp
    //     uint256[] memory weights1 = new uint256[](numTokens);
    //     weights1[0] = PRECISION * 15 / 100;
    //     weights1[1] = PRECISION * 30 / 100;
    //     weights1[2] = PRECISION * 20 / 100;
    //     weights1[3] = PRECISION * 35 / 100;

    //     vm.startPrank(jake);
    //     uint256 newAmplification = 208_583_754_406_003_441_664;
    //     pool.setRamp(newAmplification, weights1, 0, vm.getBlockTimestamp());
    //     vm.stopPrank();
    //     vm.startPrank(alice);
    //     pool.updateWeights();
    //     vm.stopPrank();
    //     uint256 bal = poolToken.balanceOf(address(staking));
    //     (uint256 virtualBalanceProd, uint256 virtualBalanceSum) = pool.virtualBalanceProdSum();

    //     // second pool that has the weights from the start
    //     vm.startPrank(jake);
    //     Pool pool2 = new Pool(address(poolToken), newAmplification, tokens, rateProviders, weights1, jake);
    //     pool2.setStaking(address(staking));
    //     poolToken.setPool(address(pool2));
    //     vm.stopPrank();

    //     for (uint256 i = 0; i < numTokens; i++) {
    //         address token = tokens[i];
    //         vm.startPrank(alice);
    //         MockToken(token).approve(address(pool2), type(uint256).max);
    //         MockToken(token).mint(alice, amounts[i]);
    //         vm.stopPrank();
    //     }

    //     vm.startPrank(alice);
    //     pool2.addLiquidity(amounts, 0, alice);
    //     vm.stopPrank();
    //     uint256 bal2 = poolToken.balanceOf(alice);
    //     (uint256 virtualBalanceProd2, uint256 virtualBalanceSum2) = pool2.virtualBalanceProdSum();

    //     assert(_abs(bal, bal2) * PRECISION / bal2 < 2);
    //     assert(_abs(virtualBalanceProd, virtualBalanceProd2) * PRECISION / virtualBalanceProd2 < 3);
    //     assert(virtualBalanceSum == virtualBalanceSum2);
    // }

    function testBand() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            MockToken(token).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            uint256 _amount = total * weights[i] / mrp.rate(token);
            amounts[i] = _amount;
            MockToken(token).mint(alice, _amount);
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, address(staking));
        vm.stopPrank();

        uint256 amount = total * PRECISION * 21 / 100 / mrp.rate(tokens[3]); // +10.4% after deposit
        for (uint256 i = 0; i < numTokens; i++) {
            if (i == 3) amounts[i] = amount;
            else amounts[i] = 0;
        }
        MockToken(tokens[3]).mint(alice, amount);

        //  deposit will work before setting a band
        {
            uint256 ss = vm.snapshot();
            estimator.getAddLp(amounts);
            vm.startPrank(alice);
            pool.addLiquidity(amounts, 0, bob);
            vm.stopPrank();
            vm.revertTo(ss);
        }

        // set band
        uint256[] memory tokens2 = new uint256[](1);
        uint256[] memory lowerWeightBands = new uint256[](1);
        uint256[] memory upperWeightBands = new uint256[](1);
        tokens2[0] = 3;
        lowerWeightBands[0] = PRECISION;
        upperWeightBands[0] = PRECISION / 10;
        vm.startPrank(jake);
        pool.setWeightBands(tokens2, lowerWeightBands, upperWeightBands);
        vm.stopPrank();

        // deposit won't work
        // vm.expectRevert(abi.encodePacked("ratio above upper band"));
        estimator.getAddLp(amounts);

        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256(bytes("Pool__RatioAboveUpperBound()"))));
        pool.addLiquidity(amounts, 0, bob);
        vm.stopPrank();
    }

    function _abs(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x >= y) {
            return (x - y);
        } else {
            return (y - x);
        }
    }

    function calculateWProd(uint256[] memory _weights) public pure returns (uint256) {
        uint256 prod = uint256(PRECISION);
        uint256 n = _weights.length;
        for (uint256 i = 0; i < n; i++) {
            uint256 w = _weights[i];
            // prod = prod / (w / PRECISION) ^ (w * n / PRECISION)
            prod = prod * PRECISION / LogExpMath.pow((w * PRECISION / PRECISION), (w * n * PRECISION) / PRECISION);
        }

        return prod;
    }
}
