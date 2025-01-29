// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {Ownable} from "../lib/solady/src/auth/Ownable.sol";

contract PoolToken is ERC20, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error Token__CallerIsNotPool();
    error Token__PoolAddressCannotBeZero();
    error Token__VaultAddressCannotBeZero();
    error Token__RecipientCannotBeZeroAddress();
    error Token__PerformanceFeeCannotExceed8000bps();
    error Token__PoolAddressAlreadySet();
    error Token__VaultAddressAlreadySet();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event PoolAddressSet(address newPoolAddress);
    event VaultAddressSet(address newVaultAddress);
    event PerformanceFeeSet(uint256 performanceFee);
    event PerformanceFeeRecipientSet(address performanceFeeRecipient);

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;

    address public poolAddress;
    address public vaultAddress;

    bool private poolAddressSet = false;
    bool private vaultAddressSet = false;

    /// @dev performance fee in basis points
    uint256 public performanceFeeInBps;

    /// @dev peformance fee recipient
    address public performanceFeeRecipient;

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

        if (to_ == vaultAddress) {
            uint256 feeAmount = (amount_ * performanceFeeInBps) / 10_000;
            _mint(performanceFeeRecipient, feeAmount);
            _mint(to_, amount_ - feeAmount);
        } else {
            _mint(to_, amount_);
        }
    }

    function burn(address from_, uint256 amount_) public {
        _checkCallerIsPool();
        _burn(from_, amount_);
    }

    function setPool(address poolAddress_) public onlyOwner {
        if (poolAddressSet) revert Token__PoolAddressAlreadySet();
        if (poolAddress_ == address(0)) revert Token__PoolAddressCannotBeZero();
        poolAddress = poolAddress_;
        poolAddressSet = true;
        emit PoolAddressSet(poolAddress_);
    }

    function setVaultAddress(address vaultAddress_) public onlyOwner {
        if (vaultAddressSet) revert Token__VaultAddressAlreadySet();
        if (vaultAddress_ == address(0)) revert Token__VaultAddressCannotBeZero();
        vaultAddress = vaultAddress_;
        vaultAddressSet = true;
        emit VaultAddressSet(vaultAddress_);
    }

    /**
     * @notice Sets the performance fee in basis points.
     * @param fee_ The new performance fee, capped at 8000 basis points.
     */
    function setPerformanceFeeInBps(uint256 fee_) public onlyOwner {
        if (fee_ > 8000) revert Token__PerformanceFeeCannotExceed8000bps();
        performanceFeeInBps = fee_;
        emit PerformanceFeeSet(fee_);
    }

    /**
     * @notice Sets the recipient for performance fees.
     * @param recipient_ The address to receive performance fees.
     */
    function setPerformanceFeeRecipient(address recipient_) public onlyOwner {
        if (recipient_ == address(0)) revert Token__RecipientCannotBeZeroAddress();
        performanceFeeRecipient = recipient_;
        emit PerformanceFeeRecipientSet(recipient_);
    }
}
