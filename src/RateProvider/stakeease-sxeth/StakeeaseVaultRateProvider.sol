// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {console} from "forge-std/console.sol";

import {IRateProvider} from "../IRateProvider.sol";
import {IWsxEth} from "../IWsxEth.sol";
import {ICurveStableSwapNG} from "../ICurveStableSwapNG.sol";
import {FixedPointMathLib} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";

// tokens
// 0x082F581C1105b4aaf2752D6eE5410984bd66Dd21 - wsxEth
// 0x8b0fb150FbA4fc25cd4f6F5bd8a8F6944ad65Af0 - sxETH-WETH curve pool

contract StakeeaseVaultRateProvider is IRateProvider {
    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;
    address private constant WSXETH = 0x082F581C1105b4aaf2752D6eE5410984bd66Dd21;
    address private constant SXETHWETH_CURVE = 0x8b0fb150FbA4fc25cd4f6F5bd8a8F6944ad65Af0;

    function rate(address token) external view returns (uint256) {
        if (token == WSXETH) {
            return IWsxEth(token).convertToAssets(PRECISION);
        } else if (token == SXETHWETH_CURVE) {
            return _fetchCurveLpPrice(token, 0);
        } else {
            revert RateProvider__InvalidParam();
        }
    }

    /// @dev index is the coin index of sxeth or sxeth derivative in the pool
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
}
