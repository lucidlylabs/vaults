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
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";
import {DepositAggregator} from "../src/DepositAggregator.sol";

contract DepositAggregatorTest is Test {
    Pool pool;
    PoolToken poolToken;
    Vault vault;
    IRateProvider rp;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    uint256 private decimals = 8;
    address public poolOwner;

    MockToken public token0 = new MockToken("name0", "symbol0", 18);
    MockToken public token1 = new MockToken("name1", "symbol1", 8);
    MockToken public token2 = new MockToken("name2", "symbol2", 18);

    address[] public tokens = new address[](3);
    uint256[] public weights = new uint256[](3);
    address[] rateProviders = new address[](3);

    uint256[] public seedAmounts = new uint256[](3);

    address jake = makeAddr("jake"); // pool and staking owner
    address alice = makeAddr("alice"); // first LP
    address bob = makeAddr("bob"); // second LP

    function setUp() public {
        rp = IRateProvider(new MockRateProvider());

        MockRateProvider(address(rp)).setRate(address(token0), 2 ether);
        MockRateProvider(address(rp)).setRate(address(token1), 3 ether);
        MockRateProvider(address(rp)).setRate(address(token2), 4 ether);

        // set tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);

        // set weights
        weights[0] = 40 * PRECISION / 100;
        weights[1] = 30 * PRECISION / 100;
        weights[2] = 30 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(rp);
        rateProviders[1] = address(rp);
        rateProviders[2] = address(rp);

        // amplification = calculateWProd(weights);
        amplification = 500 * 1e18;

        // deploy pool token
        poolToken = new PoolToken("XYZ Pool Token", "lXYZ", 18, jake);

        // deploy pool
        pool = new Pool(address(poolToken), amplification, tokens, rateProviders, weights, jake);

        // deploy staking contract
        vault = new Vault(address(poolToken), "XYZ Vault Share", "XYZVS", 100, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken.setPool(address(pool));
        pool.setStaking(address(vault));
        vm.stopPrank();

        // mint tokens to first lp
        deal(address(token0), alice, 100_000_000 * 1e18); // 100,000,000 SWBTCWBTC_CURVE
        deal(address(token1), alice, 100_000_000 * 1e8); // 100,000,000 SWBTC
        deal(address(token2), alice, 100_000_000 * 1e18); // 100,000,000 GAUNTLET_WBTC_CORE

        uint256 total = 10_000 * 1e8; // considering we seed 10000 WBTC worth of assets

        for (uint256 i = 0; i < 3; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];

            vm.startPrank(alice);

            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");

            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of an asset in WBTC, scaled to 18 precision
            uint256 amount =
                (total * weights[i] * 1e18 * 1e10) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));

            seedAmounts[i] = amount;
        }

        // seed pool
        vm.startPrank(alice);
        uint256 lpAmount = pool.addLiquidity(seedAmounts, 0 ether, alice);
        poolToken.approve(address(vault), lpAmount);
        uint256 shares = vault.deposit(lpAmount, alice);
        vault.transfer(address(vault), shares / 10);
        vm.stopPrank();
    }

    function _calculateSeedAmounts(uint256 total) internal returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];

            vm.startPrank(alice);
            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of an asset in WBTC, scaled to 18 precision
            uint256 amount =
                (total * weights[i] * 1e18 * 1e10) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
            amounts[i] = amount;
        }
        return amounts;
    }

    function testAddLiquidity() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));
        uint256 numTokens = pool.numTokens();

        uint256[] memory amounts1 = new uint256[](numTokens);
        uint256 total1 = 100 * 1e8;

        amounts1 = _calculateSeedAmounts(total1);

        // estimator has to be called before changing pool state
        uint256 lpReceivedEstimated = estimator.getAddLp(amounts1);

        vm.startPrank(alice);
        uint256 lpReceivedActual = pool.addLiquidity(amounts1, 0, alice);
        vm.stopPrank();

        assert(lpReceivedActual == lpReceivedEstimated);
    }

    function testDepositAggregator() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));
        DepositAggregator agg = new DepositAggregator();
        uint256 numTokens = pool.numTokens();
        uint256[] memory amounts1 = new uint256[](numTokens);
        uint256 total1 = 100 * 1e8;
        amounts1 = _calculateSeedAmounts(total1);

        // approve agg as spender
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(ERC20(token).approve(address(agg), type(uint256).max), "could not approve");
            vm.stopPrank();
        }

        uint256 sharesOfAlice = vault.balanceOf(alice);

        vm.startPrank(alice);
        uint256 shares = agg.deposit(tokens, amounts1, alice, 0, address(pool));
        vm.stopPrank();

        assert(shares == (vault.balanceOf(alice) - sharesOfAlice));
    }
}
