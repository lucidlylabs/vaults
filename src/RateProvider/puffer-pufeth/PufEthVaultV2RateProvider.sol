// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {IRateProvider} from "../IRateProvider.sol";
import {IStEth} from "../IStEth.sol";
import {ICurveStableSwapNG} from "../ICurveStableSwapNG.sol";
import {FixedPointMathLib} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface, RedstoneDataFeedLib} from "../libraries/RedstoneDataFeedLib.sol";
import {ERC4626} from "../../../lib/solady/src/tokens/ERC4626.sol";

contract PufEthVaultV2RateProvider is IRateProvider {
    using RedstoneDataFeedLib for AggregatorV3Interface;
    using FixedPointMathLib for uint256;

    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;

    address private constant PUFETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    address private constant PUFETH_WSTETH_CURVE = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
    address private constant WETH_PUFETH_CURVE = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;
    address private constant GAUNTLET_WETH_CORE = 0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658;

    address private constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address private constant PUFETH_ETH_REDSTONE_FEED = 0x76A495b0bFfb53ef3F0E94ef0763e03cE410835C;
    address private constant STETH_ETH_CHAINLINK_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    function rate(address token) external view returns (uint256) {
        if (token == PUFETH) {
            return ERC4626(token).convertToAssets(PRECISION);
        } else if (token == PUFETH_WSTETH_CURVE) {
            ICurveStableSwapNG pool = ICurveStableSwapNG(token);
            uint256 virtualPrice = pool.get_virtual_price();

            // fetching redstone pufEth/Eth price
            AggregatorV3Interface redstonePufEthFeed = AggregatorV3Interface(PUFETH_ETH_REDSTONE_FEED);
            uint256 pufEthRedstonePrice = redstonePufEthFeed.getPrice();
            uint256 decimals = redstonePufEthFeed.getDecimals();
            uint256 adjustedPufEthPrice = pufEthRedstonePrice.mulWad(10 ** (36 - decimals));

            // fetching wstEth/Eth price
            uint256 wstEthStEthPrice = IStEth(STETH).getPooledEthByShares(PRECISION);
            AggregatorV3Interface chainlinkStEthFeed = AggregatorV3Interface(STETH_ETH_CHAINLINK_FEED);
            uint256 chainlinkStEthPrice = chainlinkStEthFeed.getPrice();
            uint256 wstEthEthPrice = wstEthStEthPrice.mulWad(chainlinkStEthPrice);

            // lpPrice = virtual_price * min(oracle_feed_0, oracle_feed_1)
            return virtualPrice.mulWad(adjustedPufEthPrice.min(wstEthEthPrice));
        } else if (token == WETH_PUFETH_CURVE) {
            ICurveStableSwapNG pool = ICurveStableSwapNG(token);
            uint256 virtualPrice = pool.get_virtual_price();

            // fetching redstone pufEth/Eth price
            AggregatorV3Interface feed = AggregatorV3Interface(PUFETH_ETH_REDSTONE_FEED);
            uint256 pufEthRedstonePrice = feed.getPrice();
            uint256 decimals = feed.getDecimals();
            uint256 adjustedPufEthPrice = pufEthRedstonePrice.mulWad(10 ** (36 - decimals));

            // lpPrice = virtual_price * min(oracle_feed_0, oracle_feed_1)
            return virtualPrice.mulWad(adjustedPufEthPrice.min(PRECISION));
        } else if (token == GAUNTLET_WETH_CORE) {
            return ERC4626(token).convertToAssets(PRECISION);
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
