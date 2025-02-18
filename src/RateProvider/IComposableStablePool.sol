// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IComposableStablePool {
    function getLastJoinExitData() external view returns (uint256, uint256);

    function getRate() external view returns (uint256);
}
