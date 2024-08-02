// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";

contract RateProvider is Ownable {
    mapping(address => uint256) rates;

    function rate(address token_) external view returns (uint256) {
        return rates[token_];
    }

    function setRate(address token_) external {}
}
