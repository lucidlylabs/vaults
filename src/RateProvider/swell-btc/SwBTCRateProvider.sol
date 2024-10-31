// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {console} from "../../../lib/forge-std/src/console.sol";
import {FixedPointMathLib} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";

import {ISWBTC} from "./ISWBTC.sol";
import {IRateProvider} from "../IRateProvider.sol";
import {ICurveStableSwapNG} from "../ICurveStableSwapNG.sol";
import {IMetaMorpho} from "../IMetaMorpho.sol";

contract SWBTCRateProvider is IRateProvider {
    error RateProvider__InvalidParam();

    uint256 private PRECISION = 1e8;

    address private SWBTCWBTC_CURVE = 0x73e4BeC1A111869F395cBB24F6676826BF86d905;
    address private SWBTC = 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE;
    address private GAUNTLET_WBTC_CORE = 0x443df5eEE3196e9b2Dd77CaBd3eA76C3dee8f9b2;

    /// @dev scaling factor is 10 ** (18 - 8)
    function rate(address token) external view returns (uint256) {
        if (token == SWBTC) {
            return ISWBTC(token).convertToAssets(PRECISION) * 1e10; // scaling factor is 10 ** (18 - 8)
        } else if (token == SWBTCWBTC_CURVE) {
            ICurveStableSwapNG pool = ICurveStableSwapNG(token);
            uint256 virtualPrice = pool.get_virtual_price();
            // price of the lp token in terms of swBTC
            uint256 rateInToken0 =
                virtualPrice * FixedPointMathLib.min(1, pool.price_oracle(0) * 1e18 / pool.stored_rates()[0]);
            return (rateInToken0 * ISWBTC(SWBTC).convertToAssets(PRECISION) * 1e10) / 1e18;
        } else if (token == GAUNTLET_WBTC_CORE) {
            return IMetaMorpho(GAUNTLET_WBTC_CORE).convertToAssets(1e18) * 1e10;
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
