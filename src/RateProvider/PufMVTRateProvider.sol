// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPufEth} from "./IPufEth.sol";
import {IStEth} from "./IStEth.sol";
import {ICurveStableSwapNG} from "./ICurveStableSwapNG.sol";
import {IRateProvider} from "./IRateProvider.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract PufMVTRateProvider is IRateProvider {
    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;

    address private constant PUFETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    address private constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address private constant PUFETH_WSTETH_CURVE = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
    address private constant WETH_PUFETH_CURVE = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;

    function rate(address token_) external view returns (uint256) {
        if (token_ == PUFETH) {
            return IPufEth(PUFETH).previewRedeem(1e18);
        } else if (token_ == PUFETH_WSTETH_CURVE) {
            return _curveLpTokenClFeed(token_);
        } else if (token_ == WETH_PUFETH_CURVE) {
            return _curveLpTokenClFeed(token_);
        } else {
            revert RateProvider__InvalidParam();
        }
    }

    function _curveLpTokenClFeed(address token_) internal view returns (uint256) {
        if (token_ == PUFETH_WSTETH_CURVE) {
            uint256 virtualPrice = ICurveStableSwapNG(PUFETH_WSTETH_CURVE).get_virtual_price();
            uint256 wstEthClFeed = IStEth(STETH).getPooledEthByShares(PRECISION);
            uint256 pufEthClFeed = IPufEth(PUFETH).previewRedeem(PRECISION);
            return virtualPrice * FixedPointMathLib.min(wstEthClFeed, pufEthClFeed) / PRECISION;
        } else if (token_ == WETH_PUFETH_CURVE) {
            uint256 virtualPrice = ICurveStableSwapNG(WETH_PUFETH_CURVE).get_virtual_price();
            uint256 pufEthClFeed = IPufEth(PUFETH).previewRedeem(PRECISION);
            return virtualPrice * FixedPointMathLib.min(PRECISION, pufEthClFeed) / PRECISION;
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
