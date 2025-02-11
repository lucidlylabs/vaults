// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {PendleLPWrapper} from "../src/WrapperToken/PendleLPWrapper.sol";
import {IPendleRouterV4} from "../src/WrapperToken/interfaces/IPendleRouterV4.sol";
import {IPendleMarket} from "../src/WrapperToken/interfaces/IPendleMarket.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// contract PendleLPWrapperTest is Test {
//     PendleLPWrapper public pendleLPWrapper;
//     IPendleRouterV4 public pendleRouter;
//     IPendleMarket public pendleMarket;
//     address public constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
//     address public constant PENDLE_MARKET = 0xD75FC2B1ca52e72163787D1C370650F952E75DD7;

//     // LP Whale
//     address public constant PENDLE_LP_WHALE = 0xea9d65eAf4083468dE90c594288C5948b3b2b9fb;
//     // Pendle Whale
//     address public constant PENDLE_WHALE = 0x78262c9680FF0b15484d78c413aA209620320848;

//     // Test User
//     address public user = makeAddr("user");

//     function setUp() public {
//         vm.createSelectFork(vm.rpcUrl("https://rpc.ankr.com/eth"));

//         // Deploy PendleLPWrapper
//         pendleLPWrapper = new PendleLPWrapper(
//             "Wrapped Pendle LP",
//             "wPendle LP",
//             PENDLE_MARKET
//         );

//         // Transfer Pendle from whale to user
//         vm.startPrank(PENDLE_LP_WHALE);
//         uint256 userBalance = IERC20(PENDLE_MARKET).balanceOf(PENDLE_LP_WHALE);
//         IERC20(PENDLE_MARKET).transfer(user, userBalance / 2); // Transfer 50% to user
//         vm.stopPrank();
//     }

//     function testCompoundRewards() public {
//         vm.startPrank(user);
//         uint256 userBalance = IERC20(PENDLE_MARKET).balanceOf(user);
//         IERC20(PENDLE_MARKET).transfer(address(pendleLPWrapper), userBalance); // Transfer 50% to user
        
//         vm.warp(block.timestamp + 7 days);

//         // vm.startPrank(PENDLE_WHALE);
//         // uint256 whaleBalance = IERC20(PENDLE).balanceOf(PENDLE_WHALE);
//         // IERC20(PENDLE).transfer(address(pendleLPWrapper), whaleBalance);
        
//         pendleLPWrapper.compoundRewards();
//         vm.stopPrank();
//     }
// }
