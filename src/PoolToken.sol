// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract PoolToken is ERC20, Ownable {
    error Token__CallerIsNotPool();
    error Token__PoolAddressCannotBeZero();

    event PoolAddressSet(address newPoolAddress);

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    address poolAddress;

    function _checkCallerIsPool() internal view {
        if (msg.sender != poolAddress) {
            revert Token__CallerIsNotPool();
        }
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address owner_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _setOwner(owner_);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to_, uint256 amount_) public {
        _checkCallerIsPool();
        _mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_) public {
        _checkCallerIsPool();
        _burn(from_, amount_);
    }

    function setPool(address poolAddress_) public onlyOwner {
        if (poolAddress_ == address(0)) revert Token__PoolAddressCannotBeZero();
        poolAddress = poolAddress_;
        renounceOwnership();
        emit PoolAddressSet(poolAddress);
    }
}
