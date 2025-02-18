// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISpectraPrincipalToken {
  function convertToUnderlying(uint256 principalAmount) external view returns (uint256);
  function underlying() external view returns (address);
}
