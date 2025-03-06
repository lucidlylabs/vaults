// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";

import {PoolV2} from "../src/Poolv2.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";

contract Aggregator is Ownable {
    bool public paused;

    error Aggregator__AlreadyPaused();
    error Aggregator__NotPaused();
    error Aggregator__Paused();

    event Pause(address indexed caller);
    event Unpause(address indexed caller);

    constructor() {
        _setOwner(msg.sender);
    }

    function deposit(
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        _checkIfPaused();
        require(tokens.length == tokenAmounts.length, "tokens and tokenAmounts should be of same length");

        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            SafeTransferLib.safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
            ERC20(tokens[i]).approve(poolAddress, tokenAmounts[i]);
        }

        address vaultAddress = PoolV2(poolAddress).vaultAddress();
        uint256 lpReceived = PoolV2(poolAddress).addLiquidity(tokenAmounts, minLpAmount, address(this));
        PoolToken(PoolV2(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function depositSingle(
        uint256 tokenIndex,
        uint256 tokenAmount,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        _checkIfPaused();
        address token = PoolV2(poolAddress).tokens(tokenIndex);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), tokenAmount);
        ERC20(token).approve(poolAddress, tokenAmount);

        uint256 numTokens = PoolV2(poolAddress).numTokens();
        uint256[] memory addLiquidityAmounts = new uint256[](numTokens);
        addLiquidityAmounts[tokenIndex] = tokenAmount;
        address vaultAddress = PoolV2(poolAddress).vaultAddress();
        uint256 lpReceived = PoolV2(poolAddress).addLiquidity(addLiquidityAmounts, minLpAmount, address(this));
        PoolToken(PoolV2(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function depositFor(
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        _checkIfPaused();
        require(tokens.length == tokenAmounts.length, "tokens and tokenAmounts should be of same length");
        address vaultAddress = PoolV2(poolAddress).vaultAddress();
        uint256 lpReceived = PoolV2(poolAddress).addLiquidityFor(tokenAmounts, minLpAmount, msg.sender, address(this));
        PoolToken(PoolV2(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function depositForSingle(
        uint256 tokenIndex,
        uint256 tokenAmount,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        _checkIfPaused();
        address vaultAddress = PoolV2(poolAddress).vaultAddress();
        uint256 numTokens = PoolV2(poolAddress).numTokens();
        uint256[] memory addLiquidityAmounts = new uint256[](numTokens);
        addLiquidityAmounts[tokenIndex] = tokenAmount;
        uint256 lpReceived =
            PoolV2(poolAddress).addLiquidityFor(addLiquidityAmounts, minLpAmount, msg.sender, address(this));
        PoolToken(PoolV2(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function redeemBalanced(
        address poolAddress,
        uint256 sharesToBurn,
        uint256[] calldata minAmountsOut,
        address receiver
    ) external {
        _checkIfPaused();
        Vault vault = Vault(PoolV2(poolAddress).vaultAddress());
        uint256 lpRedeemed = vault.redeem(sharesToBurn, address(this), msg.sender);
        PoolV2(poolAddress).removeLiquidity(lpRedeemed, minAmountsOut, receiver);
    }

    function redeemSingle(
        address poolAddress,
        uint256 tokenOut,
        uint256 sharesToBurn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 tokenOutAmount) {
        _checkIfPaused();
        Vault vault = Vault(PoolV2(poolAddress).vaultAddress());
        uint256 lpRedeemed = vault.redeem(sharesToBurn, address(this), msg.sender);
        tokenOutAmount = PoolV2(poolAddress).removeLiquiditySingle(tokenOut, lpRedeemed, minAmountOut, receiver);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice pause the pool
    function pause() external onlyOwner {
        if (paused) revert Aggregator__AlreadyPaused();
        paused = true;
        emit Pause(msg.sender);
    }

    /// @notice unpause the pool
    function unpause() external onlyOwner {
        if (!paused) revert Aggregator__NotPaused();
        paused = false;
        emit Unpause(msg.sender);
    }

    function _checkIfPaused() internal view {
        if (paused == true) {
            revert Aggregator__Paused();
        }
    }
}
