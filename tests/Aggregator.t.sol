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
import {Aggregator} from "../src/Aggregator.sol";

contract AggregatorTest is Test {
    Pool pool;
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
        pool = new Pool(address(poolToken), amplification, tokens, rateProviders, weights, jake);

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

    function _calculateSeedAmounts(uint256 total) internal returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            address token = tokens[i];
            address rateProvider = rateProviders[i];

            vm.startPrank(alice);
            require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
            vm.stopPrank();

            uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of the asset scaled to 18 precision

            amounts[i] = FixedPointMathLib.divUp(
                FixedPointMathLib.mulDiv(total, weights[i], unadjustedRate), (10 ** (18 - ERC20(token).decimals()))
            );
        }
        return amounts;
    }

    function test__addLiquidity() public {
        PoolEstimator estimator = new PoolEstimator(address(pool));
        uint256 numTokens = pool.numTokens();

        uint256[] memory amounts1 = new uint256[](numTokens);
        uint256 total1 = 100 * 1e18;

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
        uint256 total1 = 100 * 1e18;
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

    function test__depositSingle() public {
        uint256 numTokens = pool.numTokens();
        uint256[] memory amounts = new uint256[](numTokens);
        uint256[] memory amountsEstimated = new uint256[](numTokens);
        uint256 total1 = 100 * 1e18;
        amounts = _calculateSeedAmounts(total1);
        amountsEstimated[0] = amounts[0];
        amounts[1] = 0;
        amounts[2] = 0;
        amountsEstimated[1] = 0;
        amountsEstimated[2] = 0;

        uint256 ss = vm.snapshotState();

        vm.startPrank(alice);
        uint256 lpTokens = pool.addLiquidity(amountsEstimated, 0, alice);
        poolToken.approve(address(vault), lpTokens);
        uint256 sharesEstimated = vault.deposit(lpTokens, alice);
        vm.stopPrank();

        vm.revertToState(ss);

        vm.startPrank(alice);
        require(ERC20(pool.tokens(0)).approve(address(agg), type(uint256).max), "could not approve");
        vm.stopPrank();

        uint256 sharesOfAlice = vault.balanceOf(alice);

        vm.startPrank(alice);
        uint256 shares = agg.depositSingle(0, amounts[0], alice, 0, address(pool));
        vm.stopPrank();

        assert(shares == (vault.balanceOf(alice) - sharesOfAlice));
        assert(sharesEstimated == shares);
    }

    // function test__ExecuteZapAndDeposit() public {
    //     vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));

    //     uint256[] memory amounts = new uint256[](4);
    //     bytes memory data =
    //         "73fc445700000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000254022500c0a13d4a67745d4ed129af590c495897ee2c7f8cfcc02aaa39b223fe8d0a0e5c4f27ead9083c756cc29d39a5de30e57443bff2a8307a4256c8797a3497e000d4b800d9f800e3c800e5551e60079a46ba41652f9d7cef6ee967c15b6bb0a71e65ccfbcffc5e4f08b22a26b46d74baa8decec41a0bdba7a8e921219f9399cbb2ae245016509c06a69c491b0000e0678fea99b803f84a2c247146d388f800c8b1a2bc2ec50000060300e4128acb08f80100000000000000000000000000000000000000000000000000000001000276a400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000014c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000100f0060300f40300e40400f60080c7bbec68d12a0d1830360f8ec58fa599ba1b0e9b00070a000000000000000000000000000000000000000000000000000000000000030199050020000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000014dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000000100f002004803008a0500400401c00080867b321132b18b5bf3775c0d9040d1872979422e03019905006002000000ec00f0000000004001760185018507002001ba01c000000000400240025102510700200265026b0000000000000000000000000000";
    //     address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     address MAGPIEROUTER = 0x15392211222B46A0eA85a9A800830486D144848D;

    //     agg = Aggregator(0xA13d4a67745D4Ed129AF590c495897eE2C7F8Cfc);

    //     pool = Pool(0xec970a39fc83A492103Ed707a290e050E2DA375c);
    //     vault = Vault(0xEf1BCC329081f04059b766F04C4A617AdF462934);

    //     vm.startPrank(alice);
    //     deal(WETH, alice, 1 ether);
    //     require(ERC20(WETH).approve(MAGPIEROUTER, type(uint256).max), "could not approve");
    //     (bool success, bytes memory response) = MAGPIEROUTER.call(data);
    //     require(success, "router call failed");
    //     uint256 amtReceived = ERC20(pool.tokens(0)).balanceOf(alice);
    //     amounts[0] = amtReceived;
    //     require(ERC20(pool.tokens(0)).approve(address(agg), type(uint256).max), "could not approve");
    //     vm.stopPrank();

    //     uint256 sharesOfAlice = vault.balanceOf(alice);

    //     vm.startPrank(alice);
    //     uint256 shares = agg.depositSingle(0, amounts[0], alice, 0, address(pool));
    //     vm.stopPrank();

    //     assert(shares == (vault.balanceOf(alice) - sharesOfAlice));
    // }

    function test__depositFor() public {
        uint256 numTokens = pool.numTokens();
        uint256[] memory amounts = new uint256[](numTokens);
        uint256 total1 = 100 * 1e18;
        amounts = _calculateSeedAmounts(total1);

        // approve agg as spender
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(ERC20(token).approve(address(agg), type(uint256).max), "could not approve");
            vm.stopPrank();
        }

        vm.startPrank(alice);
        require(ERC20(pool.tokens(0)).approve(address(agg), type(uint256).max), "could not approve");
        vm.stopPrank();
        uint256 sharesOfAlice = vault.balanceOf(alice);

        vm.startPrank(alice);
        uint256 shares = agg.depositFor(tokens, amounts, alice, 0, address(pool));
        vm.stopPrank();

        assert(shares == (vault.balanceOf(alice) - sharesOfAlice));
    }

    function test__depositForSingle() public {
        uint256 numTokens = pool.numTokens();
        uint256[] memory amounts = new uint256[](numTokens);
        uint256[] memory amountsEstimated = new uint256[](numTokens);
        uint256 total1 = 100 * 1e18;
        amounts = _calculateSeedAmounts(total1);
        amountsEstimated[0] = amounts[0];
        amounts[1] = 0;
        amounts[2] = 0;
        amountsEstimated[1] = 0;
        amountsEstimated[2] = 0;

        uint256 ss = vm.snapshotState();

        vm.startPrank(alice);
        uint256 lpTokens = pool.addLiquidityFor(amountsEstimated, 0, alice, alice);
        poolToken.approve(address(vault), lpTokens);
        uint256 sharesEstimated = vault.deposit(lpTokens, alice);
        vm.stopPrank();

        vm.revertToState(ss);

        // approve agg as spender
        for (uint256 i = 0; i < numTokens; i++) {
            address token = tokens[i];
            vm.startPrank(alice);
            require(ERC20(token).approve(address(agg), type(uint256).max), "could not approve");
            vm.stopPrank();
        }

        uint256 sharesOfAlice = vault.balanceOf(alice);

        vm.startPrank(alice);
        uint256 shares = agg.depositForSingle(0, amounts[0], alice, 0, address(pool));
        vm.stopPrank();

        assert(shares == (vault.balanceOf(alice) - sharesOfAlice));
        assert(sharesEstimated == shares);
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

    function test__MainnetDeposit() public {
        vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));

        address user = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

        address[] memory tokens0 = new address[](2);
        tokens0[0] = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
        tokens0[1] = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;

        uint256[] memory amounts0 = new uint256[](2);
        amounts0[0] = ERC20(tokens0[0]).balanceOf(user);
        amounts0[1] = ERC20(tokens0[1]).balanceOf(user);

        vm.startPrank(user);
        uint256 shares = Aggregator(0x8417bdEF7FE41743Cd26E591f1E4f0D19C00552f).deposit(
            tokens0, amounts0, user, 0, 0x033f4A109Fc11a11d3AFB92dCA0AB6C30BB3c722
        );
        vm.stopPrank();
    }
}
