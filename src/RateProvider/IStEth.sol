// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStEth {
    function getPooledEthByShares(uint256 _shares) external view returns (uint256);
}
