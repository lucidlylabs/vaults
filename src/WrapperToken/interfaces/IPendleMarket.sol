// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IPendleMarket is IERC20 {
    function readTokens()
        external
        view
        returns (
            address _SY,
            address _PT,
            address _YT
        );
}
