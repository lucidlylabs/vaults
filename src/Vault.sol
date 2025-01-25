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

    error Vault__ProtocolFeeAddressCannotBeZero();
    error Vault__ProtocolFeeCannotExceed500Bps();
    error Vault__PerformanceFeeCannotExceed500bps();
    error Vault__RecipientCannotBeZeroAddress();
    error Vault__DepositCapMAxxedOut();
    error Vault__NewCapCannotBeLessThanTotalAssets();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CapUpdated(uint256 indexed newCap);
    event SetProtocolFeeAddress(address indexed protocolFeeAddress);
    event SetDepositFee(uint256 indexed depositFee);
    event SetManagementFee(uint256 indexed managementFeeInBps);
    event AccruedManagementFee(uint256 feeAmount);
    event SetPerformanceFee(uint256 indexed performanceFeeInBps);
    event SetPerformanceFeeRecipient(address indexed performanceFeeRecipient);
    event AccruedPerformanceFee(uint256 feeAmount);
    event ClaimedFees(uint256 managementFees, uint256 performanceFees);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STATE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev performance fee in basis points
    uint256 public performanceFeeInBps;

    /// @dev annualized management fee in basis points
    uint256 public managementFeeInBps;

    /// @dev deposit fee
    uint256 public depositFeeInBps;

    /// @dev high-water mark for calculating performance fee
    uint256 public highWaterMark;

    /// @dev total assets deposited by users. (totalAssets() - yield)
    uint256 public totalUserDeposits;

    /// @dev peformance fee recipient
    address public performanceFeeRecipient;

    /// @dev management fee recipient
    address public managementFeeRecipient;

    /// @dev fee address
    address public depositFeeRecipient;

    /// @dev timestamp of the last management fee accrual
    uint256 public lastFeeAccrual;

    /// @dev management fees accrued since last claim
    uint256 public accruedManagementFees;

    /// @dev performace fees accrued since last claim
    uint256 public accruedPerformanceFees;

    /// @dev deposit cap for the vault
    uint256 public depositCap;

    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_,
        uint256 managementFeeInBps_,
        uint256 depositFeeInBps_,
        address depositFeeRecipient_,
        address managementFeeRecipient_,
        address owner_
    ) ERC20(name_, symbol_) ERC4626(IERC20(underlying_)) {
        managementFeeInBps = managementFeeInBps_;
        depositFeeInBps = depositFeeInBps_;

        managementFeeRecipient = managementFeeRecipient_;
        depositFeeRecipient = depositFeeRecipient_;

        _setOwner(owner_);
        lastFeeAccrual = block.timestamp;
        highWaterMark = totalAssets();

        depositCap = type(uint256).max;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PERFORMANCE FEE LOGIC                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _accruePerformanceFee() internal {
        uint256 totalAssetsValue = totalAssets();
        uint256 yield = totalAssetsValue > totalUserDeposits ? totalAssetsValue - totalUserDeposits : 0;

        uint256 feeAmount = yield > 0 && performanceFeeInBps > 0 ? (yield * performanceFeeInBps) / 10_000 : 0;
        if (feeAmount > 0) accruedPerformanceFees += feeAmount;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    MANAGEMENT FEE LOGIC                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _accrueManagementFee() internal {
        uint256 elapsedTime = block.timestamp - lastFeeAccrual;
        if (elapsedTime == 0 || managementFeeInBps == 0) return;

        uint256 feeAmount = (totalUserDeposits * elapsedTime * managementFeeInBps) / 10_000 / 365 days;
        accruedManagementFees = feeAmount > 0 ? accruedManagementFees + feeAmount : accruedManagementFees;
        lastFeeAccrual = block.timestamp;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 ERC4626 OVERRIDE FUNCTIONS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (totalAssets() + assets > depositCap) {
            revert Vault__DepositCapMAxxedOut();
        }

        _accrueManagementFee();
        totalUserDeposits += assets;
        _accruePerformanceFee();
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _accrueManagementFee();
        totalUserDeposits -= assets;
        _accruePerformanceFee();
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setPerformanceFeeInBps(uint256 fee_) public onlyOwner {
        if (fee_ > 500) revert Vault__PerformanceFeeCannotExceed500bps();
        performanceFeeInBps = fee_;
        emit SetPerformanceFee(fee_);
    }

    function setPerformanceFeeRecipient(address recipient_) public onlyOwner {
        if (recipient_ == address(0)) revert Vault__RecipientCannotBeZeroAddress();
        performanceFeeRecipient = recipient_;
        emit SetPerformanceFeeRecipient(recipient_);
    }

    function setProtocolFeeAddress(address address_) public onlyOwner {
        if (address_ == address(0)) revert Vault__ProtocolFeeAddressCannotBeZero();
        depositFeeRecipient = address_;
        emit SetProtocolFeeAddress(address_);
    }

    function setDepositFeeInBps(uint256 fee_) public onlyOwner {
        if (fee_ > 500) revert Vault__ProtocolFeeCannotExceed500Bps();
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
        return depositFeeRecipient;
    }

    function updateCap(uint256 newCap_) external onlyOwner {
        if (newCap_ < totalAssets()) {
            revert Vault__NewCapCannotBeLessThanTotalAssets();
        }
        uint256 oldCap = depositCap;
        depositCap = newCap_;
        emit CapUpdated(newCap_);
    }

    function harvestFees() external {
        _accrueManagementFee();
        _accruePerformanceFee();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CLAIM FEE LOGIC                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function claimFees() external onlyOwner {
        uint256 managementFeesToClaim = accruedManagementFees;
        uint256 performanceFeesToClaim = accruedPerformanceFees;

        if (managementFeesToClaim > 0) {
            _mint(managementFeeRecipient, convertToShares(managementFeesToClaim));
            accruedManagementFees = 0;
        }

        if (performanceFeesToClaim > 0) {
            _mint(performanceFeeRecipient, convertToShares(performanceFeesToClaim));
            accruedPerformanceFees = 0;
        }

        emit ClaimedFees(managementFeesToClaim, performanceFeesToClaim);
    }
}
