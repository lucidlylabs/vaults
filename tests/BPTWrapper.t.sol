// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {BPTWrapper} from "../src/WrapperToken/BPTWrapper.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IBeetsGauge} from "../src/WrapperToken/interfaces/IBeetsGauge.sol";

// contract BPTWrapperTest is Test {
//     BPTWrapper public bptWrapper;

//     address public constant BPT = 0x944D4AE892dE4BFd38742Cc8295d6D5164c5593C; // bpt-anS-SiloWS
//     // address public constant BPT = 0x374641076B68371e69D03C417DAc3E5F236c32FA; // wS/stS BPT
//     address public constant GAUGE = 0x8476F3A8DA52092e7835167AFe27835dC171C133; // Beets Gauge - wS/stS

//     // BPT Whale
//     address public constant BPT_WHALE = 0x7c9597508Ea3a27D53600b180E23f4913a60Fd31;

//     // Test User
//     address public user = makeAddr("user");

//     function setUp() public {
//         vm.createSelectFork(vm.rpcUrl("https://rpc.ankr.com/sonic_mainnet"));

//         // Deploy BPTWrapper
//         bptWrapper = new BPTWrapper(
//             "Wrapped BPT",
//             "wBPT",
//             BPT,
//             GAUGE
//         );

//         // Transfer BPT from whale to user
//         vm.startPrank(BPT_WHALE);
//         uint256 userBalance = IERC20(BPT).balanceOf(BPT_WHALE);
//         IERC20(BPT).transfer(user, userBalance / 2); // Transfer 50% to user
//         vm.stopPrank();
//     }

//     // Test Deposit Functionality
//     function testDeposit() public {
//         vm.startPrank(user);
//         uint256 depositAmount = IERC20(BPT).balanceOf(user);
//         IERC20(BPT).approve(address(bptWrapper), depositAmount);
//         bptWrapper.deposit(depositAmount, user);
//         vm.stopPrank();

//         // Check shares minted
//         uint256 shares = bptWrapper.balanceOf(user);
//         assertGt(shares, 0, "No shares minted");

//         // Check BPT staked in gauge
//         uint256 gaugeBalance = IBeetsGauge(GAUGE).balanceOf(address(bptWrapper));
//         assertEq(gaugeBalance, depositAmount, "BPT not deposited into gauge");
//     }

//     // Test Compounding Rewards
//     function testCompoundRewards() public {
//         // Deposit initial BPT
//         testDeposit();

//         // Advance time by 7 days to accrue rewards
//         vm.warp(block.timestamp + 7 days);

//         // Compound rewards
//         vm.prank(user);
//         bptWrapper.compoundRewards();

//         // Check if BPT in gauge increased
//         uint256 newGaugeBalance = IBeetsGauge(GAUGE).balanceOf(address(bptWrapper));
//         uint256 initialBalance = IERC20(BPT).balanceOf(user);
//         assertGt(newGaugeBalance, initialBalance, "Rewards not compounded");
//     }

//     // Test Withdrawal
//     function testWithdraw() public {
//         // Deposit first
//         testDeposit();

//         // Withdraw all shares
//         vm.startPrank(user);
//         uint256 shares = bptWrapper.balanceOf(user);
//         bptWrapper.redeem(shares, user, user);
//         vm.stopPrank();

//         // Check shares burned
//         assertEq(bptWrapper.balanceOf(user), 0, "Shares not burned");

//         // Check BPT returned to user (may have increased due to rewards)
//         uint256 userBptBalance = IERC20(BPT).balanceOf(user);
//         assertGt(userBptBalance, 0, "No BPT returned");
//     }
// }
