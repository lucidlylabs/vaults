// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {PoolV2} from "../../src/Poolv2.sol";
import {PoolToken} from "../../src/PoolToken.sol";
import {Vault} from "../../src/Vault.sol";
import {MockToken} from "../../src/Mocks/MockToken.sol";
import {MockRateProvider} from "../../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "../PoolEstimator.sol";
import {LogExpMath} from "../../src/BalancerLibCode/LogExpMath.sol";
import {WeirollPlanner} from "../utils/WeirollPlanner.sol";

// contract PoolTest is Test {
//     Pool pool;
//     PoolToken poolToken;
//     Vault staking;
//     MockRateProvider mrp;
//
//     uint256 public constant PRECISION = 1e18;
//     uint256 public constant MAX_NUM_TOKENS = 32;
//     uint256 public amplification;
//
//     address public poolOwner;
//
//     address jake = makeAddr("jake"); // pool and staking owner
//     address alice = makeAddr("alice"); // first LP
//     address bob = makeAddr("bob"); // second LP
//
//     // Token addresses
//     ERC20 public SDAI = ERC20(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
//     ERC20 public SUSDE = ERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
//     ERC20 public SDAISUSDE_CURVE = ERC20(0x167478921b907422F8E88B43C4Af2B8BEa278d3A);
//     ERC20 public YPTSUSDE = ERC20(0x57fC2D9809F777Cd5c8C433442264B6E8bE7Fce4);
//     ERC20 public GAUNTLET_USDC_PRIME = ERC20(0xdd0f28e19C1780eb6396170735D45153D261490d);
//
//     function setUp() public {}
//
//     function testRemoveToken() public {
//         vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));
//
//         uint256 INITIAL_AMOUNT = 1000e18; // 1000 tokens
//         deal(address(SUSDE), jake, INITIAL_AMOUNT);
//         deal(address(SDAISUSDE_CURVE), jake, INITIAL_AMOUNT);
//         deal(address(YPTSUSDE), jake, INITIAL_AMOUNT);
//         deal(address(GAUNTLET_USDC_PRIME), jake, INITIAL_AMOUNT);
//
//         uint256 n = 4;
//         uint256[] memory weights1 = new uint256[](n);
//
//         // Equal weights for all tokens
//         for (uint256 i = 0; i < n; i++) {
//             weights1[i] = PRECISION / n;
//         }
//
//         address[] memory tokens0 = new address[](n);
//         address[] memory mockRateProviders = new address[](n);
//
//         // Set up tokens array
//         tokens0[0] = address(SUSDE);
//         tokens0[1] = address(SDAISUSDE_CURVE);
//         tokens0[2] = address(YPTSUSDE);
//         tokens0[3] = address(GAUNTLET_USDC_PRIME);
//
//         // Set up rate providers
//         MockRateProvider mrp0 = new MockRateProvider();
//         for (uint256 i = 0; i < n; i++) {
//             mrp0.setRate(tokens0[i], PRECISION);
//             mockRateProviders[i] = address(mrp0);
//         }
//
//         // Deploy pool
//         vm.startPrank(jake);
//         PoolToken poolToken1 = new PoolToken("PoolToken1", "XYZ-PT1", 18, jake);
//         Pool pool1 =
//             new Pool(address(poolToken1), calculateWProd(weights1) * 10, tokens0, mockRateProviders, weights1, jake);
//         poolToken1.setPool(address(pool1));
//
//         uint256[] memory amounts = new uint256[](4);
//         amounts[0] = INITIAL_AMOUNT;
//         amounts[1] = INITIAL_AMOUNT;
//         amounts[2] = INITIAL_AMOUNT;
//         amounts[3] = INITIAL_AMOUNT;
//
//         SUSDE.approve(address(pool1), INITIAL_AMOUNT);
//         SDAISUSDE_CURVE.approve(address(pool1), INITIAL_AMOUNT);
//         YPTSUSDE.approve(address(pool1), INITIAL_AMOUNT);
//         GAUNTLET_USDC_PRIME.approve(address(pool1), INITIAL_AMOUNT);
//
//         pool1.addLiquidity(amounts, 0, address(this));
//
//         // Store initial balances
//         uint256 initialCurveLPBalance = SDAISUSDE_CURVE.balanceOf(address(pool1));
//
//         // Remove sUSDe (index 0)
//         uint256 poolSusdeBalance = SUSDE.balanceOf(address(pool1));
//
//         // Approve Curve pool to spend sUSDe
//         bytes32 command1 = WeirollPlanner.buildCommand(
//             ERC20.approve.selector,
//             0x00,
//             bytes6(0x0001ffffffff),
//             bytes1(0x02),
//             address(SUSDE)
//         );
//
//         // Add liquidity to Curve pool - [sDAI, sUSDe]
//         uint256[] memory amounts = new uint256[](2);
//         amounts[1] = balance; // sUSDe amount
//
//         bytes32 command2 = WeirollPlanner.buildCommand(
//             bytes4(keccak256("add_liquidity(uint256[],uint256)")),
//             0x00,
//             bytes6(0x8204ffffffff),
//             bytes1(0x02),
//             address(SDAISUSDE_CURVE)
//         );
//
//         bytes32[] memory commands = new bytes32[](1);
//         commands[0] = command1;
//         commands[1] = command2;
//
//         bytes[] memory state = new bytes[](2);
//         state[0] = abi.encode(
//             uint256(5),
//             address(SDAISUSDE_CURVE),
//             poolSusdeBalance,
//             uint256(amounts[0]),
//             uint256(amounts[1]),
//             uint256(min_mint_amount)
//         );
//
//         pool1.removeToken(0, commands, state);
//
//         vm.stopPrank();
//
//         // Verify pool state after removal
//         assertEq(pool1.numTokens(), 3);
//
//         // Verify weights are redistributed equally
//         for (uint256 i = 0; i < 3; i++) {
//             (uint256 weight,,,) = pool1.weight(i);
//             console.log(weight);
//             // assertEq(weight, PRECISION / 3);
//         }
//
//         // Verify sUSDe was added to Curve pool
//         uint256 finalCurveLPBalance = SDAISUSDE_CURVE.balanceOf(address(pool1));
//         assert(finalCurveLPBalance > initialCurveLPBalance);
//
//         // Verify sUSDe balance is 0
//         assertEq(SUSDE.balanceOf(address(pool1)), 0);
//     }
//
//     function testAddLiquidityToCurve() public {
//         vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));
//
//         uint256 INITIAL_AMOUNT = 1000e18; // 1000 tokens
//         deal(address(SDAI), jake, INITIAL_AMOUNT);
//         deal(address(SUSDE), jake, INITIAL_AMOUNT);
//         deal(address(SDAISUSDE_CURVE), jake, INITIAL_AMOUNT);
//         deal(address(YPTSUSDE), jake, INITIAL_AMOUNT);
//         deal(address(GAUNTLET_USDC_PRIME), jake, INITIAL_AMOUNT);
//
//         uint256[] memory amounts = new uint256[](2);
//         amounts[0] = 500e18;
//         amounts[1] = 500e18;
//
//         vm.startPrank(jake);
//         SDAI.approve(address(SDAISUSDE_CURVE), amounts[0]);
//         SUSDE.approve(address(SDAISUSDE_CURVE), amounts[0]);
//         address curvePool = address(SDAISUSDE_CURVE);
//         (bool success, bytes memory data) =
//             curvePool.call(abi.encodeWithSelector(bytes4(keccak256("add_liquidity(uint256[],uint256)")), amounts, 0));
//         require(success, "could not add liquidity to curve");
//         uint256 lpMinted = abi.decode(data, (uint256));
//         vm.stopPrank();
//     }
//
//     function calculateWProd(uint256[] memory _weights) public pure returns (uint256) {
//         uint256 prod = uint256(PRECISION);
//         uint256 n = _weights.length;
//         for (uint256 i = 0; i < n; i++) {
//             uint256 w = _weights[i];
//             // prod = prod / (w / PRECISION) ^ (w * n / PRECISION)
//             prod = prod * PRECISION / LogExpMath.pow((w * PRECISION / PRECISION), (w * n * PRECISION) / PRECISION);
//         }
//
//         return prod;
//     }
// }
