// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "../../../lib/solady/src/auth/Ownable.sol";
import {ERC20} from "../../../lib/solady/src/tokens/ERC20.sol";
import {ReentrancyGuard} from "../../../lib/solady/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "../../../lib/solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "../../../lib/solady/src/utils/SafeTransferLib.sol";

import {Pool} from "../../Pool.sol";
import {SwapAdapter} from "../SwapAdapter.sol";

// PUFETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
// PUFETH_WSTETH_CURVE = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
// WETH_PUFETH_CURVE = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;
// GAUNTLET_WETH_CORE = 0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658;

/**
 * 0 - 1 -> pufEth <-> wstEth
 * 0 - 2 -> pufEth <-> weth
 * 0 - 3 -> pufEth <-> weth
 * 1 - 2 -> pufEth <-> weth | pufEth <-> wstEth | weth <-> wstEth
 * 1 - 3 -> pufEth <-> weth | wstEth <-> weth
 * 2 - 3 -> pufEth <-> weth
 */

/**
 * pufEth -> wstEth
 * ------ pufeth -> pool.swap(pufEth, pufethwsteth) -> curve_pool.remove_liquidity_one_coin(pufethwsteth) -> wsteth
 * ------ wsteth -> curve.add_liquidity(wsteth) -> pool.swap(pufethwsteth, pufeth) -> pufeth
 */
contract EthenaVaultSwapAdapter is SwapAdapter {
    address immutable PUFETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    address immutable PUFETH_WSTETH_CURVE = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
    address immutable WETH_PUFETH_CURVE = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;
    address immutable GAUNTLET_WETH_CORE = 0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658;
    address immutable WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address immutable pool;

    constructor(address poolAddress) {
        pool = poolAddress;
    }

    /// @dev swap paths for token0 <-> token1
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 tokenInAmount,
        uint256 minTokenOutAmount,
        uint256 minTokenOutAmount2,
        uint256 minTokenOutAmount3,
        address receiver
    ) external virtual override returns (uint256 tokenOutAmount) {
        SafeTransferLib.safeTransferFrom(tokenIn, msg.sender, address(this), tokenInAmount);
        if (tokenIn == PUFETH) {
            (bool success, bytes memory data) = pool.call(
                abi.encodeWithSelector(
                    bytes4(keccak256("swap(uint256,uint256,uint256,uint256,address)")),
                    0,
                    1,
                    tokenInAmount,
                    minTokenOutAmount,
                    address(this)
                )
            );
            require(success, "Failed to swap from lucidly pool contract");
            uint256 tokensOut = abi.decode(data, (uint256));
            (success, data) = PUFETH_WSTETH_CURVE.call(
                abi.encodeWithSelector(
                    bytes4(keccak256("remove_liquidity_one_coin(uint256,uint256,uint256,address)")),
                    tokensOut,
                    1,
                    minTokenOutAmount2,
                    receiver
                )
            );
            require(success, "Failed to remove liquidity from curve pool");
            uint256 tokensWithdrawn = abi.decode(data, (uint256));
            require(tokensWithdrawn > minTokenOutAmount3);
        } else if (tokenIn == WSTETH) {
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = tokenInAmount;
            (bool success, bytes memory data) = PUFETH_WSTETH_CURVE.call(
                abi.encodeWithSelector(
                    bytes4(keccak256("add_liquidity(uint256[],uint256,address)")),
                    amounts,
                    minTokenOutAmount2,
                    address(this)
                )
            );
            require(success, "Failed to add liquidity from curve pool");
            uint256 lpMinted = abi.decode(data, (uint256));
            (success, data) =
                PUFETH_WSTETH_CURVE.call(abi.encodeWithSelector(keccak256("approve(address,uint256)")), pool, lpMinted);
            require(success, "failed to approve.");
            (success, data) = pool.call(abi.encodeWithSelector(keccak256("swap")));
        }
    }
}
