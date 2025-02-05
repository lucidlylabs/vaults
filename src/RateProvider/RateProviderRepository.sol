// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";
import {Ownable} from "../../lib/solady/src/auth/Ownable.sol";
import {Vault} from "../Vault.sol";
import {PoolV2} from "../Poolv2.sol";
import {RateProvider} from "./RateProvider.sol";

import {ERC20} from "../../lib/solady/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "../../lib/solady/src/utils/FixedPointMathLib.sol";

contract RateProviderRepository is Ownable {
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    /// @notice the vault this repository is associated with
    Vault public immutable vault;

    /// @notice the underlying pool
    PoolV2 public immutable pool;

    ///  @notice the base asset rates are provided in.
    ERC20 public immutable base;

    /// @notice The decimals rates are provided in.
    uint8 public immutable decimals;

    /// @param isPeggedToBase whether or not the asset is 1:1 with the base asset
    /// @param rateProvider the rate provider for this asset if `isPeggedToBase` is false
    struct RateProviderData {
        bool isPeggedToBase;
        RateProvider rateProvider;
    }

    EnumerableSetLib.AddressSet private tokenAddresses;

    /// @dev Maps ERC20s to their RateProviderData.
    mapping(address => RateProviderData) public rateProviderData;

    error RateProviderRepository__TokenNotSupported();
    error RateProviderRepository__TokenAlreadySupported();

    constructor(address vault_, address pool_, address base_) {
        vault = Vault(vault_);
        pool = PoolV2(pool_);
        base = ERC20(base_);
        decimals = ERC20(vault_).decimals();
    }

    /// @notice returns price of one vault share in terms of base
    function getVaultSharePrice() external view returns (uint256) {
        return vault.previewRedeem(1e18);
    }

    /// @notice returns if a token is whitelisted in this address
    /// @param tokenAddress address of the ERC20
    function isTokenSupported(address tokenAddress) external view returns (bool) {
        return tokenAddresses.contains(tokenAddress);
    }

    function addToken(address tokenAddress, bool isPeggedToBase, address rateProviderAddress) external onlyOwner {
        if (tokenAddresses.contains(tokenAddress)) revert RateProviderRepository__TokenAlreadySupported();
        tokenAddresses.add(tokenAddress);

        rateProviderData[tokenAddress] =
            RateProviderData({isPeggedToBase: isPeggedToBase, rateProvider: RateProvider(rateProviderAddress)});
    }

    function removeToken(address tokenAddress) external onlyOwner {
        if (!tokenAddresses.contains(tokenAddress)) revert RateProviderRepository__TokenNotSupported();

        tokenAddresses.remove(tokenAddress);
        rateProviderData[tokenAddress] =
            RateProviderData({isPeggedToBase: false, rateProvider: RateProvider(address(0))});
    }

    /// @notice getter function for the rateProvider address.
    /// @dev the rateProvider returns a value where quote = base
    /// @param tokenAddress address of ERC20
    function getRateProvider(address tokenAddress) external view returns (address) {
        if (!tokenAddresses.contains(tokenAddress)) revert RateProviderRepository__TokenNotSupported();

        RateProvider rateProvider = rateProviderData[tokenAddress].rateProvider;
        return address(rateProvider);
    }

    /// @notice setter function for an ERC20 rateProviderData
    /// @dev the ERC20 must be registered in this contract
    /// @param tokenAddress ERC20 address
    /// @param isPeggedToBase boolean to store if the token is pegged to the base asset
    /// @param rateProviderAddress address of the rateProvider
    function setRateProvider(address tokenAddress, bool isPeggedToBase, address rateProviderAddress)
        external
        onlyOwner
    {
        if (!tokenAddresses.contains(tokenAddress)) revert RateProviderRepository__TokenNotSupported();

        rateProviderData[tokenAddress] =
            RateProviderData({isPeggedToBase: isPeggedToBase, rateProvider: RateProvider(rateProviderAddress)});
    }

    /// @notice returns the rate in terms of base
    /// @param tokenAddress ERC20 address
    function getRate(address tokenAddress) external view returns (uint256) {
        if (!tokenAddresses.contains(tokenAddress)) revert RateProviderRepository__TokenNotSupported();

        RateProviderData memory data = rateProviderData[tokenAddress];
        return data.rateProvider.rate(tokenAddress);
    }

    /// @notice get the price of one vault share in terms of ERC20(tokenAddress)
    /// @dev tokenAddress must have its RateProviderData set, else this will revert
    /// @dev This function will lose precision if the exchange rate decimals is greater than the asset's decimals.
    function getVaultSharePriceInAsset(address tokenAddress) external view returns (uint256) {
        if (!tokenAddresses.contains(tokenAddress)) revert RateProviderRepository__TokenNotSupported();

        uint256 rateOfVaultShareInBase = vault.previewRedeem(1e18);

        RateProviderData memory data = rateProviderData[tokenAddress];
        uint256 rateOfQuoteInBase = data.rateProvider.rate(tokenAddress);

        return FixedPointMathLib.divWadUp(rateOfVaultShareInBase, rateOfQuoteInBase);
    }

    /// @notice get the price of one unit of ERC20(tokenAddress) in terms of vault share
    /// @dev tokenAddress must have its RateProviderData set, else this will revert
    /// @dev This function will lose precision if the exchange rate decimals is greater than the asset's decimals.
    function getAssetPriceInVaultShare(address tokenAddress) external view returns (uint256) {
        if (!tokenAddresses.contains(tokenAddress)) revert RateProviderRepository__TokenNotSupported();

        uint256 rateOfVaultShareInBase = vault.previewRedeem(1e18);

        RateProviderData memory data = rateProviderData[tokenAddress];
        uint256 rateOfWantInBase = data.rateProvider.rate(tokenAddress);

        return FixedPointMathLib.divWad(rateOfWantInBase, rateOfVaultShareInBase);
    }
}
