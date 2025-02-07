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
import {AtomicQueue} from "../src/AtomicQueue/AtomicQueue.sol";
import {RateProviderRepository} from "../src/RateProvider/RateProviderRepository.sol";

contract AtomicQueueTest is Test {
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
        pool = new PoolV2(address(poolToken), amplification, tokens, rateProviders, weights, jake);

        // deploy staking contract
        vault = new Vault(address(poolToken), "XYZ Vault Share", "XYZVS", 100, 100, jake, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3 bps
        vault.setEntryFeeAddress(jake);
        vault.setEntryFeeInBps(100); // 100 bps
        vm.stopPrank();

        // mint tokens to first lp
        deal(address(token0), alice, 100_000_000 * 1e8); // 100,000,000 SWBTCWBTC_CURVE
        deal(address(token1), alice, 100_000_000 * 1e18); // 100,000,000 SWBTC
        deal(address(token2), alice, 100_000_000 * 1e6); // 100,000,000 USDC

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

    function test__SafeUpdateAtomicDepositRequest() public {
        vm.startPrank(jake);
        AtomicQueue queue = new AtomicQueue(jake);
        RateProviderRepository rateRepo = new RateProviderRepository(address(vault), address(pool), address(token0));
        vm.stopPrank();

        address user = makeAddr("userA");

        MockToken token4 = new MockToken("name4", "symbol4", 8);
        deal(address(token4), user, 100_000_000 * 1e8); // 100m tokens

        MockRateProvider(address(rp)).setRate(address(token4), 0.001 ether);

        vm.prank(jake);
        rateRepo.addToken(address(token4), false, address(rp));

        AtomicQueue.AtomicRequest memory request = AtomicQueue.AtomicRequest({
            deadline: uint64(vm.getBlockTimestamp() + 1),
            atomicPrice: uint88(0),
            offerAmount: uint96(1e8), // 1 token
            inSolve: false,
            requestType: AtomicQueue.RequestType.Deposit // deposit
        });

        vm.prank(user);
        token4.approve(address(queue), type(uint256).max);

        uint256 discount = 1e6 / 100;

        uint256 safeMinPrice =
            FixedPointMathLib.mulDiv(rateRepo.getAssetPriceInVaultShare(address(token4)), 1e6 - discount, 1e6);

        vm.expectEmit(address(queue));
        emit AtomicQueue.AtomicRequestUpdated(
            user, // user address
            address(token4), // offer ERC20
            address(vault), // want ERC20
            uint96(1e8), // offer amount
            uint64(vm.getBlockTimestamp() + 1), // offer deadline
            safeMinPrice, // minimum price for want ERC20
            AtomicQueue.RequestType.Deposit, // deposit request type
            vm.getBlockTimestamp() // current block.timestamp()
        );

        // user creates deposit request
        vm.prank(user);
        queue.safeUpdateAtomicRequest(ERC20(address(token4)), ERC20(address(vault)), request, rateRepo, discount);
    }

    function test__SafeUpdateAtomicWithdrawRequest() public {
        vm.startPrank(jake);
        AtomicQueue queue = new AtomicQueue(jake);
        RateProviderRepository rateRepo = new RateProviderRepository(address(vault), address(pool), address(token0));
        vm.stopPrank();

        address user = makeAddr("userA");

        MockToken token4 = new MockToken("name4", "symbol4", 8);
        deal(address(token4), user, 100_000_000 * 1e8); // 100m tokens
        deal(address(vault), user, 1000e18); // 1000 vault shares

        MockRateProvider(address(rp)).setRate(address(token4), 0.001 ether);

        vm.prank(jake);
        rateRepo.addToken(address(token4), false, address(rp));

        AtomicQueue.AtomicRequest memory request = AtomicQueue.AtomicRequest({
            deadline: uint64(vm.getBlockTimestamp() + 1),
            atomicPrice: uint88(0),
            offerAmount: uint96(1000e18), // 1000 shares
            inSolve: false,
            requestType: AtomicQueue.RequestType.Withdraw // withdraw
        });

        vm.prank(user);
        vault.approve(address(queue), type(uint256).max);

        uint256 discount = 1e6 / 100;

        uint256 safeMinPrice =
            FixedPointMathLib.mulDiv(rateRepo.getVaultSharePriceInAsset(address(token4)), 1e6 - discount, 1e6);

        vm.expectEmit(address(queue));
        emit AtomicQueue.AtomicRequestUpdated(
            user, // user address
            address(vault), // offer ERC20
            address(token4), // want ERC20
            uint96(1000e18), // offer amount
            uint64(vm.getBlockTimestamp() + 1), // offer deadline
            safeMinPrice, // minimum price for want ERC20
            AtomicQueue.RequestType.Withdraw, // deposit request type
            vm.getBlockTimestamp() // current block.timestamp()
        );

        // user creates deposit request
        vm.prank(user);
        queue.safeUpdateAtomicRequest(ERC20(address(vault)), ERC20(address(token4)), request, rateRepo, discount);
    }
}
