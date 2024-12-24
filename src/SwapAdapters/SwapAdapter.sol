// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract SwapAdapter {
    function swap(address tokenIn, address tokenOut, uint256 tokenInAmount, uint256 minTokenOutAmount)
        external
        virtual
        returns (uint256 tokenOutAmount)
    {}
}
