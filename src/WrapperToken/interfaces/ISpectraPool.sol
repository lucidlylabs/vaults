// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISpectraPool {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount, bool use_eth, address receiver)
        external
        returns (uint256);
}
