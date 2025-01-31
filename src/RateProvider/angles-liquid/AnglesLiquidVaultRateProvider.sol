// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {IRateProvider} from "../IRateProvider.sol";
import {IERC4626RateProvider} from "./IERC4626RateProvider.sol";

contract AnglesLiquidVaultRateProvider is IRateProvider {
    error RateProvider__InvalidParam();

    uint256 immutable PRECISION = 1e18;

    address immutable WRAPPED_ANGLES_S = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;
    address immutable WRAPPED_S = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address immutable WRAPPED_ANGLES_S_RATE_PROVIDER = 0x2d087C0999223997b77cc33BE5E7E8eC79396cea;

    /// @dev hardcode price of WRAPPED_S to PRECISION
    function rate(address token) external view returns (uint256) {
        if (token == WRAPPED_S) {
            return PRECISION;
        } else if (token == WRAPPED_ANGLES_S) {
            return IERC4626RateProvider(WRAPPED_ANGLES_S_RATE_PROVIDER).getRate();
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
