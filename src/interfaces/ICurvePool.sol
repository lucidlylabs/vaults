// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICurvePool {
    function name() external view returns (string memory);

    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external returns (uint256);

    function remove_liquidity(uint256 _burn_amount, uint256[2] memory _min_amounts) external returns (uint256);
}
