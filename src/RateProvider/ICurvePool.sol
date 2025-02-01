// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICurvePool {
    function lp_price() external view returns (uint256);
}
