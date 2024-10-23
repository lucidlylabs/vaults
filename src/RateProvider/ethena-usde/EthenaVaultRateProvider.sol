// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {IRateProvider} from "../IRateProvider.sol";
import {ISUSDe} from "../ISUSDe.sol";
import {ICurveStableSwapNG} from "../ICurveStableSwapNG.sol";
import {IPendleOracle} from "../IPendleOracle.sol";
import {FixedPointMathLib} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";

// tokens
// - 0x9d39a5de30e57443bff2a8307a4256c8797a3497 - sUSDe
// - 0x167478921b907422f8e88b43c4af2b8bea278d3a - sDAI-sUSDe curve pool
// - 0x5dc1bf6f1e983c0b21efb003c105133736fa0743 - FRAX-USDe curve pool
// - 0xf36a4ba50c603204c3fc6d2da8b78a7b69cbc67d - USDe-DAI curve pool
// - 0xb451a36c8b6b2eac77ad0737ba732818143a0e25 - USDE March 2025 Pendle LP token

contract UsdeVaultRateProvider is IRateProvider {
    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;
    address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
    address private constant FRAXUSDE_CURVE = 0x5dc1BF6f1e983C0b21EfB003c105133736fA0743;
    address private constant USDEDAI_CURVE = 0xF36a4BA50C603204c3FC6d2dA8b78A7b69CBC67d;
    address private constant USDE_LPT_PENDLE_MARCH2025 = 0xB451A36c8B6b2EAc77AD0737BA732818143A0E25;
    address private constant PENDLE_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;

    function rate(address token) external view returns (uint256) {
        if (token == SUSDE) {
            return ISUSDe(token).previewRedeem(PRECISION);
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
