// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {MasterVault} from "../src/Staking.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";

contract PoolSwapWithDifferentDecimals is Test {
    Pool pool;
    PoolToken poolToken;
    MasterVault staking;
    MockRateProvider mrp;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    address public poolOwner;

    MockToken public token0;
    MockToken public token1;
    MockToken public token2;
    MockToken public token3;

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
        // 5. add liquidity to pool

        token0 = new MockToken("token0", "t0", 6);
        token1 = new MockToken("token1", "t1", 18);
        token2 = new MockToken("token2", "t2", 8);
        token3 = new MockToken("token3", "t3", 15);

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
        staking = new MasterVault(address(poolToken), "XYZ Mastervault Token", "XYZ-MVT", 200, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken.setPool(address(pool));
        pool.setStaking(address(staking));
        vm.stopPrank();
    }

    function testRoundTrip() public {
        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;

        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];
            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();
            uint256 amountToMint = (total * weights[i]) / MockRateProvider(rateProvider).rate(token);
            MockToken(token).mint(alice, amountToMint);
            amounts[i] = amountToMint;
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0 ether, alice);
        vm.stopPrank();

        (uint256 vbProd, uint256 vbSum) = pool.virtualBalanceProdSum();

        uint256 amount = PRECISION;
        MockToken(tokens[0]).mint(alice, amount);

        vm.startPrank(alice);
        pool.swap(0, 1, amount, 0, bob);
        vm.stopPrank();

        uint256 balBob = MockToken(tokens[1]).balanceOf(bob);

        vm.startPrank(bob);
        MockToken(tokens[1]).approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // slippage check
        vm.startPrank(bob);
        vm.expectRevert(bytes4(keccak256(bytes("Pool__SlippageLimitExceeded()"))));
        pool.swap(1, 0, balBob, amount, bob);
        vm.stopPrank();

        vm.startPrank(bob);
        pool.swap(1, 0, balBob, 0, bob);
        vm.stopPrank();

        uint256 amount2 = MockToken(tokens[0]).balanceOf(bob);

        // rounding in favor of pool
        assert(amount2 < amount);
        assert(((amount - amount2) / amount) * 1e14 < 10);

        (uint256 vbProd2, uint256 vbSum2) = pool.virtualBalanceProdSum();

        if (vbProd2 > vbProd) {
            assert(((vbProd2 - vbProd) / vbProd) * 1e16 < 3);
        } else {
            assert(((vbProd - vbProd2) / vbProd) * 1e16 < 3);
        }

        if (vbSum2 > vbSum) {
            assert(((vbSum2 - vbSum) / vbSum) * 1e16 < 2);
        } else {
            assert(((vbSum - vbSum2) / vbSum) * 1e16 < 2);
        }
    }

    function testPenalty() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;

        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];
            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();
            uint256 amountToMint = (total * weights[i]) / MockRateProvider(rateProvider).rate(token);
            MockToken(token).mint(alice, amountToMint);
            amounts[i] = amountToMint;
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0 ether, alice);
        vm.stopPrank();

        uint256 swap = total / 100;
        MockToken(tokens[0]).mint(alice, swap);
        uint256 prev;

        for (uint256 i = 1; i < numTokens; i++) {
            uint256 snapshot = vm.snapshot();
            {
                address token = tokens[i];
                uint256 exp = estimator.getOutputToken(0, i, swap);

                vm.startPrank(alice);
                uint256 res = pool.swap(0, i, swap, 0, bob);
                vm.stopPrank();
                uint256 bal = MockToken(token).balanceOf(bob);

                assert(bal == exp);
                assert(bal == res);

                // pool out of balance, penalty applied
                uint256 amount = bal * mrp.rate(token) / PRECISION;
                assert(amount < swap * mrp.rate(token) / PRECISION);

                // later assets have higher weight, so penalty will be lower
                assert(amount > prev);
                prev = amount;
            }
            vm.revertTo(snapshot);
        }
    }

    function testFee() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();
            uint256 amountToMint = (total * weights[i]) / mrp.rate(token);
            MockToken(token).mint(alice, amountToMint);
            amounts[i] = amountToMint;
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0 ether, alice);
        vm.stopPrank();

        uint256 amount = PRECISION;
        MockToken(tokens[0]).mint(alice, amount);

        uint256 snapshot = vm.snapshot();
        vm.startPrank(alice);
        uint256 base = pool.swap(0, 1, amount, 0, bob);
        vm.stopPrank();
        vm.revertTo(snapshot);

        uint256 feeRate = PRECISION / 100;

        vm.startPrank(jake);
        pool.setSwapFeeRate(feeRate);
        vm.stopPrank();

        uint256 exp = estimator.getOutputToken(0, 1, amount);

        vm.startPrank(alice);
        uint256 res = pool.swap(0, 1, amount, 0, bob);
        vm.stopPrank();

        uint256 bal = MockToken(tokens[1]).balanceOf(bob);

        assert(bal == exp);
        assert(bal == res);

        assert(bal < base);
        uint256 actualRate = (base - bal) * PRECISION / base;
        if (actualRate > feeRate) {
            assert((actualRate - feeRate) / feeRate * 1e4 < 4);
        } else {
            assert((feeRate - actualRate) / feeRate * 1e4 < 4);
        }
    }

    function testRateUpdate() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1_000_000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();
            uint256 amountToMint = (total * weights[i]) / mrp.rate(token);
            MockToken(token).mint(alice, amountToMint);
            amounts[i] = amountToMint;
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0 ether, alice);
        vm.stopPrank();

        MockToken(tokens[0]).mint(alice, PRECISION);

        //  rate update of each token, followed by swap
        uint256 factor = 101 * PRECISION / 100;
        // uint256 factor = 1_173_868_744_800_786_254 * PRECISION / 1_173_959_129_341_288_733;
        for (uint256 i = 1; i < numTokens; i++) {
            address token = tokens[i];
            uint256 base;
            {
                uint256 ss = vm.snapshot();
                vm.startPrank(alice);
                pool.swap(0, i, PRECISION, 0, bob);
                vm.stopPrank();
                base = MockToken(token).balanceOf(bob) * mrp.rate(token) / PRECISION;
                vm.revertTo(ss);
            }
            uint256 exp;
            uint256 exp2;
            uint256 bal;
            uint256 bal2;
            {
                uint256 ss1 = vm.snapshot();
                vm.startPrank(alice);
                mrp.setRate(token, mrp.rate(token) * factor / PRECISION);
                vm.stopPrank();

                // swap after rate increase
                exp = estimator.getOutputToken(0, i, PRECISION);
                vm.startPrank(alice);
                pool.swap(0, i, PRECISION, 0, bob);
                vm.stopPrank();
                bal = MockToken(token).balanceOf(bob);
                assert(bal == exp);
                bal = bal * mrp.rate(token) / PRECISION;

                // staking address received rewards
                exp2 = total * weights[i] / PRECISION * (factor - PRECISION);
                bal2 = poolToken.balanceOf(address(staking));
                // assert(bal2 < exp2);
                // assert(_abs(bal2, exp2) * PRECISION / exp2 < PRECISION / 1e4);
                vm.revertTo(ss1);
            }

            // the rate update brought pool out of balance so user receives bonus
            assert(bal > base);
            uint256 bal_factor = bal * PRECISION / base;
            assert(bal_factor < factor);
            assert(_abs(bal_factor, factor) * PRECISION / factor < 1e16);
        }
    }

    function testRateUpdateDown() public {
        vm.startPrank(jake);
        pool.setSwapFeeRate(300_000_000_000_000);
        vm.stopPrank();

        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1_000_000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();
            uint256 amountToMint = (total * weights[i]) / mrp.rate(token);
            MockToken(token).mint(alice, amountToMint);
            amounts[i] = amountToMint;
        }
        vm.startPrank(alice);
        uint256 tokensReceived = pool.addLiquidity(amounts, 0, address(alice));
        vm.stopPrank();

        console.log("balance of alice: ", poolToken.balanceOf(alice));

        // alice deposits poolTokens into masterVault
        vm.startPrank(alice);
        poolToken.approve(address(staking), type(uint256).max);
        staking.deposit(tokensReceived / 10, address(staking));
        vm.stopPrank();

        MockToken(tokens[0]).mint(alice, PRECISION);

        //  rate update of each token, followed by swap
        // uint256 factor = 101 * PRECISION / 100;
        uint256 factor = 1_173_868_744_800_786_254 * PRECISION / 1_173_959_129_341_288_733;
        for (uint256 i = 1; i < numTokens; i++) {
            address token = tokens[i];
            uint256 base;
            {
                uint256 ss = vm.snapshot();
                vm.startPrank(alice);
                pool.swap(0, i, PRECISION, 0, bob);
                vm.stopPrank();
                base = MockToken(token).balanceOf(bob) * mrp.rate(token) / PRECISION;
                vm.revertTo(ss);
            }
            uint256 exp;
            uint256 exp2;
            uint256 bal;
            uint256 bal2;
            {
                uint256 ss1 = vm.snapshot();
                vm.startPrank(alice);
                mrp.setRate(token, mrp.rate(token) * factor / PRECISION);
                vm.stopPrank();

                // swap after rate increase
                exp = estimator.getOutputToken(0, i, PRECISION);
                vm.startPrank(alice);
                pool.swap(0, i, PRECISION, 0, bob);
                vm.stopPrank();
                bal = MockToken(token).balanceOf(bob);
                assert(bal == exp);
                bal = bal * mrp.rate(token) / PRECISION;

                // staking address received rewards
                // exp2 = total * weights[i] / PRECISION * (factor - PRECISION);
                exp2 = total * weights[i] / PRECISION * (PRECISION - factor);
                bal2 = poolToken.balanceOf(address(staking));
                // assert(bal2 < exp2);
                // assert(_abs(bal2, exp2) * PRECISION / exp2 < PRECISION / 1e4);
                vm.revertTo(ss1);
            }

            // the rate update brought pool out of balance so user receives bonus
            // assert(bal > base);
            // uint256 bal_factor = bal * PRECISION / base;
            // assert(bal_factor < factor);
            // assert(_abs(bal_factor, factor) * PRECISION / factor < 1e16);
        }
    }

    function testRampWeight() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1_000_000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();
            uint256 amountToMint = (total * weights[i]) / mrp.rate(token);
            MockToken(token).mint(alice, amountToMint);
            amounts[i] = amountToMint;
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, address(staking));
        vm.stopPrank();

        MockToken(tokens[0]).mint(alice, PRECISION);

        uint256 base1;
        {
            uint256 ss = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 1, PRECISION, 0, bob);
            vm.stopPrank();
            base1 = MockToken(tokens[1]).balanceOf(bob);
            vm.revertTo(ss);
        }
        uint256 base2;
        {
            uint256 ss1 = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 2, PRECISION, 0, bob);
            vm.stopPrank();
            base2 = MockToken(tokens[2]).balanceOf(bob);
            vm.revertTo(ss1);
        }

        uint256[] memory weights2 = new uint256[](numTokens);
        weights2[0] = PRECISION * 1 / 10;
        weights2[1] = PRECISION * 3 / 10;
        weights2[2] = PRECISION * 2 / 10;
        weights2[3] = PRECISION * 4 / 10;

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
            exp = estimator.getOutputToken(0, 1, PRECISION);
            vm.revertTo(ss2);
        }
        vm.warp(ts + 7 days / 2);
        uint256 mid1;
        {
            uint256 ss3 = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 1, PRECISION, 0, bob);
            vm.stopPrank();
            mid1 = MockToken(tokens[1]).balanceOf(bob);
            assert(_abs(mid1, exp) <= 2);
            vm.revertTo(ss3);
        }
        vm.warp(ts + 7 days / 2);
        {
            uint256 ss3 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getOutputToken(0, 2, PRECISION);
            vm.revertTo(ss3);
        }
        vm.warp(ts + 7 days / 2);
        uint256 mid2;
        {
            uint256 ss4 = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 2, PRECISION, 0, bob);
            vm.stopPrank();
            mid2 = MockToken(tokens[2]).balanceOf(bob);
            assert(_abs(mid2, exp) <= 1);
            vm.revertTo(ss4);
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
            exp = estimator.getOutputToken(0, 1, PRECISION);
            vm.revertTo(ss5);
        }
        vm.warp(ts + 7 days);
        uint256 end1;
        {
            uint256 ss6 = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 1, PRECISION, 0, bob);
            vm.stopPrank();
            end1 = MockToken(tokens[1]).balanceOf(bob);
            assert(_abs(end1, exp) <= 4);
            vm.revertTo(ss6);
        }
        vm.warp(ts + 7 days);
        {
            uint256 ss7 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getOutputToken(0, 2, PRECISION);
            vm.revertTo(ss7);
        }
        vm.warp(ts + 7 days);
        uint256 end2;
        {
            uint256 ss8 = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 2, PRECISION, 0, bob);
            vm.stopPrank();
            end2 = MockToken(tokens[2]).balanceOf(bob);
            assert(_abs(end2, exp) <= 2);
            vm.revertTo(ss8);
        }

        // token 1 share is more below weight -> bigger penalty
        assert(end1 < mid1);

        // token 2 share is more above weight -> bigger bonus
        assert(end2 > mid2);
    }

    function testRampAmplification() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1_000_000 * PRECISION;
        uint256[] memory amounts = new uint256[](numTokens);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(MockToken(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();
            uint256 amountToMint = (total * weights[i]) / mrp.rate(token);
            MockToken(token).mint(alice, amountToMint);
            amounts[i] = amountToMint;
        }
        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, address(staking));
        vm.stopPrank();

        MockToken(tokens[0]).mint(alice, PRECISION);

        uint256 base;
        {
            uint256 ss = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 1, PRECISION, 0, bob);
            vm.stopPrank();
            base = MockToken(tokens[1]).balanceOf(bob);
            vm.revertTo(ss);
        }

        uint256 amplification2 = 10 * pool.amplification();
        uint256 ts = vm.getBlockTimestamp();
        vm.startPrank(jake);
        pool.setRamp(amplification2, weights, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();

        // halfway ramp
        vm.warp(ts + 7 days / 2);
        uint256 exp;
        {
            uint256 ss1 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getOutputToken(0, 1, PRECISION);
            vm.revertTo(ss1);
        }

        vm.warp(ts + 7 days / 2);
        uint256 mid;
        {
            uint256 ss1 = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 1, PRECISION, 0, bob);
            vm.stopPrank();
            mid = MockToken(tokens[1]).balanceOf(bob);
            assert(_abs(mid, exp) <= 1);
            vm.revertTo(ss1);
        }

        // higher amplification -> lower penalty
        assert(mid > base);

        // end of ramp
        vm.warp(ts + 7 days);
        {
            uint256 ss2 = vm.snapshot();
            vm.roll(vm.getBlockNumber() + 1);
            exp = estimator.getOutputToken(0, 1, PRECISION);
            vm.revertTo(ss2);
        }
        vm.warp(ts + 7 days);
        uint256 end;
        {
            uint256 ss3 = vm.snapshot();
            vm.startPrank(alice);
            pool.swap(0, 1, PRECISION, 0, bob);
            vm.stopPrank();
            end = MockToken(tokens[1]).balanceOf(bob);
            assert(_abs(end, exp) <= 1);
            vm.revertTo(ss3);
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
        pool.addLiquidity(amounts, 0, address(staking));
        vm.stopPrank();

        uint256 amount = total * 2 / 100 * PRECISION / mrp.rate(tokens[0]);
        MockToken(tokens[0]).mint(alice, amount);

        // swap will work before setting a band
        {
            uint256 ss = vm.snapshot();
            estimator.getOutputToken(0, 3, amount);
            vm.startPrank(alice);
            pool.swap(0, 3, amount, 0, bob);
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

        // swapping won't work anymore
        vm.expectRevert(abi.encodePacked("ratio below lower band"));
        estimator.getOutputToken(0, 3, amount);

        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256(bytes("Pool__RatioBelowLowerBound()"))));
        pool.swap(0, 3, amount, 0, bob);
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
        pool.addLiquidity(amounts, 0, address(staking));
        vm.stopPrank();

        uint256 amount = total * 2 / 100 * PRECISION / mrp.rate(tokens[0]);
        MockToken(tokens[0]).mint(alice, amount);

        // swap will work before setting a band
        {
            uint256 ss = vm.snapshot();
            estimator.getOutputToken(0, 3, amount);
            vm.startPrank(alice);
            pool.swap(0, 3, amount, 0, bob);
            vm.stopPrank();
            vm.revertTo(ss);
        }

        // set band
        uint256[] memory tokens2 = new uint256[](1);
        uint256[] memory lowerWeightBands = new uint256[](1);
        uint256[] memory upperWeightBands = new uint256[](1);
        tokens2[0] = 0;
        lowerWeightBands[0] = PRECISION;
        upperWeightBands[0] = PRECISION / 100;
        vm.startPrank(jake);
        pool.setWeightBands(tokens2, lowerWeightBands, upperWeightBands);
        vm.stopPrank();

        // swapping won't work anymore
        vm.expectRevert(abi.encodePacked("ratio above upper band"));
        estimator.getOutputToken(0, 3, amount);

        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256(bytes("Pool__RatioAboveUpperBound()"))));
        pool.swap(0, 3, amount, 0, bob);
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
