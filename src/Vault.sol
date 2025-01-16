// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
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
    event SetManagementFee(uint256 indexed managementFeeInBps);
    event AccruedManagementFee(uint256 feeAmount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STATE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public depositFeeInBps;
    uint256 public managementFeeInBps; // Annualized management fee in basis points
    uint256 public lastFeeAccrual; // Timestamp of the last management fee accrual

    address public protocolFeeAddress;
    address public managementFeeRecipient;

    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_,
        uint256 depositFeeInBps_,
        uint256 managementFeeInBps_,
        address protocolFeeAddress_,
        address managementFeeRecipient_,
        address owner_
    ) ERC20(name_, symbol_) ERC4626(IERC20(underlying_)) {
        depositFeeInBps = depositFeeInBps_;
        managementFeeInBps = managementFeeInBps_;
        protocolFeeAddress = protocolFeeAddress_;
        managementFeeRecipient = managementFeeRecipient_;
        _setOwner(owner_);
        lastFeeAccrual = block.timestamp;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    MANAGEMENT FEE LOGIC                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function accrueManagementFee() public {
        uint256 elapsedTime = block.timestamp - lastFeeAccrual;
        if (elapsedTime == 0 || managementFeeInBps == 0) return;

        uint256 totalAssetsValue = totalAssets();
        uint256 feeAmount = (totalAssetsValue * elapsedTime * managementFeeInBps) / 10_000 / 365 days;

        if (feeAmount > 0) {
            _mint(managementFeeRecipient, convertToShares(feeAmount));
            emit AccruedManagementFee(feeAmount);
        }

        lastFeeAccrual = block.timestamp;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    OVERRIDE FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        accrueManagementFee();
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        accrueManagementFee();
        super._withdraw(caller, receiver, owner, assets, shares);
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

    function setManagementFeeInBps(uint256 fee_) public onlyOwner {
        require(fee_ <= 500, "Management fee exceeds 5%");
        managementFeeInBps = fee_;
        emit SetManagementFee(fee_);
    }

    function setManagementFeeRecipient(address recipient_) public onlyOwner {
        require(recipient_ != address(0), "Recipient cannot be zero address");
        managementFeeRecipient = recipient_;
    }

    function _entryFeeBasisPoints() internal view virtual override returns (uint256) {
        return depositFeeInBps;
    }

    function _entryFeeRecipient() internal view virtual override returns (address) {
        return protocolFeeAddress;
    }
}
