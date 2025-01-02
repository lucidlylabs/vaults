// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Pool} from "./Pool.sol";
import {PoolToken} from "./PoolToken.sol";
import {Vault} from "./Vault.sol";
import {IRateProvider} from "./RateProvider/IRateProvider.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";

// contract FactoryV1 is Ownable {
//     event NewVaultCreated(address indexed poolAddress, address indexed vaultAddress, address indexed poolOwner);
//
//     constructor() {
//         _setOwner(msg.sender);
//     }
//
//     function create(
//         string memory poolTokenName,
//         string memory poolTokenSymbol,
//         uint8 poolTokenDecimals,
//         string memory vaultName,
//         string memory vaultSymbol,
//         uint256 amplification,
//         uint256[] memory weights,
//         address[] memory tokens,
//         address[] memory rateProviders,
//         uint256 swapFeeInBps,
//         uint256 depositFeeInBps
//     ) external onlyOwner returns (address poolAddress, address vaultAddress, address poolTokenAddress) {
//         require(weights.length == tokens.length, "mismatched weights and tokens length.");
//         require(rateProviders.length == tokens.length, "mismatched rate providers and tokens length.");
//
//         // deploying PoolToken
//         PoolToken poolToken = new PoolToken(poolTokenName, poolTokenSymbol, poolTokenDecimals, address(this));
//         poolTokenAddress = address(poolToken);
//
//         // deploying Pool
//         Pool pool = new Pool(poolTokenAddress, amplification, tokens, rateProviders, weights, address(this));
//         poolAddress = address(pool);
//
//         // deploying Vault
//         Vault vault = new Vault(poolTokenAddress, vaultName, vaultSymbol, depositFeeInBps, address(this), address(this));
//
//         // poolToken.setPool(poolAddress);
//         // pool.setVaultAddress(vaultAddress);
//         // pool.setSwapFeeRate(swapFeeInBps);
//         // vault.setDepositFeeInBps(depositFeeInBps);
//         // vault.setProtocolFeeAddress(msg.sender);
//
//         // // transfer ownership
//         // pool.transferOwnership(msg.sender);
//         // vault.transferOwnership(msg.sender);
//
//         emit NewVaultCreated(poolAddress, vaultAddress, pool.owner());
//     }
// }
