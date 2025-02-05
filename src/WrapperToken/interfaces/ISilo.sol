// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ISilo is IERC20 {
    function deposit(uint256 _assets, address _receiver) external returns (uint256);
}
