// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";
import {IERC20, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626Fees} from "openzeppelin-contracts/contracts/mocks/docs/ERC4626Fees.sol";

contract Vault is ERC4626Fees, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error Staking__ProtocolFeeAddressCannotBeZero();
    error Staking__ProtocolFeeCannotExceed500Bps();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event SetProtocolFeeAddress(address indexed protocolFeeAddress);
    event SetDepositFee(uint256 indexed depositFee);

    uint256 public depositFeeInBps;
    address public protocolFeeAddress;

    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_,
        uint256 depositFeeInBps_,
        address protocolFeeAddress_,
        address owner_
    ) ERC20(name_, symbol_) ERC4626(IERC20(underlying_)) {
        depositFeeInBps = depositFeeInBps_;
        protocolFeeAddress = protocolFeeAddress_;
        _setOwner(owner_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      FEE CONFIGURATION                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setProtocolFeeAddress(address address_) public onlyOwner {
        if (address_ == address(0)) revert Staking__ProtocolFeeAddressCannotBeZero();
        protocolFeeAddress = address_;
        emit SetProtocolFeeAddress(address_);
    }

    function setDepositFeeInBps(uint256 fee_) public onlyOwner {
        if (fee_ > 500) revert Staking__ProtocolFeeCannotExceed500Bps();
        depositFeeInBps = fee_;
        emit SetDepositFee(fee_);
    }

    function _entryFeeBasisPoints() internal view virtual override returns (uint256) {
        return depositFeeInBps;
    }

    function _entryFeeRecipient() internal view virtual override returns (address) {
        return protocolFeeAddress;
    }
}
