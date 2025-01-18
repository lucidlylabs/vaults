// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC20} from "solady/tokens/ERC20.sol";
import {LibSort} from "solady/utils/LibSort.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "../tests/PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";

contract Aggregator {
    function deposit(
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        require(tokens.length == tokenAmounts.length, "tokens and tokenAmounts should be of same length");

        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            SafeTransferLib.safeTransferFrom(tokens[i], msg.sender, address(this), tokenAmounts[i]);
            ERC20(tokens[i]).approve(poolAddress, tokenAmounts[i]);
        }

        address vaultAddress = Pool(poolAddress).vaultAddress();
        uint256 lpReceived = Pool(poolAddress).addLiquidity(tokenAmounts, minLpAmount, address(this));
        PoolToken(Pool(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function depositSingle(
        uint256 tokenIndex,
        uint256 tokenAmount,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        address token = Pool(poolAddress).tokens(tokenIndex);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), tokenAmount);
        ERC20(token).approve(poolAddress, tokenAmount);

        uint256 numTokens = Pool(poolAddress).numTokens();
        uint256[] memory addLiquidityAmounts = new uint256[](numTokens);
        addLiquidityAmounts[tokenIndex] = tokenAmount;
        address vaultAddress = Pool(poolAddress).vaultAddress();
        uint256 lpReceived = Pool(poolAddress).addLiquidity(addLiquidityAmounts, minLpAmount, address(this));
        PoolToken(Pool(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function depositFor(
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        require(tokens.length == tokenAmounts.length, "tokens and tokenAmounts should be of same length");
        address vaultAddress = Pool(poolAddress).vaultAddress();
        uint256 lpReceived = Pool(poolAddress).addLiquidityFor(tokenAmounts, minLpAmount, msg.sender, address(this));
        PoolToken(Pool(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function depositForSingle(
        uint256 tokenIndex,
        uint256 tokenAmount,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        address vaultAddress = Pool(poolAddress).vaultAddress();
        uint256 numTokens = Pool(poolAddress).numTokens();
        uint256[] memory addLiquidityAmounts = new uint256[](numTokens);
        addLiquidityAmounts[tokenIndex] = tokenAmount;
        uint256 lpReceived =
            Pool(poolAddress).addLiquidityFor(addLiquidityAmounts, minLpAmount, msg.sender, address(this));
        PoolToken(Pool(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function redeemBalanced(
        address poolAddress,
        uint256 sharesToBurn,
        uint256[] calldata minAmountsOut,
        address receiver
    ) external {
        Vault vault = Vault(Pool(poolAddress).vaultAddress());
        uint256 lpRedeemed = vault.redeem(sharesToBurn, address(this), msg.sender);
        Pool(poolAddress).removeLiquidity(lpRedeemed, minAmountsOut, receiver);
    }

    function redeemSingle(
        address poolAddress,
        uint256 tokenOut,
        uint256 sharesToBurn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 tokenOutAmount) {
        Vault vault = Vault(Pool(poolAddress).vaultAddress());
        uint256 lpRedeemed = vault.redeem(sharesToBurn, address(this), msg.sender);
        tokenOutAmount = Pool(poolAddress).removeLiquiditySingle(tokenOut, lpRedeemed, minAmountOut, receiver);
    }
}
