// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IBalancerVaultV3 {
    enum AddLiquidityKind {
        PROPORTIONAL,
        UNBALANCED,
        SINGLE_TOKEN_EXACT_OUT,
        DONATION,
        CUSTOM
    }

    struct AddLiquidityParams {
        address pool;
        address to;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        AddLiquidityKind kind;
        bytes userData;
    }

    enum SwapKind {
        EXACT_IN,
        EXACT_OUT
    }

    struct VaultSwapParams {
        SwapKind kind;
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 amountGivenRaw;
        uint256 limitRaw;
        bytes userData;
    }

    function addLiquidity(AddLiquidityParams memory params)
        external
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    function swap(VaultSwapParams memory vaultSwapParams)
        external
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);
}
