// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICurvePool {
    function price_oracle() external view returns (uint256);
}
