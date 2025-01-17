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
    event SetPerformanceFee(uint256 indexed performanceFeeInBps);
    event SetPerformanceFeeRecipient(address indexed performanceFeeRecipient);
    event AccruedPerformanceFee(uint256 feeAmount);
    event ClaimedFees(uint256 managementFees, uint256 performanceFees);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STATE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev performance fee in basis points
    uint256 public performanceFeeInBps;

    /// @dev high-water mark for calculating performance fee
    uint256 public highWaterMark;

    /// @dev peformance fee recipient
    address public performanceFeeRecipient;

    /// @dev deposit fee
    uint256 public depositFeeInBps;

    /// @dev annualized management fee in basis points
    uint256 public managementFeeInBps;

    /// @dev timestamp of the last management fee accrual
    uint256 public lastFeeAccrual;

    /// @dev fee address
    address public protocolFeeAddress;

    /// @dev management fee recipient
    address public managementFeeRecipient;

    /// @dev management fees accrued since last claim
    uint256 public accruedManagementFees;

    /// @dev performace fees accrued since last claim
    uint256 public accruedPerformanceFees;

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
        highWaterMark = totalAssets();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PERFORMANCE FEE LOGIC                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _accruePerformanceFee() internal {
        uint256 totalAssetsValue = totalAssets();

        if (totalAssetsValue > highWaterMark && performanceFeeInBps > 0) {
            uint256 profit = totalAssetsValue - highWaterMark;
            uint256 feeAmount = (profit * performanceFeeInBps) / 10_000;

            if (feeAmount > 0) {
                accruedPerformanceFees += feeAmount;
            }

            highWaterMark = totalAssetsValue;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    MANAGEMENT FEE LOGIC                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _accrueManagementFee() internal {
        uint256 elapsedTime = block.timestamp - lastFeeAccrual;
        if (elapsedTime == 0 || managementFeeInBps == 0) return;

        uint256 totalAssetsValue = totalAssets();
        uint256 feeAmount = (totalAssetsValue * elapsedTime * managementFeeInBps) / 10_000 / 365 days;

        if (feeAmount > 0) {
            accruedManagementFees += feeAmount;
        }

        lastFeeAccrual = block.timestamp;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    OVERRIDE FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _accrueManagementFee();
        _accruePerformanceFee();
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _accrueManagementFee();
        _accruePerformanceFee();
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      FEE CONFIGURATION                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setPerformanceFeeInBps(uint256 fee_) public onlyOwner {
        require(fee_ <= 500, "Performance fee exceeds 5%");
        performanceFeeInBps = fee_;
        emit SetPerformanceFee(fee_);
    }

    function setPerformanceFeeRecipient(address recipient_) public onlyOwner {
        require(recipient_ != address(0), "Recipient cannot be zero address");
        performanceFeeRecipient = recipient_;
        emit SetPerformanceFeeRecipient(recipient_);
    }

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
