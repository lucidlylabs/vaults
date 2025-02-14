// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPendleSY {
    function getTokensOut() external view returns (address[] memory res);
}
