// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICurveStableSwapNG {
    function get_virtual_price() external view returns (uint256);
}
