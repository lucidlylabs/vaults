// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISilo {
    function convertToAssets(uint256 _shares) external view returns (uint256);
}
