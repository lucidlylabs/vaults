// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

interface IERC4626RateProvider {
    function getRate() external view returns (uint256);
}
