// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

interface IPendleOracle {
    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256);
    function getLpToAssetRate(address market, uint32 duration) external view returns (uint256);
}
