// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {PoolOwner} from "../src/PoolOwner.sol";
import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";
import {Aggregator} from "../src/Aggregator.sol";

contract PoolOwnerTest is Test {
    Pool pool;
    PoolToken poolToken;
    Vault vault;
    IRateProvider rp;
    Aggregator agg;
    PoolOwner ownerContract;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    uint256 private decimals = 8;
    address public poolOwner;

    MockToken public token0 = new MockToken("name0", "symbol0", 8);
    MockToken public token1 = new MockToken("name1", "symbol1", 18);
    MockToken public token2 = new MockToken("name2", "symbol2", 6);

    // token to test addToken()
    MockToken public token3 = new MockToken("name3", "symbol3", 12);

    address[] public tokens = new address[](3);
    uint256[] public weights = new uint256[](3);
    address[] rateProviders = new address[](3);

    uint256[] public seedAmounts = new uint256[](3);

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
        vault = new Vault(address(poolToken), "XYZ Vault Share", "XYZVS", 100, 100, jake, jake, jake);

        vm.startPrank(jake);
        ownerContract = new PoolOwner(address(pool));
        pool.transferOwnership(address(ownerContract));
        vm.stopPrank();

        // set staking on pool
        vm.startPrank(jake);
        poolToken.setPool(address(pool));
        vm.stopPrank();

        vm.startPrank(address(ownerContract));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3 bps
        vm.stopPrank();

        vm.startPrank(jake);
        vault.setEntryFeeAddress(jake);
        vault.setEntryFeeInBps(100); // 100 bps
        vm.stopPrank();

        // mint tokens to first lp
        deal(address(token0), alice, 100_000_000 * 1e8); // 100,000,000 SWBTCWBTC_CURVE
        deal(address(token1), alice, 100_000_000 * 1e18); // 100,000,000 SWBTC
        deal(address(token2), alice, 100_000_000 * 1e6); // 100,000,000 USDC
        deal(address(token3), alice, 100_000_000 * 1e12); // 100,000,000 random 12 decimal token

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

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of the asset scaled to 18 precision
            uint256 amount =
                (total * weights[i] * 1e18 * 1e10) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
            amounts[i] = amount;
        }
        return amounts;
    }

    function test__addLiquidity() public {
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

    function test__deposit() public {
        uint256 numTokens = pool.numTokens();
        uint256[] memory amounts = new uint256[](numTokens);
        uint256 total1 = 100 * 1e8;
        amounts = _calculateSeedAmounts(total1);

        // approve agg as spender
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(ERC20(token).approve(address(agg), type(uint256).max), "could not approve");
            vm.stopPrank();
        }

        uint256 sharesOfAlice = vault.balanceOf(alice);

        vm.startPrank(alice);
        uint256 shares = agg.deposit(tokens, amounts, alice, 0, address(pool));
        vm.stopPrank();

        assert(shares == (vault.balanceOf(alice) - sharesOfAlice));
    }

    function test__depositFor() public {
        uint256 numTokens = pool.numTokens();
        uint256[] memory amounts = new uint256[](numTokens);
        uint256 total1 = 100 * 1e8;
        amounts = _calculateSeedAmounts(total1);

        // approve agg as spender
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(ERC20(token).approve(address(agg), type(uint256).max), "could not approve");
            vm.stopPrank();
        }

        uint256 sharesOfAlice = vault.balanceOf(alice);

        vm.startPrank(alice);
        uint256 shares = agg.depositFor(tokens, amounts, alice, 0, address(pool));
        vm.stopPrank();

        assert(shares == (vault.balanceOf(alice) - sharesOfAlice));
    }

    function test__redeemBalanced() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 aliceLpWorth = vault.convertToAssets(aliceShares / 10); // redeem 10% of the balance

        uint256[] memory minAmounts = new uint256[](pool.numTokens());
        uint256[] memory aliceTokenBalancesBefore = new uint256[](pool.numTokens());
        uint256[] memory amountsOutEstimated = new uint256[](pool.numTokens());

        for (uint256 i = 0; i < pool.numTokens(); i++) {
            aliceTokenBalancesBefore[i] = ERC20(pool.tokens(i)).balanceOf(alice);
        }

        amountsOutEstimated = estimator.getRemoveLp(aliceLpWorth);

        vm.startPrank(alice);
        vault.approve(address(agg), type(uint256).max);
        agg.redeemBalanced(address(pool), aliceShares / 10, minAmounts, alice);
        vm.stopPrank();

        assert(aliceShares - vault.balanceOf(alice) == aliceLpWorth);

        for (uint256 i = 0; i < pool.numTokens(); i++) {
            assert(ERC20(pool.tokens(i)).balanceOf(alice) - aliceTokenBalancesBefore[i] == amountsOutEstimated[i]);
        }
    }

    function test__redeemSingle() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 aliceLpWorth = vault.convertToAssets(aliceShares / 10); // redeem 10% of the balance
        uint256 amountOutEstimated = estimator.getRemoveSingleLp(0, aliceLpWorth);

        vm.startPrank(alice);
        vault.approve(address(agg), type(uint256).max);
        uint256 amountOutActual = agg.redeemSingle(address(pool), 0, aliceShares / 10, 0, alice);
        vm.stopPrank();

        assert(aliceShares - vault.balanceOf(alice) == aliceLpWorth);
        assert(amountOutEstimated == amountOutActual);
    }

    function test__transferOwnershipToPoolOwnerContract() public {
        assert(pool.owner() == address(ownerContract));
        assert(ownerContract.owner() == address(jake));

        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.transferPoolOwnership(address(alice));
        vm.stopPrank();

        vm.startPrank(jake);
        ownerContract.transferPoolOwnership(jake);
        vm.stopPrank();
        assert(pool.owner() == jake);
    }

    function test__addTokenThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        // add amount worth 100 units of token0
        // uint256 amountToAdd = poolToken.totalSupply() * token3.decimals() / (100 * PRECISION);
        uint256 amountToAdd = (100 * rp.rate(address(token0)) * PRECISION)
            / (10 ** (token3.decimals() - token0.decimals()) * rp.rate(address(token3)));
        amountToAdd = amountToAdd * 50 / 100;
        deal(address(token3), poolManager, amountToAdd);

        vm.startPrank(poolMonitor);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.addToken(
            address(token3),
            address(rp),
            PRECISION / 100, // target weight
            5 * PRECISION / 100, // lower band
            10 * PRECISION / 100, // upper band
            amountToAdd,
            amplification,
            0,
            jake
        );
        vm.stopPrank();

        uint256 lpBalanceOfJakeCached = poolToken.balanceOf(jake);

        vm.startPrank(poolManager);
        token3.approve(address(ownerContract), amountToAdd);
        ownerContract.addToken(
            address(token3),
            address(rp),
            PRECISION / 100, // target weight
            5 * PRECISION / 100, // lower band
            10 * PRECISION / 100, // upper band
            amountToAdd,
            amplification,
            0,
            jake
        );
        vm.stopPrank();

        uint256 lpTokensMintedToJake = poolToken.balanceOf(jake) - lpBalanceOfJakeCached;
        uint256 token3WorthAdded =
            (amountToAdd * 10 ** (36 - token3.decimals()) * rp.rate(address(token3))) / (PRECISION * PRECISION);
        assert((token3WorthAdded - lpTokensMintedToJake) * PRECISION / token3WorthAdded <= 1e17);
    }

    function test__setSwapFeeRateThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        vm.startPrank(poolMonitor);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.setSwapFeeRate(5 * PRECISION / 10_000);
        vm.stopPrank();

        vm.startPrank(poolManager);
        ownerContract.setSwapFeeRate(5 * PRECISION / 10_000);
        vm.stopPrank();
    }

    function test__setWeightBandsThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        // set band
        uint256[] memory tokens2 = new uint256[](1);
        uint256[] memory lowerWeightBands = new uint256[](1);
        uint256[] memory upperWeightBands = new uint256[](1);

        tokens2[0] = 2;
        lowerWeightBands[0] = PRECISION / 100;
        upperWeightBands[0] = PRECISION;

        vm.startPrank(poolMonitor);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.setWeightBands(tokens2, lowerWeightBands, upperWeightBands);
        vm.stopPrank();

        vm.startPrank(poolManager);
        ownerContract.setWeightBands(tokens2, lowerWeightBands, upperWeightBands);
        vm.stopPrank();
    }

    function test__setVaultAddressThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        vm.startPrank(poolMonitor);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.setVaultAddress(address(0x1));
        vm.stopPrank();

        vm.startPrank(poolManager);
        ownerContract.setVaultAddress(address(0x1));
        vm.stopPrank();
    }

    function test__setRateProviderThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        IRateProvider rp1 = IRateProvider(new MockRateProvider());
        MockRateProvider(address(rp1)).setRate(address(token0), 6 ether);

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        vm.startPrank(poolMonitor);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.setRateProvider(0, address(rp1));
        vm.stopPrank();

        vm.startPrank(poolManager);
        ownerContract.setRateProvider(0, address(rp1));
        vm.stopPrank();
    }

    function test__setRampThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        uint256[] memory newWeights = new uint256[](3);
        newWeights[0] = PRECISION * 10 / 100;
        newWeights[1] = PRECISION * 30 / 100;
        newWeights[2] = PRECISION * 60 / 100;

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        vm.startPrank(poolMonitor);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.setRamp(amplification * 90 / 100, newWeights, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();

        vm.startPrank(poolManager);
        ownerContract.setRamp(amplification * 90 / 100, newWeights, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();
    }

    function test__setRampStepThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        vm.startPrank(poolMonitor);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.setRampStep(2 days);
        vm.stopPrank();

        vm.startPrank(poolManager);
        ownerContract.setRampStep(2 days);
        vm.stopPrank();
    }

    function test__stopRampThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        uint256[] memory newWeights = new uint256[](3);
        newWeights[0] = PRECISION * 10 / 100;
        newWeights[1] = PRECISION * 30 / 100;
        newWeights[2] = PRECISION * 60 / 100;

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        vm.startPrank(poolManager);
        ownerContract.setRamp(amplification * 90 / 100, newWeights, 7 days, vm.getBlockTimestamp());
        vm.stopPrank();

        vm.warp(301_700);

        vm.startPrank(poolMonitor);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.stopRamp();
        vm.stopPrank();

        vm.startPrank(poolManager);
        ownerContract.stopRamp();
        vm.stopPrank();
    }

    function test__pausePoolThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        vm.startPrank(poolManager);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.pausePool();
        vm.stopPrank();

        vm.startPrank(poolMonitor);
        ownerContract.pausePool();
        vm.stopPrank();
    }

    function test__unpausePoolThroughPoolOwnerContract() public {
        address poolManager = makeAddr("poolManager");
        address poolMonitor = makeAddr("poolMonitor");

        vm.startPrank(jake);
        ownerContract.grantRoles(poolManager, ownerContract.ROLE_POOL_MANAGER());
        ownerContract.grantRoles(poolMonitor, ownerContract.ROLE_POOL_MONITOR());
        vm.stopPrank();

        vm.startPrank(poolMonitor);
        ownerContract.pausePool();
        vm.stopPrank();

        vm.startPrank(poolManager);
        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        ownerContract.unpausePool();
        vm.stopPrank();

        vm.startPrank(poolMonitor);
        ownerContract.unpausePool();
        vm.stopPrank();
    }
}
