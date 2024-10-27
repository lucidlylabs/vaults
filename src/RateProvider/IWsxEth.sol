// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWsxEth {
    function convertToAssets(uint256 shares) external view returns (uint256);
}
