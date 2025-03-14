// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {console} from "forge-std/console.sol";

import {IRateProvider} from "../IRateProvider.sol";
import {ISUSDe} from "../ISUSDe.sol";
import {ICurveStableSwapNG} from "../ICurveStableSwapNG.sol";
import {IPendleOracle} from "../IPendleOracle.sol";
import {FixedPointMathLib} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";

// tokens
// - 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497 - sUSDe
// - 0x167478921b907422f8e88b43c4af2b8bea278d3a - sDAI-sUSDe curve pool
// - 0x5dc1BF6f1e983C0b21EfB003c105133736fA0743 - FRAX-USDe curve pool
// - 0xF36a4BA50C603204c3FC6d2dA8b78A7b69CBC67d - USDe-DAI curve pool
// - 0xB451A36c8B6b2EAc77AD0737BA732818143A0E25  - USDE March 2025 Pendle LP token

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
        } else if (token == SDAISUSDE_CURVE) {
            uint256 price = _fetchCurveLpPrice(token, 1);
            return price * ISUSDe(SUSDE).previewRedeem(PRECISION) / PRECISION;
        } else if (token == FRAXUSDE_CURVE) {
            return _fetchCurveLpPrice(token, 1);
        } else if (token == USDEDAI_CURVE) {
            return _fetchCurveLpPrice(token, 0);
        } else if (token == USDE_LPT_PENDLE_MARCH2025) {
            return _fetchPendleLpPrice(token);
        } else {
            revert RateProvider__InvalidParam();
        }
    }

    /// @dev index is the coin index of usde or usde derivative in the pool
    function _fetchCurveLpPrice(address curvePoolAddress, uint256 index) internal view returns (uint256) {
        ICurveStableSwapNG pool = ICurveStableSwapNG(curvePoolAddress);
        uint256 virtualPrice = pool.get_virtual_price();
        if (index == 1) {
            uint256 price =
                virtualPrice * FixedPointMathLib.min(1, (pool.price_oracle(0) * PRECISION / pool.stored_rates()[1]));
            return price;
        } else {
            uint256 price =
                virtualPrice * FixedPointMathLib.min(1, pool.price_oracle(0) * PRECISION / pool.stored_rates()[0]);
            return price;
        }
    }

    function _fetchPendleLpPrice(address pendleMarketAddress) internal view returns (uint256) {
        uint256 price = IPendleOracle(PENDLE_ORACLE).getLpToAssetRate(pendleMarketAddress, 1800);
        return price;
    }
}
