// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBeetsGauge is IERC20 {
    function deposit(uint256 value) external;
    function withdraw(uint256 value) external;
    function claim_rewards(address account) external;
}
