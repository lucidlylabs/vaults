// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {ERC4626} from "../lib/solady/src/tokens/ERC4626.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {SwBtcRateProvider} from "../src/RateProvider/swell-btc/SwBTCRateProvider.sol";
import {ISWBTC} from "../src/RateProvider/swell-btc/ISWBTC.sol";
import {ICurveStableSwapNG} from "../src/RateProvider/ICurveStableSwapNG.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";

contract PoolAdd is Test {
    Pool pool;
    PoolToken poolToken;
    Vault vault;
    IRateProvider rp;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    uint256 private decimals = 18;
    address public poolOwner;

    address private ADMIN_ADDRESS = 0x49b3cF9E95566FC769eA22Bc7633906878794c86;
    // 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;
    address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
    address private constant YPTSUSDE = 0x57fC2D9809F777Cd5c8C433442264B6E8bE7Fce4;
    address private constant GAUNTLET_USDC_PRIME = 0xdd0f28e19C1780eb6396170735D45153D261490d;

    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;

    MockToken public token0 = MockToken(SUSDE);
    MockToken public token1 = MockToken(SDAISUSDE_CURVE);
    MockToken public token2 = MockToken(YPTSUSDE);
    MockToken public token3 = MockToken(GAUNTLET_USDC_PRIME);

    address[] public tokens = new address[](4);
    uint256[] public weights = new uint256[](4);
    address[] rateProviders = new address[](4);

    uint256[] public seedAmounts = new uint256[](4);

    address alice = makeAddr("alice"); // first LP
    address bob = makeAddr("bob"); // second LP

    // function setUp() public {
    //     vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));
    //     poolToken = PoolToken(0x37da1F0AADe11970F6c9B770a05D65D880ba36d3);
    //     pool = Pool(0xec970a39fc83A492103Ed707a290e050E2DA375c);
    //     vault = Vault(0xEf1BCC329081f04059b766F04C4A617AdF462934);
    //     rp = IRateProvider(0x2F6ac41126575B74eD71e7d0F299b9dEDd9D2287);
    // }

    // function test__seedPoolAndSetUpVault() public {
    //     deal(DAI, ADMIN_ADDRESS, 50_000_000e18);
    //     deal(USDE, ADMIN_ADDRESS, 50_000_000e18);
    //     deal(USDC, ADMIN_ADDRESS, 50_000_000e6);

    //     seedAmounts = _calculateSeedAmounts(50_000e18);

    //     vm.startPrank(ADMIN_ADDRESS);
    //     uint256 poolTokensMinted = pool.addLiquidity(seedAmounts1, 49_000e18, ADMIN_ADDRESS);
    //     poolToken.approve(address(vault), type(uint256).max);
    //     uint256 vaultSharesMinted = vault.deposit(poolTokensMinted, ADMIN_ADDRESS);
    //     vm.stopPrank();
    // }

    // function _mintMorphoShares(uint256 mintAmounts) internal returns (uint256) {
    //     vm.startPrank(ADMIN_ADDRESS);

    //     // approve Morpho Vault to spend USDC
    //     (bool success, bytes memory data) = USDC.call(
    //         abi.encodeWithSelector(
    //             bytes4(keccak256("approve(address,uint256)")), GAUNTLET_USDC_PRIME, type(uint256).max
    //         )
    //     );
    //     require(success, "could not approve Morpho Vault contract to spend USDC.");
    //     uint256 usdcDeposited = ERC4626(GAUNTLET_USDC_PRIME).mint(mintAmounts, ADMIN_ADDRESS);
    //     console.log("usdcDeposited:", usdcDeposited);
    //     vm.stopPrank();
    // }

    // function _mintYptsusde(uint256 mintAmount) internal returns (uint256 sharesMinted) {
    //     vm.startPrank(ADMIN_ADDRESS);

    //     // approve sUSDe to spend USDe
    //     (bool success, bytes memory data) =
    //         USDE.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), SUSDE, type(uint256).max));
    //     require(success, "could not approve sUSDe contract to spend USDe.");

    //     uint256 susdeAmount = ERC4626(YPTSUSDE).previewMint(mintAmount);
    //     uint256 usdeAmount = ERC4626(SUSDE).previewMint(susdeAmount);

    //     // deposit USDE into SUSDE
    //     (success, data) =
    //         SUSDE.call(abi.encodeWithSelector(bytes4(keccak256("deposit(uint256,address)")), usdeAmount, ADMIN_ADDRESS));
    //     require(success, "could not deposit USDe into sUSDe contract.");
    //     uint256 susdeBalance = abi.decode(data, (uint256));
    //     (success, data) = SUSDE.call(
    //         abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), YPTSUSDE, type(uint256).max)
    //     );
    //     uint256 susdeDeposited = ERC4626(YPTSUSDE).mint(mintAmount, ADMIN_ADDRESS);
    //     console.log("susde deposited:", susdeDeposited);
    //     vm.stopPrank();
    // }

    // function _addLiquidityToCurve(uint256 usdeAmount) internal returns (uint256 lpMinted) {
    //     vm.startPrank(ADMIN_ADDRESS);

    //     (bool success, bytes memory data) =
    //         USDE.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), SUSDE, type(uint256).max));
    //     require(success, "could not approve sUSDe contract to spend USDe.");

    //     // deposit USDE into SUSDE
    //     (success, data) =
    //         SUSDE.call(abi.encodeWithSelector(bytes4(keccak256("deposit(uint256,address)")), usdeAmount, ADMIN_ADDRESS));
    //     require(success, "could not deposit USDe into sUSDe contract.");
    //     uint256 susdeBalance = abi.decode(data, (uint256));
    //     uint256[] memory lpAmount = new uint256[](2);
    //     lpAmount[1] = susdeBalance;
    //     (success, data) = SUSDE.call(
    //         abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), SDAISUSDE_CURVE, type(uint256).max)
    //     );
    //     require(success, "could not approve SDAISUSDE_CURVE contract to spend sUSDe.");

    //     // add liquidity to curve pool
    //     (success, data) = SDAISUSDE_CURVE.call(
    //         abi.encodeWithSelector(
    //             bytes4(keccak256("add_liquidity(uint256[],uint256,address)")), lpAmount, 0, ADMIN_ADDRESS
    //         )
    //     );

    //     console.log("susde added:", susdeBalance);

    //     lpMinted = abi.decode(data, (uint256));
    //     vm.stopPrank();
    // }

    // function _mintSusde(uint256 mintAmount) internal {
    //     vm.startPrank(ADMIN_ADDRESS);
    //     require(ERC20(USDE).approve(SUSDE, type(uint256).max));
    //     uint256 usdeDeposited = ERC4626(SUSDE).mint(mintAmount, ADMIN_ADDRESS);
    //     console.log("USDE deposited:", usdeDeposited);
    //     vm.stopPrank();
    // }

    // /// @param totalAmount total amount of lp tokens to be minted by seeding the pool
    // function _calculateSeedAmounts(uint256 totalAmount) internal returns (uint256[] memory) {
    //     uint256 n = pool.numTokens();
    //     uint256[] memory amounts = new uint256[](n);
    //     for (uint256 i = 0; i < n; i++) {
    //         address token = pool.tokens(i);
    //         address rateProvider = pool.rateProviders(i);
    //         (uint256 weight,,,) = pool.weight(i);

    //         // vm.startPrank(ADMIN_ADDRESS);
    //         // require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");
    //         // vm.stopPrank();
    //         uint256 unadjustedRate = IRateProvider(rateProvider).rate(token);
    //         // amount = (total * weight) / rate
    //         amounts[i] = FixedPointMathLib.divUp(
    //             FixedPointMathLib.mulDiv(totalAmount, weight, unadjustedRate), (10 ** (18 - ERC20(token).decimals()))
    //         );
    //     }
    //     return amounts;
    // }

    // function setUp() public {
    //     vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));

    //     rp = new SwBtcRateProvider();

    //     // set tokens
    //     tokens[0] = address(token0);
    //     tokens[1] = address(token1);
    //     tokens[2] = address(token2);

    //     // set weights
    //     weights[0] = 40 * PRECISION / 100;
    //     weights[1] = 30 * PRECISION / 100;
    //     weights[2] = 30 * PRECISION / 100;

    //     // set rateProviders
    //     rateProviders[0] = address(rp);
    //     rateProviders[1] = address(rp);
    //     rateProviders[2] = address(rp);

    //     // amplification = calculateWProd(weights);
    //     amplification = 500 * 1e18;

    //     // deploy pool token
    //     poolToken = new PoolToken("XYZ Pool Token", "lXYZ", 18, jake);

    //     // deploy pool
    //     pool = new Pool(address(poolToken), 10 * 1e18, tokens, rateProviders, weights, jake);

    //     // deploy staking contract
    //     staking = new Vault(address(poolToken), "XYZ Vault Token", "XYZ-VS", 200, jake, jake);

    //     // set staking on pool
    //     vm.startPrank(jake);
    //     poolToken.setPool(address(pool));
    //     pool.setVaultAddress(address(staking));
    //     vm.stopPrank();

    //     // mint tokens to first lp
    //     deal(address(token0), alice, 100_000_000 * 1e18); // 100,000,000 SWBTCWBTC_CURVE
    //     deal(address(token1), alice, 100_000_000 * 1e8); // 100,000,000 SWBTC
    //     deal(address(token2), alice, 100_000_000 * 1e18); // 100,000,000 GAUNTLET_WBTC_CORE

    //     uint256 total = 10_000 * 1e8; // considering we seed 10000 WBTC worth of assets

    //     for (uint256 i = 0; i < 3; i++) {
    //         address token = tokens[i];
    //         address rateProvider = rateProviders[i];

    //         vm.startPrank(alice);

    //         require(ERC20(token).approve(address(pool), type(uint256).max), "could not approve");

    //         vm.stopPrank();

    //         uint256 unadjustedRate = IRateProvider(rateProvider).rate(token); // price of an asset in WBTC, scaled to 18 precision
    //         uint256 amount =
    //             (total * weights[i] * 1e18 * 1e10) / (unadjustedRate * (10 ** (36 - ERC20(token).decimals())));

    //         seedAmounts[i] = amount;

    //         console.log("amount of token", i, "to be seeded:", amount);
    //     }
    // }

    // function testAddLiquidityInitial() public {
    //     uint256 total = 10_000 * 1e18; // 10000 WBTC worth of assets

    //     vm.startPrank(alice);

    //     {
    //         vm.expectRevert(bytes4(keccak256(bytes("Pool__SlippageLimitExceeded()"))));
    //         pool.addLiquidity(seedAmounts, 11_000 * 1e18, alice);
    //     }

    //     uint256 lpAmount = pool.addLiquidity(seedAmounts, 0 ether, alice);
    //     vm.stopPrank();

    //     uint256 lpBalanceOfAlice = poolToken.balanceOf(alice);

    //     require(lpAmount == lpBalanceOfAlice, "amounts do not match");

    //     // precision
    //     if (lpBalanceOfAlice > total) {
    //         assert((lpBalanceOfAlice - total) * 1e16 / total < 2);
    //     } else {
    //         assert((total - lpBalanceOfAlice) * 1e16 / total < 2);
    //     }
    //     assert(poolToken.totalSupply() == lpBalanceOfAlice);
    //     assert(pool.supply() == lpBalanceOfAlice);
    //     (, uint256 sumTerm) = pool.virtualBalanceProdSum();

    //     // rounding
    //     if (sumTerm > total) {
    //         assert((sumTerm - total) <= 4);
    //     } else {
    //         assert((total - sumTerm) <= 4);
    //     }
    // }
}
