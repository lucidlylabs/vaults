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

contract End2End is Test {
    PoolV2 pool;
    PoolToken poolToken;
    Vault vault;
    IRateProvider rateProvider;
    Aggregator agg;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    uint256 private decimals = 18;
    address public poolOwner;

    MockToken public token0 = new MockToken("name0", "symbol0", 18);
    MockToken public token1 = new MockToken("name1", "symbol1", 18);
    MockToken public token2 = new MockToken("name2", "symbol2", 18);

    address[] public tokens = new address[](3);
    uint256[] public weights = new uint256[](3);
    address[] rateProviders = new address[](3);

    uint256[] public seedAmounts = new uint256[](3);

    address jake = makeAddr("jake"); // pool and staking owner
    address alice = makeAddr("alice"); // first LP

    function setUp() public {
        rateProvider = IRateProvider(new MockRateProvider());
        agg = new Aggregator();

        MockRateProvider(address(rateProvider)).setRate(address(token0), 2 ether);
        MockRateProvider(address(rateProvider)).setRate(address(token1), 3 ether);
        MockRateProvider(address(rateProvider)).setRate(address(token2), 4 ether);

        // set tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);

        // set weights
        weights[0] = 40 * PRECISION / 100;
        weights[1] = 30 * PRECISION / 100;
        weights[2] = 30 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);
        rateProviders[2] = address(rateProvider);

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
        poolToken.setVaultAddress(address(vault));

        poolToken.setPerformanceFeeRecipient(jake);
        poolToken.setPerformanceFeeInBps(100);

        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3 bps
        vault.setProtocolFeeAddress(jake);
        vault.setDepositFeeInBps(100); // 100 bps
        vm.stopPrank();

        // mint tokens to first lp
        deal(address(token0), alice, 100_000_000 * 1e18);
        deal(address(token1), alice, 100_000_000 * 1e18);
        deal(address(token2), alice, 100_000_000 * 1e18);

        uint256 total = 10_000 * 1e18; // considering we seed 10000 WBTC worth of assets

        for (uint256 i = 0; i < 3; i++) {
            address token = tokens[i];
            address rateProvider0 = rateProviders[i];

            vm.startPrank(alice);

            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");

            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider0).rate(token);
            seedAmounts[i] = FixedPointMathLib.divUp(
                FixedPointMathLib.mulDiv(total, weights[i], unadjustedRate), (10 ** (18 - ERC20(token).decimals()))
            );
        }

        // seed pool
        vm.startPrank(alice);
        uint256 lpAmount = pool.addLiquidity(seedAmounts, 0 ether, alice);
        poolToken.approve(address(vault), lpAmount);
        uint256 shares = vault.deposit(lpAmount, alice);
        vault.transfer(address(vault), shares / 10);
        vm.stopPrank();
    }

    function test__end2endFlow() public {
        address bob = makeAddr("bob");
        deal(address(token0), bob, 100_000_000 * 1e18);
        deal(address(token1), bob, 100_000_000 * 1e18);
        deal(address(token2), bob, 100_000_000 * 1e18);

        uint256 tokenAmount = 1000 * 1e18;

        vm.startPrank(bob);

        require(ERC20(address(token0)).approve(address(agg), type(uint256).max), "could not approve");

        uint256 sharesBeforeDeposit = vault.balanceOf(bob);
        uint256 sharesReceived = agg.depositSingle(0, tokenAmount, bob, 0, address(pool));
        uint256 sharesAfterDeposit = vault.balanceOf(bob);

        // bob should have more shares after deposit
        assert(sharesAfterDeposit > sharesBeforeDeposit);

        // mismatch in shares received
        assert(sharesReceived == sharesAfterDeposit - sharesBeforeDeposit);

        uint256 sharesToRedeem = sharesAfterDeposit / 2;
        uint256 sharesBeforeRedeem = vault.balanceOf(bob);
        uint256 tokenBalanceBeforeRedeem = ERC20(address(token0)).balanceOf(bob);

        require(vault.approve(address(agg), type(uint256).max), "could not approve");

        uint256 tokenAmountReceived = agg.redeemSingle(address(pool), 0, sharesToRedeem, 0, bob);
        uint256 sharesAfterRedeem = vault.balanceOf(bob);
        uint256 tokenBalanceAfterRedeem = ERC20(address(token0)).balanceOf(bob);

        // shares should decrease after redeem
        assert(sharesAfterRedeem < sharesBeforeRedeem);

        // should have received some tokens
        assert(tokenAmountReceived > 0);

        // token balance should increase
        assert(tokenBalanceAfterRedeem > tokenBalanceBeforeRedeem);

        // token received mismatch
        assert(tokenBalanceAfterRedeem - tokenBalanceBeforeRedeem == tokenAmountReceived);

        vm.stopPrank();
    }
}
