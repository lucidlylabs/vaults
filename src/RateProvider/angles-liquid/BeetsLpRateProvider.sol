// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC4626} from "../../../lib/solady/src/tokens/ERC4626.sol";
import {IRateProvider} from "../IRateProvider.sol";

contract BeetsLpRateProvider is IRateProvider {
    error RateProvider__InvalidParam();

    uint256 private constant PRECISION = 1e18;
    address private constant BPT = 0x944D4AE892dE4BFd38742Cc8295d6D5164c5593C;

    function rate(address token) external view returns (uint256) {
        if (token == BPT) {
            (bool success, bytes memory data) = BPT.staticcall(abi.encodeWithSelector(bytes4(keccak256("getRate()"))));
            return abi.decode(data, (uint256));
        } else {
            revert RateProvider__InvalidParam();
        }
    }
}
