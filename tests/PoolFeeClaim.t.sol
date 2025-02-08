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
import {FeeSplitter} from "../src/utils/FeeSplitter.sol";

contract PerfFee is Test {
    PoolV2 pool;
    PoolToken poolToken;
    Vault vault;
    IRateProvider rateProvider;
    Aggregator agg;
    FeeSplitter splitter;

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
    address bob = makeAddr("bob"); //second LP

    address thirdParty = makeAddr("thirdParty"); // third party with access to claim fees
    uint256 tokenIndex;

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
        splitter = new FeeSplitter(address(poolToken), jake, thirdParty);

        tokenIndex = 0;
        poolToken.setPool(address(pool));
        poolToken.setVaultAddress(address(vault));

        vault.setPerformanceFeeRecipient(address(splitter));
        vault.setPerformanceFeeInBps(100);

        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3 bps
        vault.setEntryFeeAddress(jake);
        vault.setEntryFeeInBps(100); // 100 bps

        splitter.setTokenIndex(tokenIndex);
        vm.stopPrank();

        // mint tokens to first lp
        deal(address(token0), alice, 100_000_000 * 1e18);
        deal(address(token1), alice, 100_000_000 * 1e18);
        deal(address(token2), alice, 100_000_000 * 1e18);

        uint256 total = 10_000_000 * 1e18; // considering we seed 10000 WBTC worth of assets

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


        deal(address(token0), bob, 100_000_000 * 1e18);
        uint256 tokenAmount = 1000 * 1e18;
        vm.startPrank(bob);
        require(ERC20(address(token0)).approve(address(agg), type(uint256).max), "could not approve");
        agg.depositSingle(0, tokenAmount, bob, 0, address(pool));
        vm.stopPrank();

    }

    function testClaimingFees() public{
        address recipient0 = splitter.recipient0();
        address recipient1 = splitter.recipient1();
        ERC20 token = ERC20(pool.tokens(tokenIndex));
        splitter.updateBalances();

        uint256 balanceBeforeClaim0 = token.balanceOf(recipient0);
        uint256 balanceBeforeClaim1 = token.balanceOf(recipient1);

        vm.prank(recipient0);
        splitter.claimRecipient0(address(pool), 0);
        uint256 balanceAfterClaim0 = token.balanceOf(recipient0);
        assertGt(balanceAfterClaim0, balanceBeforeClaim0, "Recipient0 did not receive any tokens");
        vm.stopPrank();

        vm.prank(recipient1);
        splitter.claimRecipient1(address(pool), 0);
        uint256 balanceAfterClaim1 = token.balanceOf(recipient1);
        assertGt(balanceAfterClaim1, balanceBeforeClaim1, "Recipient1 did not receive any tokens");
        vm.stopPrank();
        // assertEq(splitter.recipient0OwedAmount(), 0, "Recipient0 balance not reset");
        // assertEq(splitter.recipient1OwedAmount(), 0, "Recipient1 balance not reset");
    }

    function testSetTokenIndex() public {
        address owner = splitter.owner();
        uint256 index = 1;
        vm.prank(owner);
        splitter.setTokenIndex(index);
        assertEq(splitter.tokenIndex(), index, "Token index not set");
    }

    function testUpdateRecipients() public {
        address recipient0 = splitter.recipient0();
        address recipient1 = splitter.recipient1();
        address randomAddress = makeAddr("randomAddress");
        address newRecipient0 = address(0x789);
        address newRecipient1 = address(0x9ab);

        vm.expectRevert(bytes("Unauthorized"));
        vm.prank(randomAddress);
        splitter.updateRecipient0(newRecipient0);

        vm.prank(recipient0);
        splitter.updateRecipient0(newRecipient0);
        assertEq(splitter.recipient0(), newRecipient0, "Recipient0 address not updated");

        vm.prank(recipient1);
        splitter.updateRecipient1(newRecipient1);
        assertEq(splitter.recipient1(), newRecipient1, "Recipient1 address not updated");
    }
}
