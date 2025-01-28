// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {IRateProvider} from "../IRateProvider.sol";
import {FixedPointMathLib} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface, RedstoneDataFeedLib} from "../libraries/RedstoneDataFeedLib.sol";

contract RingsVaultRateProvider is IRateProvider {
    using RedstoneDataFeedLib for AggregatorV3Interface;
    using FixedPointMathLib for uint256;

    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;

    address private constant USDC_BRIDGED = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address private constant SCUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address private constant SCUSD_USDC_REDSTONE_FEED = 0xb81131B6368b3F0a83af09dB4E39Ac23DA96C2Db;

    /// @dev hardcode price of usdc.e to PRECISION
    function rate(address token) external view returns (uint256) {
        if (token == USDC_BRIDGED) {
            return PRECISION;
        } else if (token == SCUSD) {
            AggregatorV3Interface feed = AggregatorV3Interface(SCUSD_USDC_REDSTONE_FEED);
            uint256 priceInUsdc = feed.getPrice();
            uint256 decimals = feed.getDecimals();
            return priceInUsdc.mulWad(10 ** (36 - decimals));
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
