// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRateProvider {
    function rate(address token) external view returns (uint256);
}

/// @dev returns (rate, quote token decimals)
interface IRateProviderV2 {
    function rate(address token) external view returns (uint256, uint8);
}
