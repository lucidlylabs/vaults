// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {PoolV2} from "../src/PoolV2.sol";
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
        weights[2] = 49 * PRECISION / 100;
        weights[3] = 1 * PRECISION / 100;

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
        vault = new Vault(address(poolToken), "XYZ Vault Share", "XYZVS", 100, jake, jake);

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

    function _calculateSeedAmounts(uint256 total, uint256 quoteTokenDecimals, address sender)
        internal
        returns (uint256[] memory)
    {
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];

            vm.startPrank(sender);
            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of the asset scaled to 18 precision

            // considering quoteTokenDecimals is <= 18
            // this is redundant code
            uint256 amount = (total * weights[i] * 1e18 * 10 ** (18 - ERC20(token).decimals()))
                / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
            amounts[i] = amount;
        }
        return amounts;
    }

    function test__poolRemoveToken() public {
        uint256 _numTokens = pool.numTokens();

        deal(address(token0), jake, 100_000_000 * 1e8); // 100,000,000 SWBTCWBTC_CURVE
        deal(address(token1), jake, 100_000_000 * 1e18); // 100,000,000 SWBTC
        deal(address(token2), jake, 100_000_000 * 1e8); // 100,000,000 cbBTC
        deal(address(token3), jake, 100_000_000 * 1e8); // 100,000,000 SWBTC

        uint256[] memory amounts = new uint256[](4);
        uint256 total = 1000 * 1e18; // considering we seed 10000 WBTC worth of assets

        for (uint256 i = 0; i < 4; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];

            vm.startPrank(jake);
            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of an asset in WBTC, scaled to 18 precision
            uint256 amount = (total * weights[i] * 1e18) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
            amounts[i] = amount;
        }

        amounts[3] = 0;
        console.log("lp token supply before adding liquidity:", poolToken.totalSupply());
        vm.startPrank(jake);
        uint256 lpAdded = pool.addLiquidity(amounts, 0, jake);

        console.log("lp token balance:", lpAdded);
        console.log("tokens[3] balance in pool", ERC20(pool.tokens(3)).balanceOf(address(pool)));

        console.log("before removing token -----");
        console.log("pool balances");
        for (uint256 i = 0; i < 4; i++) {
            console.log(i, "=", ERC20(tokens[i]).balanceOf(address(pool)));
        }
        console.log("lp token supply:", poolToken.totalSupply());
        console.log("pool supply:", pool.supply());

        poolToken.approve(address(pool), type(uint256).max);
        uint256 ampl = pool.amplification();
        pool.removeToken(3, lpAdded, ampl);

        console.log("after removing token -----");
        console.log("pool balances");
        for (uint256 i = 0; i < 4; i++) {
            console.log(i, "=", ERC20(tokens[i]).balanceOf(address(pool)));
        }
        console.log("lp token supply:", poolToken.totalSupply());
        console.log("pool supply:", pool.supply());

        console.log("numTokens now:", pool.numTokens());

        vm.stopPrank();
    }

    function test__AssertVbSumAndSupply() public {
        uint256 _supply;
        uint256 _numTokens = pool.numTokens();

        uint256 lpAmount;
        uint256 expectedSupply;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;
            uint256 _virtualBalance = pool.packedVirtualBalances(t) & (2 ** 96 - 1);
            uint256 _rate = (pool.packedVirtualBalances(t) >> 96) & (2 ** 80 - 1);

            expectedSupply += _virtualBalance * _rate / 1e18;
        }
    }

    function _calculateVirtualBalanceSum() internal view returns (uint256) {
        uint256 _numTokens = pool.numTokens();
        uint256 _sum = 0;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;
            _sum = FixedPointMathLib.rawAdd(_sum, pool.packedVirtualBalances(t) & (2 ** 96 - 1));
        }
        return _sum;
    }

    // function test__SetWeightToZero() public {
    //     PoolEstimator est = new PoolEstimator(address(pool));

    //     uint256 numTokens = pool.numTokens();
    //     uint256 total = 1000 * 1e18;
    //     uint256[] memory amounts = _calculateSeedAmounts(total, 18, jake);

    //     // vm.startPrank(alice);
    //     // uint256 lp1 = pool.addLiquidity(amounts, 0, alice);
    //     // vm.stopPrank();

    //     uint256[] memory newWeights = new uint256[](4);
    //     newWeights[0] = 40 * PRECISION / 100;
    //     newWeights[1] = 30 * PRECISION / 100;
    //     newWeights[2] = 299 * PRECISION / 1000;
    //     newWeights[3] = 1 * PRECISION / 1000;

    //     uint256 newAmplification = 600 * PRECISION;

    //     vm.startPrank(jake);
    //     pool.setRamp(newAmplification, newWeights, 7 days, vm.getBlockTimestamp());
    //     vm.stopPrank();

    //     uint256 ts = vm.getBlockTimestamp();

    //     vm.startPrank(alice);
    //     uint256 seedLpRedeemed = vault.redeem(vault.balanceOf(alice), alice, alice);
    //     vm.stopPrank();

    //     uint256 token3BalanceInPool = ERC20(pool.tokens(3)).balanceOf(address(pool));
    //     uint256 token3WorthInPool = token3BalanceInPool * rp.rate(pool.tokens(3)) / PRECISION;

    //     uint256 totalLpOfAlice = poolToken.balanceOf(alice);
    //     uint256 tokenOut1;
    //     uint256 tokenOut2;
    //     uint256 tokenOut3;

    //     uint256 lpToRemove = totalLpOfAlice * 30 / 100;
    //     uint256[] memory newLp = new uint256[](4);
    //     newLp[0] = _getTokenAmountFromLp(lpToRemove, 0);

    //     uint256 ss1 = vm.snapshotState();
    //     vm.startPrank(alice);
    //     console.log("token3 weight in the pool now:", _getWeightOfToken(3));
    //     // vm.expectRevert(bytes4(keccak256(bytes("Pool__NoConvergence()"))));
    //     tokenOut1 = pool.removeLiquiditySingle(3, lpToRemove, 0, alice);
    //     pool.addLiquidity(newLp, 0, alice);
    //     vm.stopPrank();
    //     assert(token3BalanceInPool > tokenOut1);
    //     console.log("First attempt -> 0 day");
    //     console.log("pool token3 balance before:", token3BalanceInPool);
    //     console.log("pool token3 balance removed:", tokenOut1);
    //     console.log("pool token3 balance now:", ERC20(pool.tokens(3)).balanceOf(address(pool)));
    //     console.log("token3 weight in the pool now:", _getWeightOfToken(3));
    //     assert(ERC20(pool.tokens(3)).balanceOf(address(pool)) + tokenOut1 == token3BalanceInPool);
    //     vm.revertToState(ss1);

    //     console.log("////////////////////////////////////////////////////////");

    //     // halfway ramp
    //     vm.warp(ts + 7 days / 2);

    //     uint256 ss2 = vm.snapshotState();
    //     vm.startPrank(alice);
    //     console.log("token3 weight in the pool now:", _getWeightOfToken(3));
    //     // vm.expectRevert(bytes4(keccak256(bytes("Pool__NoConvergence()"))));
    //     tokenOut2 = pool.removeLiquiditySingle(3, lpToRemove, 0, alice);
    //     pool.addLiquidity(newLp, 0, alice);
    //     vm.stopPrank();
    //     assert(token3BalanceInPool > tokenOut2);
    //     console.log("Second attempt -> 3.5 day");
    //     console.log("pool token3 balance before:", token3BalanceInPool);
    //     console.log("pool token3 balance removed:", tokenOut2);
    //     console.log("pool token3 balance now:", ERC20(pool.tokens(3)).balanceOf(address(pool)));
    //     console.log("token3 weight in the pool now:", _getWeightOfToken(3));
    //     assert(ERC20(pool.tokens(3)).balanceOf(address(pool)) + tokenOut2 == token3BalanceInPool);
    //     vm.revertToState(ss2);

    //     console.log("////////////////////////////////////////////////////////");

    //     // halfway ramp
    //     vm.warp(ts + 7 days);

    //     uint256 ss3 = vm.snapshotState();
    //     vm.startPrank(alice);
    //     console.log("token3 weight in the pool now:", _getWeightOfToken(3));
    //     // vm.expectRevert(bytes4(keccak256(bytes("Pool__NoConvergence()"))));
    //     tokenOut3 = pool.removeLiquiditySingle(3, lpToRemove, 0, alice);
    //     pool.addLiquidity(newLp, 0, alice);
    //     vm.stopPrank();
    //     assert(token3BalanceInPool > tokenOut2);
    //     console.log("Third attempt -> 7 day");
    //     console.log("pool token3 balance before:", token3BalanceInPool);
    //     console.log("pool token3 balance removed:", tokenOut3);
    //     console.log("pool token3 balance now:", ERC20(pool.tokens(3)).balanceOf(address(pool)));
    //     console.log("token3 weight in the pool now:", _getWeightOfToken(3));
    //     assert(ERC20(pool.tokens(3)).balanceOf(address(pool)) + tokenOut3 == token3BalanceInPool);
    //     vm.revertToState(ss3);
    // }

    function _getWeightOfToken(uint256 token) internal returns (uint256) {
        uint256 numTokens = pool.numTokens();
        uint256 totalVb;
        for (uint256 i = 0; i < numTokens; i++) {
            totalVb = totalVb + pool.virtualBalance(i);
        }

        return pool.virtualBalance(token) * PRECISION / totalVb;
    }

    function _getTokenAmountFromLp(uint256 lpAmount, uint256 token) internal returns (uint256) {
        uint256 rate = IRateProvider(pool.rateProviders(token)).rate(pool.tokens(token));
        uint256 unadjustedAmount = lpAmount * PRECISION / rate;

        return unadjustedAmount * PRECISION / (10 ** (36 - ERC20(pool.tokens(token)).decimals()));
    }
}
