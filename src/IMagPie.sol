// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMagPie {
    /**
     * @notice Interface function for multicall
     * @param data Encoded calls in an array of bytes
     * @return results An array of call return data
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
