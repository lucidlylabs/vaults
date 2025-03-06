// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC4626} from "../../../lib/solady/src/tokens/ERC4626.sol";
import {IRateProvider} from "../IRateProvider.sol";

contract SpectraLpRateProvider is IRateProvider {
    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;
    address private SPECTRA_LP = 0xEc81ee88906ED712deA0a17A3Cd8A869eBFA89A0;
    address private WRAPPED_ANGLES_S = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;
    address private WRAPPED_ANGLES_S_RATE_PROVIDER = 0x2d087C0999223997b77cc33BE5E7E8eC79396cea;
    address private CURVE_POOL = 0x2386ebDE944e723Ffd9066bE23709444342d2685;

    function rate(address token) external view returns (uint256) {
        if (token == SPECTRA_LP) {
            (bool success, bytes memory data) =
                CURVE_POOL.staticcall(abi.encodeWithSelector(bytes4(keccak256("lp_price()"))));
            uint256 lpPriceInWans = abi.decode(data, (uint256));
            (success, data) =
                WRAPPED_ANGLES_S_RATE_PROVIDER.staticcall(abi.encodeWithSelector(bytes4(keccak256("getRate()"))));
            uint256 wanSPrice = abi.decode(data, (uint256));
            return lpPriceInWans * wanSPrice / 1e18;
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
