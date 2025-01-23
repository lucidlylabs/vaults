// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Vault} from "../Vault.sol";
import {Pool} from "../Pool.sol";
import {RateProvider} from "./RateProvider.sol";

contract RateProviderRepository is Ownable {
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    Vault public vault;
    Pool public pool;
    EnumerableSetLib.AddressSet private tokenAddresses;
    mapping(address => address) public rateProviders;

    error TokenNotSupported();
    constructor(address vault_, address pool_) {
        vault = Vault(vault_);
        pool = Pool(pool_);
    }

    function getVaultSharePrice() external view returns (uint256) {
        return vault.previewRedeem(1e18);
    }

    function isTokenSupported(address token_) external view returns (bool) {
        return tokenAddresses.contains(token_);
    }

    function addToken(address token_, address rateProvider_) external onlyOwner {
        tokenAddresses.add(token_);
        rateProviders[token_] = rateProvider_;
    }

    function removeToken(address token_) external onlyOwner {
        tokenAddresses.remove(token_);
        rateProviders[token_] = address(0);
    }

    function getRateProvider(address token_) external view returns (address) {
        return rateProviders[token_];
    }

    function setRateProvider(address token_, address rateProvider_) external onlyOwner {
        if (!tokenAddresses.contains(token_)) revert TokenNotSupported();
        
        rateProviders[token_] = rateProvider_;
    }

    function getRate(address token_) external view returns (uint256) {
        if (!tokenAddresses.contains(token_)) revert TokenNotSupported();

        return RateProvider(rateProviders[token_]).rate(token_);
    }

    function getVaultSharePriceInAsset(address token_) external view returns (uint256) {
        if (!tokenAddresses.contains(token_)) revert TokenNotSupported();

        uint256 vaultSharePrice = vault.previewRedeem(1e18);
        uint256 rate = RateProvider(rateProviders[token_]).rate(token_);

        return vaultSharePrice * (10 ** ERC20(token_).decimals()) / rate;
    }

    function getAssetPriceInVaultShare(address token_) external view returns (uint256) {
        if (!tokenAddresses.contains(token_)) revert TokenNotSupported();

        uint256 vaultSharePrice = vault.previewRedeem(1e18);
        uint256 rate = RateProvider(rateProviders[token_]).rate(token_);
        return rate * 1e18 / vaultSharePrice;
    }
}
