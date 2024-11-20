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

import {ManualRegistry} from "../src/ManualRegistry.sol";
import {Aggregator} from "../src/Aggregator.sol";

contract ManualRegistryTest is Test {
    Pool pool0;
    PoolToken poolToken0;
    Vault vault0;

    Pool pool1;
    PoolToken poolToken1;
    Vault vault1;
    IRateProvider rp;
    Aggregator agg;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    uint256 private decimals0 = 8;
    address public poolOwner;

    // pool0 tokens
    MockToken public token0 = new MockToken("name0", "symbol0", 8);
    MockToken public token1 = new MockToken("name1", "symbol1", 18);
    MockToken public token2 = new MockToken("name2", "symbol2", 6);

    // pool1 tokens
    MockToken public token3 = new MockToken("name3", "symbol3", 12);
    MockToken public token4 = new MockToken("name4", "symbol4", 10);
    MockToken public token5 = new MockToken("name5", "symbol5", 8);
    MockToken public token6 = new MockToken("name6", "symbol6", 16);

    address[] public tokens0 = new address[](3);
    uint256[] public weights0 = new uint256[](3);
    address[] rateProviders0 = new address[](3);

    address[] public tokens1 = new address[](4);
    uint256[] public weights1 = new uint256[](4);
    address[] rateProviders1 = new address[](4);

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

        MockRateProvider(address(rp)).setRate(address(token3), 4 ether);
        MockRateProvider(address(rp)).setRate(address(token4), 1 ether);
        MockRateProvider(address(rp)).setRate(address(token5), 5 ether);
        MockRateProvider(address(rp)).setRate(address(token6), 2 ether);

        /////////////////////
        //   deploy pool0
        /////////////////////

        // set tokens
        tokens0[0] = address(token0);
        tokens0[1] = address(token1);
        tokens0[2] = address(token2);

        // set weights
        weights0[0] = 40 * PRECISION / 100;
        weights0[1] = 30 * PRECISION / 100;
        weights0[2] = 30 * PRECISION / 100;

        // set rateProviders
        rateProviders0[0] = address(rp);
        rateProviders0[1] = address(rp);
        rateProviders0[2] = address(rp);

        // amplification = calculateWProd(weights);
        amplification = 500 * 1e18;

        // deploy pool token
        poolToken0 = new PoolToken("XYZ Pool Token", "lXYZ", 18, jake);

        // deploy pool
        pool0 = new Pool(address(poolToken0), amplification, tokens0, rateProviders0, weights0, jake);

        // deploy staking contract
        vault0 = new Vault(address(poolToken0), "XYZ Vault Share", "XYZVS", 100, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken0.setPool(address(pool0));
        pool0.setStaking(address(vault0));
        pool0.setSwapFeeRate(3 * PRECISION / 10_000); // 3 bps
        vault0.setProtocolFeeAddress(jake);
        vault0.setDepositFeeInBps(100); // 100 bps
        vm.stopPrank();

        // mint tokens to first lp
        deal(address(token0), alice, 100_000_000 * 1e8); // 100,000,000 SWBTCWBTC_CURVE
        deal(address(token1), alice, 100_000_000 * 1e18); // 100,000,000 SWBTC
        deal(address(token2), alice, 100_000_000 * 1e6); // 100,000,000 USDC

        uint256 total = 10_000 * 1e8; // considering we seed 10000 WBTC worth of assets

        for (uint256 i = 0; i < 3; i++) {
            address token = tokens0[i];
            address rateProvider = rateProviders0[i];

            vm.startPrank(alice);
            require(ERC20(token).approve(address(pool0), type(uint256).max), "could not approve");
            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of an asset in WBTC, scaled to 18 precision
            uint256 amount =
                (total * weights0[i] * 1e18 * 1e10) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));

            seedAmounts[i] = amount;
        }

        // seed pool
        vm.startPrank(alice);

        uint256 lpAmount0 = pool0.addLiquidity(seedAmounts, 0 ether, alice);
        poolToken0.approve(address(vault0), lpAmount0);
        uint256 shares0 = vault0.deposit(lpAmount0, alice);
        vault0.transfer(address(vault0), shares0 / 10);
        vm.stopPrank();

        /////////////////////
        //   deploy pool1
        /////////////////////

        // set tokens
        tokens1[0] = address(token3);
        tokens1[1] = address(token4);
        tokens1[2] = address(token5);
        tokens1[3] = address(token6);

        // set weights
        weights1[0] = 10 * PRECISION / 100;
        weights1[1] = 30 * PRECISION / 100;
        weights1[2] = 30 * PRECISION / 100;
        weights1[3] = 30 * PRECISION / 100;

        // set rateProviders
        rateProviders1[0] = address(rp);
        rateProviders1[1] = address(rp);
        rateProviders1[2] = address(rp);
        rateProviders1[3] = address(rp);

        // amplification = calculateWProd(weights);
        amplification = 500 * 1e18;

        // deploy pool token
        poolToken1 = new PoolToken("XYZ Pool Token", "lXYZ", 18, jake);

        // deploy pool
        pool1 = new Pool(address(poolToken1), amplification, tokens1, rateProviders1, weights1, jake);

        // deploy staking contract
        vault1 = new Vault(address(poolToken1), "XYZ Vault Share", "XYZVS", 100, jake, jake);

        // set staking on pool
        vm.startPrank(jake);
        poolToken1.setPool(address(pool1));
        pool1.setStaking(address(vault1));
        pool1.setSwapFeeRate(3 * PRECISION / 10_000); // 3 bps
        vault1.setProtocolFeeAddress(jake);
        vault1.setDepositFeeInBps(100); // 100 bps
        vm.stopPrank();

        // mint tokens to first lp
        deal(address(token3), alice, 100_000_000 * 1e12); // 100,000,000 SWBTCWBTC_CURVE
        deal(address(token4), alice, 100_000_000 * 1e10); // 100,000,000 SWBTC
        deal(address(token5), alice, 100_000_000 * 1e8); // 100,000,000 USDC
        deal(address(token6), alice, 100_000_000 * 1e16); // 100,000,000 USDC

        uint256 total0 = 10_000 * 1e8; // considering we seed 10000 WBTC worth of assets

        uint256[] memory seedAmounts1 = new uint256[](4);

        for (uint256 i = 0; i < 4; i++) {
            address token = tokens1[i];
            address rateProvider = rateProviders1[i];

            vm.startPrank(alice);

            require(ERC20(token).approve(address(pool1), type(uint256).max), "could not approve");

            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of an asset in WBTC, scaled to 18 precision
            uint256 amount =
                (total0 * weights1[i] * 1e18 * 1e10) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));

            seedAmounts1[i] = amount;
        }

        // seed pool
        vm.startPrank(alice);
        uint256 lpAmount = pool1.addLiquidity(seedAmounts1, 0 ether, alice);
        poolToken1.approve(address(vault1), lpAmount);
        uint256 shares = vault1.deposit(lpAmount, alice);
        vault1.transfer(address(vault1), shares / 10);
        vm.stopPrank();
    }

    // function _calculateSeedAmounts(uint256 total) internal returns (uint256[] memory) {
    //     uint256[] memory amounts = new uint256[](3);
    //     for (uint256 i = 0; i < 3; i++) {
    //         address token = tokens[i];
    //         address rateProvider = rateProviders[i];

    //         vm.startPrank(alice);
    //         require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
    //         vm.stopPrank();

    //         uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of the asset scaled to 18 precision
    //         uint256 amount =
    //             (total * weights[i] * 1e18 * 1e10) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));
    //         amounts[i] = amount;
    //     }
    //     return amounts;
    // }

    // function test__addPoolAddress() {}

    function test__addPoolAddress() public {
        vm.startPrank(jake);
        ManualRegistry res = new ManualRegistry();
        vm.stopPrank();

        vm.startPrank(jake);
        res.addPoolAddress(address(pool0), "BTC", "v1");

        res.getPoolAddresses();
        res.numPools();

        res.addPoolAddress(address(pool1), "BTC", "v1");
        vm.stopPrank();

        res.getPoolAddresses();
        res.numPools();
    }
}
