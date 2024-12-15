// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {IRateProvider} from "../IRateProvider.sol";
import {ISUSDe} from "../ISUSDe.sol";
import {ICurveStableSwapNG} from "../ICurveStableSwapNG.sol";
import {FixedPointMathLib} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface, ChainlinkDataFeedLib} from "../libraries/ChainlinkDataFeedLib.sol";
import {ERC20} from "../../../lib/solady/src/tokens/ERC20.sol";
import {ERC4626} from "../../../lib/solady/src/tokens/ERC4626.sol";

contract EthenaVaultV2RateProvider is IRateProvider {
    using ChainlinkDataFeedLib for AggregatorV3Interface;
    using FixedPointMathLib for uint256;

    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;

    address private constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address private constant SDAISUSDE_CURVE = 0x167478921b907422F8E88B43C4Af2B8BEa278d3A;
    address private constant YPTSUSDE = 0x57fC2D9809F777Cd5c8C433442264B6E8bE7Fce4;
    address private constant GAUNTLET_USDC_PRIME = 0xdd0f28e19C1780eb6396170735D45153D261490d;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant SUSDE_USD_CHAINLINK_FEED = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;
    address private constant USDE_USD_CHAINLINK_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
    address private constant USDC_USD_CHAINLINK_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    function rate(address token) external view returns (uint256) {
        if (token == SUSDE) {
            AggregatorV3Interface feed = AggregatorV3Interface(SUSDE_USD_CHAINLINK_FEED);
            uint256 price = feed.getPrice();
            uint256 decimals = feed.getDecimals();
            uint256 adjustedPrice = price.mulWad(10 ** (36 - decimals));
            return adjustedPrice;
        } else if (token == SDAISUSDE_CURVE) {
            uint256 priceInSusde = _fetchCurveLpPrice(token, 1);
            AggregatorV3Interface feed = AggregatorV3Interface(SUSDE_USD_CHAINLINK_FEED);
            uint256 susdePrice = feed.getPrice();
            uint256 decimals = feed.getDecimals();
            uint256 adjustedSusdePrice = susdePrice.mulWad(10 ** (36 - decimals));
            return priceInSusde.mulWad(adjustedSusdePrice);
        } else if (token == YPTSUSDE) {
            uint256 priceInSusde = ERC4626(YPTSUSDE).convertToAssets(PRECISION);
            AggregatorV3Interface feed = AggregatorV3Interface(SUSDE_USD_CHAINLINK_FEED);
            uint256 susdePrice = feed.getPrice();
            uint256 decimals = feed.getDecimals();
            uint256 adjustedSusdePrice = susdePrice.mulWad(10 ** (36 - decimals));
            return priceInSusde.mulWad(adjustedSusdePrice);
        } else if (token == GAUNTLET_USDC_PRIME) {
            uint256 priceInUsdc = ERC4626(GAUNTLET_USDC_PRIME).convertToAssets(PRECISION);
            uint256 adjustedPriceInUsdc = priceInUsdc.mulWad(10 ** (36 - ERC20(USDC).decimals()));
            AggregatorV3Interface feed = AggregatorV3Interface(USDC_USD_CHAINLINK_FEED);
            uint256 usdcPrice = feed.getPrice();
            uint256 decimals = feed.getDecimals();
            uint256 adjustedUsdcPrice = usdcPrice.mulWad(10 ** (36 - decimals));
            return adjustedPriceInUsdc.mulWad(adjustedUsdcPrice);
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
}
