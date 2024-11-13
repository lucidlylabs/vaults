// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

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

contract PoolRemove is Test {
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

        amplification = calculateWProd(weights);

        // deploy pool token
        poolToken = new PoolToken("XYZ Pool Token", "XYZ-PT", 18, jake);

        // deploy pool
        pool = new Pool(address(poolToken), amplification, tokens, rateProviders, weights, jake);

        // deploy staking contract
        staking = new Vault(address(pool), "XYZ Mastervault Token", "XYZ-MVT", 200, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken.setPool(address(pool));
        pool.setStaking(address(staking));
        vm.stopPrank();
    }

    function testRoundTrip() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));

        uint256 numTokens = pool.numTokens();
        uint256 total = 1000 * PRECISION;
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
        pool.addLiquidity(amounts, 0, bob);
        vm.stopPrank();

        (uint256 vbProd, uint256 vbSum) = pool.virtualBalanceProdSum();

        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            amounts[i] = amounts[i] / 100;
            MockToken(token).mint(alice, amounts[i]);
        }

        vm.startPrank(alice);
        pool.addLiquidity(amounts, 0, alice);
        vm.stopPrank();

        uint256 lpAmount = poolToken.balanceOf(alice);

        // slippage check
        for (uint256 i = 0; i < numTokens; i++) {
            uint256[] memory amountsToRemove = new uint256[](numTokens);
            for (uint256 j = 0; j < numTokens; j++) {
                if (i == j) amountsToRemove[j] = amounts[i];
                else amountsToRemove[j] = 0;
            }

            vm.startPrank(alice);
            vm.expectRevert(bytes4(keccak256(bytes("Pool__SlippageLimitExceeded()"))));
            pool.removeLiquidity(lpAmount, amountsToRemove, bob);
            vm.stopPrank();
        }

        uint256[] memory exp = estimator.getRemoveLp(lpAmount);

        vm.startPrank(alice);
        pool.removeLiquidity(lpAmount, new uint256[](numTokens), bob);
        vm.stopPrank();

        for (uint256 i = 0; i < numTokens; i++) {
            // rounding in favor of pool
            uint256 amount = amounts[i];
            uint256 amount2 = MockToken(tokens[i]).balanceOf(bob);

            assert(amount2 < amount);
            assert(amount2 == exp[i]);
            assert((amount - amount2) * 1e14 / amount < 3);
        }

        (uint256 vbProd2, uint256 vbSum2) = pool.virtualBalanceProdSum();
        assert((vbProd > vbProd2 ? vbProd - vbProd2 : vbProd2 - vbProd) * 1e16 / vbProd < 10);
        assert((vbSum > vbSum2 ? vbSum - vbSum2 : vbSum2 - vbSum) * 1e16 / vbSum < 10);
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
