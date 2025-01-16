// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

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

contract PoolRemoveSingle is Test {
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

    address jake = makeAddr("jake"); // pool contract and staking contract owner and deployer of both
    address alice = makeAddr("alice"); // first LP
    address bob = makeAddr("bob"); // second LP

    function setUp() public {
        // 1. deploy tokens
        // 2. deploy pool
        // 3. configure pool
        // 4. deploy staking vault

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

        amplification = 167_237_825_366_714_712_064;

        // deploy pool token
        poolToken = new PoolToken("XYZ Pool Token", "XYZ-PT", 18, jake);

        // deploy pool
        pool = new Pool(address(poolToken), amplification, tokens, rateProviders, weights, jake);

        // deploy staking contract
        staking = new Vault(address(pool), "XYZ Mastervault Token", "XYZ-MVT", 200, 100, jake, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken.setPool(address(pool));
        pool.setVaultAddress(jake);
        vm.stopPrank();
    }

    function testRoundTrip() public {
        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address t = tokens[i];

            vm.startPrank(alice);
            MockToken(t).approve(address(pool), type(uint256).max);
            vm.stopPrank();

            uint256 a = total * weights[i] / mrp.rate(t);
            amounts[i] = a;
            MockToken(t).mint(alice, a);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        (uint256 vbProd, uint256 vbSum) = pool.virtualBalanceProdSum();

        uint256 amount = PRECISION;
        address token = tokens[0];
        MockToken(token).mint(alice, amount);

        uint256[] memory amountsToAdd = new uint256[](numTokens);
        amountsToAdd[0] = amount;

        vm.startPrank(alice);
        pool.addLiquidity(amountsToAdd, 0, bob);
        vm.stopPrank();

        uint256 lpAmount = poolToken.balanceOf(bob);

        // slippage check
        vm.startPrank(bob);
        vm.expectRevert(bytes4(keccak256(bytes("Pool__SlippageLimitExceeded()"))));
        pool.removeLiquiditySingle(0, lpAmount, amount, bob);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.removeLiquiditySingle(0, lpAmount, 0, bob);
        vm.stopPrank();

        uint256 amount2 = MockToken(token).balanceOf(bob);

        assert(amount2 < amount);
        assert((amount - amount2) * 1e13 / amount < 2);

        (uint256 vbProd2, uint256 vbSum2) = pool.virtualBalanceProdSum();
        assert((vbProd > vbProd2 ? vbProd - vbProd2 : vbProd2 - vbProd) * 1e16 / vbProd < 10);
        assert((vbSum > vbSum2 ? vbSum - vbSum2 : vbSum2 - vbSum) * 1e16 / vbSum < 10);
    }

    function testPenalty() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address t = tokens[i];

            vm.startPrank(alice);
            MockToken(t).approve(address(pool), type(uint256).max);
            vm.stopPrank();

            uint256 a = total * weights[i] / mrp.rate(t);
            amounts[i] = a;
            MockToken(t).mint(alice, a);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        uint256 lp = total / 100;
        uint256 prev;

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 snapshot = vm.snapshot();

            address token = tokens[i];
            uint256 exp = estimator.getRemoveSingleLp(i, lp);

            vm.startPrank(alice);
            uint256 res = pool.removeLiquiditySingle(i, lp, 0, bob);
            vm.stopPrank();

            uint256 balance = MockToken(token).balanceOf(bob);
            assert(balance == exp);
            assert(balance == res);

            // pool out of balance, penalty applied
            uint256 amount = balance * mrp.rate(token) / PRECISION;
            assert(amount < lp);

            // later tokens have higher weight, so penalty will be lower
            assert(amount > prev);
            prev = amount;

            vm.revertTo(snapshot);
        }
    }

    function testFee() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address t = tokens[i];

            vm.startPrank(alice);
            MockToken(t).approve(address(pool), type(uint256).max);
            vm.stopPrank();

            uint256 a = total * weights[i] / mrp.rate(t);
            amounts[i] = a;
            MockToken(t).mint(alice, a);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        vm.startPrank(alice);

        uint256 snapshot = vm.snapshot();
        uint256 base = pool.removeLiquiditySingle(0, PRECISION, 0, bob);
        vm.revertTo(snapshot);

        vm.stopPrank();

        // set a fee
        uint256 feeRate = PRECISION / 100;

        vm.startPrank(jake);
        pool.setSwapFeeRate(feeRate);
        vm.stopPrank();

        uint256 exp = estimator.getRemoveSingleLp(0, PRECISION);

        vm.startPrank(alice);
        uint256 res = pool.removeLiquiditySingle(0, PRECISION, 0, bob);
        vm.stopPrank();

        uint256 bal = MockToken(tokens[0]).balanceOf(bob);

        assert(bal == exp);
        assert(bal == res);

        // doing a single sided withdrawal charges fee/2
        assert(bal < base);
        // uint256 actualRate = ((base - bal) * PRECISION) / (base * 2);

        /// TODO not passing
        // assert((actualRate > feeRate ? actualRate - feeRate : feeRate - actualRate) * 1e17 / feeRate < 10);
    }

    function testRateUpdate() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address t = tokens[i];

            vm.startPrank(alice);
            MockToken(t).approve(address(pool), type(uint256).max);
            vm.stopPrank();

            uint256 a = total * weights[i] / mrp.rate(t);
            amounts[i] = a;
            MockToken(t).mint(alice, a);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        // rate update for each token, followed by a single side withdrawal
        // factor = 101 / 100;
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];

            ///////////////////////////////////////////////////////////////////
            uint256 snapshot = vm.snapshot();

            vm.startPrank(alice);
            pool.removeLiquiditySingle(i, PRECISION, 0, bob);
            vm.stopPrank();

            uint256 base = MockToken(token).balanceOf(bob) * mrp.rate(token) / PRECISION;

            vm.revertTo(snapshot);
            ///////////////////////////////////////////////////////////////////
            ///////////////////////////////////////////////////////////////////
            uint256 snapshot1 = vm.snapshot();

            // update rate
            mrp.setRate(token, mrp.rate(token) * 101 / 100);

            // remove liquidity after rate increase
            uint256 exp = estimator.getRemoveSingleLp(i, PRECISION);

            vm.startPrank(alice);
            pool.removeLiquiditySingle(i, PRECISION, 0, bob);
            vm.stopPrank();

            uint256 bal = MockToken(token).balanceOf(bob);
            assert(bal == exp);
            bal = bal * mrp.rate(token) / PRECISION;

            // staking address received rewards
            uint256 exp2 = total * weights[i] / (PRECISION * (101 - 100) / 100);
            uint256 bal2 = poolToken.balanceOf(address(staking));

            assert(bal2 < exp2);
            // assert((exp2 - bal2) * 1000 < exp2);

            vm.revertTo(snapshot1);
            ///////////////////////////////////////////////////////////////////

            // the rate update brought pool out of balance so user receives bonus

            // assert bal > base
            // bal_factor = bal / base
            // assert bal_factor < factor
            // assert abs(bal_factor - factor) / factor < 1e-2

            assert(bal > base);
            assert(bal * 100 < base * 101);
            assert(((base * 101 - bal * 100) / (base * 100)) * 10_000 / 101 < 1);
        }
    }

    function testRampWeight() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address t = tokens[i];

            vm.startPrank(alice);
            MockToken(t).approve(address(pool), type(uint256).max);
            vm.stopPrank();

            uint256 a = total * weights[i] / mrp.rate(t);
            amounts[i] = a;
            MockToken(t).mint(alice, a);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, jake);
        vm.stopPrank();

        uint256 base1;
        {
            uint256 ss = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(1, PRECISION, 0, bob);
            vm.stopPrank();
            base1 = MockToken(tokens[1]).balanceOf(bob);
            vm.revertTo(ss);
        }

        uint256 base2;
        {
            uint256 ss1 = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(2, PRECISION, 0, bob);
            vm.stopPrank();
            base2 = MockToken(tokens[2]).balanceOf(bob);
            vm.revertTo(ss1);
        }

        uint256[] memory weights2 = new uint256[](weights.length);
        weights2[0] = 10 * PRECISION / 100;
        weights2[1] = 30 * PRECISION / 100;
        weights2[2] = 20 * PRECISION / 100;
        weights2[3] = 40 * PRECISION / 100;

        uint256 ts = vm.getBlockTimestamp();
        uint256 newAmplification = 167_237_825_366_714_744_832;
        vm.startPrank(jake);
        pool.setRamp(newAmplification, weights2, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();

        // halfway ramp
        vm.warp(ts + 7 days / 2);
        uint256 exp;
        {
            uint256 ss2 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getRemoveSingleLp(1, PRECISION);
            vm.revertTo(ss2);
        }

        vm.warp(ts + 7 days / 2);
        uint256 mid1;
        {
            uint256 ss3 = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(1, PRECISION, 0, bob);
            vm.stopPrank();
            mid1 = MockToken(tokens[1]).balanceOf(bob);
            assert(_abs(mid1, exp) <= 1);
            assert(mid1 == exp);
            vm.revertTo(ss3);
        }
        vm.warp(ts + 7 days / 2);
        {
            uint256 ss4 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getRemoveSingleLp(2, PRECISION);
            vm.revertTo(ss4);
        }
        vm.warp(ts + 7 days / 2);
        uint256 mid2;
        {
            uint256 ss5 = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(2, PRECISION, 0, bob);
            vm.stopPrank();
            mid2 = MockToken(tokens[2]).balanceOf(bob);
            assert(_abs(mid2, exp) <= 1);
            vm.revertTo(ss5);
        }

        // token 1 share is below weight -> penalty
        assert(mid1 < base1);
        // token 2 share is above weight -> bonus
        assert(mid2 > base2);

        // end of ramp
        vm.warp(ts + 7 days);
        {
            uint256 ss5 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getRemoveSingleLp(1, PRECISION);
            vm.stopPrank();
            vm.revertTo(ss5);
        }
        vm.warp(ts + 7 days);
        uint256 end1;
        {
            uint256 ss6 = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(1, PRECISION, 0, bob);
            vm.stopPrank();
            end1 = MockToken(tokens[1]).balanceOf(bob);
            assert(_abs(end1, exp) <= 2);
            vm.revertTo(ss6);
        }
        vm.warp(ts + 7 days);
        {
            uint256 ss7 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getRemoveSingleLp(2, PRECISION);
            vm.revertTo(ss7);
        }
        vm.warp(ts + 7 days);
        uint256 end2;
        {
            uint256 ss8 = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(2, PRECISION, 0, bob);
            vm.stopPrank();
            end2 = MockToken(tokens[2]).balanceOf(bob);
            assert(_abs(end2, exp) <= 2);
            vm.revertTo(ss8);
        }

        // asset 1 share is more below weight -> bigger penalty
        assert(end1 < mid1);

        //asset 2 share is more above weight -> bigger bonus
        assert(end2 > mid2);
    }

    function testRampAmplification() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address t = tokens[i];

            vm.startPrank(alice);
            MockToken(t).approve(address(pool), type(uint256).max);
            vm.stopPrank();

            uint256 a = total * weights[i] / mrp.rate(t);
            amounts[i] = a;
            MockToken(t).mint(alice, a);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, jake);
        vm.stopPrank();

        uint256 base;
        {
            uint256 ss = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(0, PRECISION, 0, bob);
            vm.stopPrank();
            base = MockToken(tokens[0]).balanceOf(bob);
            vm.revertTo(ss);
        }

        uint256 amplification1 = 10 * pool.amplification();
        uint256 ts = vm.getBlockTimestamp();
        vm.startPrank(jake);
        pool.setRamp(amplification1, weights, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();

        // halfway ramp
        vm.warp(ts + 7 days / 2);
        uint256 exp;
        {
            uint256 ss1 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getRemoveSingleLp(0, PRECISION);
            vm.revertTo(ss1);
        }
        vm.warp(ts + 7 days / 2);
        uint256 mid;
        {
            uint256 ss2 = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(0, PRECISION, 0, bob);
            vm.stopPrank();
            mid = MockToken(tokens[0]).balanceOf(bob);
            assert(_abs(mid, exp) <= 1);
            vm.revertTo(ss2);
        }

        // higher amplification -> lower penalty
        assert(mid > base);

        // end of ramp
        vm.warp(ts + 7 days);
        {
            uint256 ss3 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getRemoveSingleLp(0, PRECISION);
            vm.revertTo(ss3);
        }
        vm.warp(ts + 7 days);
        uint256 end;
        {
            uint256 ss4 = vm.snapshot();
            vm.startPrank(jake);
            pool.removeLiquiditySingle(0, PRECISION, 0, bob);
            vm.stopPrank();
            end = MockToken(tokens[0]).balanceOf(bob);
            assert(_abs(end, exp) <= 2);
            vm.revertTo(ss4);
        }

        // even lower penalty
        assert(end > mid);
    }

    function testLowerBand() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address t = tokens[i];

            vm.startPrank(alice);
            MockToken(t).approve(address(pool), type(uint256).max);
            vm.stopPrank();

            uint256 a = total * weights[i] / mrp.rate(t);
            amounts[i] = a;
            MockToken(t).mint(alice, a);
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, jake);
        vm.stopPrank();

        uint256 lp = total * 2 / 100; // -1.2% after withdrawal

        // withdraw will work before setting a band
        {
            uint256 ss = vm.snapshot();
            estimator.getRemoveSingleLp(3, lp);
            vm.startPrank(jake);
            pool.removeLiquiditySingle(3, lp, 0, bob);
            vm.stopPrank();
            vm.revertTo(ss);
        }

        // set band
        uint256[] memory tokens2 = new uint256[](1);
        uint256[] memory lowerWeightBands = new uint256[](1);
        uint256[] memory upperWeightBands = new uint256[](1);
        tokens2[0] = 3;
        lowerWeightBands[0] = PRECISION / 100;
        upperWeightBands[0] = PRECISION;
        vm.startPrank(jake);
        pool.setWeightBands(tokens2, lowerWeightBands, upperWeightBands);
        vm.stopPrank();

        // withdraw won't work
        vm.expectRevert(abi.encodePacked("ratio below lower band"));
        estimator.getRemoveSingleLp(3, lp);

        vm.startPrank(jake);
        vm.expectRevert(bytes4(keccak256(bytes("Pool__RatioBelowLowerBound()"))));
        pool.removeLiquiditySingle(3, lp, 0, bob);
        vm.stopPrank();
    }

    function testUpperBand() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            address t = tokens[i];

            vm.startPrank(alice);
            MockToken(t).approve(address(pool), type(uint256).max);
            vm.stopPrank();

            uint256 a = total * weights[i] / mrp.rate(t);
            amounts[i] = a;
            MockToken(t).mint(alice, a);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, jake);
        vm.stopPrank();

        uint256 lp = total * 4 / 100; // +1.2% after withdrawal

        // withdraw will work before setting a band
        {
            uint256 ss = vm.snapshot();
            estimator.getRemoveSingleLp(3, lp);
            vm.startPrank(jake);
            pool.removeLiquiditySingle(3, lp, 0, bob);
            vm.stopPrank();
            vm.revertTo(ss);
        }

        // set band
        uint256[] memory tokens2 = new uint256[](1);
        uint256[] memory lowerWeightBands = new uint256[](1);
        uint256[] memory upperWeightBands = new uint256[](1);
        tokens2[0] = 2;
        lowerWeightBands[0] = PRECISION;
        upperWeightBands[0] = PRECISION / 100;
        vm.startPrank(jake);
        pool.setWeightBands(tokens2, lowerWeightBands, upperWeightBands);
        vm.stopPrank();

        // withdraw won't work
        vm.expectRevert(abi.encodePacked("ratio above upper band"));
        estimator.getRemoveSingleLp(3, lp);

        vm.startPrank(jake);
        vm.expectRevert(bytes4(keccak256(bytes("Pool__RatioAboveUpperBound()"))));
        pool.removeLiquiditySingle(3, lp, 0, bob);
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

    function testCalculateWProd() public pure {
        uint256[] memory _weights = new uint256[](4);
        (_weights[0], _weights[1], _weights[2], _weights[3]) =
            (10 * PRECISION / 100, 20 * PRECISION / 100, 30 * PRECISION / 100, 40 * PRECISION / 100);

        uint256 prod = calculateWProd(_weights);

        /*
           .py

           ```
           import math

           PRECISION = 1_000_000_000_000_000_000
           weights = [10*PRECISION//100, 20 * PRECISION //
           100, 30 * PRECISION//100, 40 * PRECISION//100]
           n = len(weights)
           prod = PRECISION

           for w in weights:
               prod = int(prod / math.pow(w / PRECISION, w * n / PRECISION))

           print(prod)
           ```
        */
        uint256 pyRes = 167_237_825_366_714_712_064;

        assert((prod > pyRes ? prod - pyRes : pyRes - prod) < 1e5);
    }
}
