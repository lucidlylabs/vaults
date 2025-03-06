// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC4626} from "../../../lib/solady/src/tokens/ERC4626.sol";
import {IRateProvider} from "../IRateProvider.sol";

contract SiloBorrowableWsRateProvider is IRateProvider {
    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;
    address private SILO_BORROWABLE_WS = 0x016C306e103FbF48EC24810D078C65aD13c5f11B;

    function rate(address token) external view returns (uint256) {
        if (token == SILO_BORROWABLE_WS) {
            return ERC4626(SILO_BORROWABLE_WS).convertToAssets(1e18);
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
