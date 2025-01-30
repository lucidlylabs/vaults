// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {PoolV2} from "../src/Poolv2.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
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

        address vaultAddress = PoolV2(poolAddress).vaultAddress();
        uint256 lpReceived = PoolV2(poolAddress).addLiquidity(tokenAmounts, minLpAmount, address(this));
        PoolToken(PoolV2(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function depositFromRouter(
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        require(tokens.length == tokenAmounts.length, "tokens and tokenAmounts should be of same length");

        for (uint256 i = 0; i < tokenAmounts.length; i++) {
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

    function depositSingleFromRouter(
        uint256 tokenIndex,
        uint256 tokenAmount,
        address receiver,
        uint256 minLpAmount,
        address poolAddress
    ) external returns (uint256 shares) {
        address token = PoolV2(poolAddress).tokens(tokenIndex);
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
        Vault vault = Vault(PoolV2(poolAddress).vaultAddress());
        uint256 lpRedeemed = vault.redeem(sharesToBurn, address(this), msg.sender);
        tokenOutAmount = PoolV2(poolAddress).removeLiquiditySingle(tokenOut, lpRedeemed, minAmountOut, receiver);
    }

    function executeZapAndDeposit(
        address zapTokenAddress,
        uint256 zapTokenAmount,
        uint256 tokenIndex,
        address receiver,
        uint256 minLpAmount,
        address poolAddress,
        address routerAddress,
        bytes calldata data
    ) external returns (uint256 shares) {
        require(zapTokenAddress != address(0), "invalid zapTokenAddress.");
        require(zapTokenAmount != 0, "cannot allow 0 amount to zap in.");

        SafeTransferLib.safeTransferFrom(zapTokenAddress, msg.sender, address(this), zapTokenAmount);
        SafeTransferLib.safeApprove(zapTokenAddress, routerAddress, zapTokenAmount);

        address token = PoolV2(poolAddress).tokens(tokenIndex);
        uint256 cachedBalance = ERC20(token).balanceOf(address(this));

        (bool success,) = routerAddress.call(data);
        require(success, "router call failed");

        uint256 tokenAmount = ERC20(token).balanceOf(address(this)) - cachedBalance;

        ERC20(token).approve(poolAddress, tokenAmount);
        uint256 numTokens = PoolV2(poolAddress).numTokens();
        uint256[] memory addLiquidityAmounts = new uint256[](numTokens);
        addLiquidityAmounts[tokenIndex] = tokenAmount;
        address vaultAddress = PoolV2(poolAddress).vaultAddress();
        uint256 lpReceived = PoolV2(poolAddress).addLiquidity(addLiquidityAmounts, minLpAmount, address(this));
        PoolToken(PoolV2(poolAddress).tokenAddress()).approve(vaultAddress, lpReceived);
        shares = Vault(vaultAddress).deposit(lpReceived, receiver);
    }

    function executeRedeemAndZap(
        address poolAddress,
        uint256 sharesToBurn,
        uint256 tokenOut,
        uint256 minAmountOut,
        address zapTokenAddress,
        address routerAddress,
        bytes calldata data,
        address receiver
    ) external returns (uint256 zapTokenAmount) {
        require(zapTokenAddress != address(0), "invalid zapTokenAddress.");

        Vault vault = Vault(PoolV2(poolAddress).vaultAddress());
        uint256 lpRedeemed = vault.redeem(sharesToBurn, address(this), msg.sender);
        uint256 tokenAmount =
            PoolV2(poolAddress).removeLiquiditySingle(tokenOut, lpRedeemed, minAmountOut, address(this));

        address token = PoolV2(poolAddress).tokens(tokenOut);

        uint256 currentAllowance = ERC20(token).allowance(address(this), routerAddress);
        if (currentAllowance > 0) {
            SafeTransferLib.safeApprove(token, routerAddress, 0);
        }
        SafeTransferLib.safeApprove(token, routerAddress, tokenAmount);

        uint256 cachedBalance = ERC20(zapTokenAddress).balanceOf(address(this));
        (bool success,) = routerAddress.call(data);
        require(success, "router call failed");
        zapTokenAmount = ERC20(zapTokenAddress).balanceOf(address(this)) - cachedBalance;
        SafeTransferLib.safeTransfer(zapTokenAddress, receiver, zapTokenAmount);
    }
}
