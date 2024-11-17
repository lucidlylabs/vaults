// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRateProvider} from "../RateProvider/IRateProvider.sol";

contract MockRateProvider is IRateProvider {
    mapping(address => uint256) public rate;

    function setRate(address token_, uint256 rate_) external {
        rate[token_] = rate_;
    }
}
