// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICurveStableSwapNG {
    function get_virtual_price() external view returns (uint256);
    function stored_rates() external view returns (uint256[] memory);
    function price_oracle(uint256 i) external view returns (uint256);
}
