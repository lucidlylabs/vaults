// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {IERC20Metadata, IERC20, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626Fees} from "../lib/openzeppelin-contracts/contracts/mocks/docs/ERC4626Fees.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

contract Vault is ERC4626Fees, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error Vault__ProtocolFeeAddressCannotBeZero();
    error Vault__ProtocolFeeCannotExceed500Bps();
    error Vault__RecipientCannotBeZeroAddress();
    error Vault__DepositCapMAxxedOut();
    error Vault__NewCapCannotBeLessThanTotalAssets();
    error Vault__ManagementFeeCannotExceed500Bps();
    error Vault__ManagementFeeRecipientCannotBeZeroAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CapUpdated(uint256 indexed newCap);
    event ProtocolFeeAddressSet(address indexed protocolFeeAddress);
    event DepositFeeSet(uint256 indexed depositFee);
    event ManagementFeeSet(uint256 indexed managementFeeInBps);
    event ManagementFeeRecipientSet(address indexed managementFeeRecipient);
    event ClaimedFees(uint256 managementFees);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STATE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev name of the vault token
    string private _name;

    /// @dev symbol of the vault token
    string private _symbol;

    /// @dev performance fee in basis points
    uint256 public performanceFeeInBps;

    /// @dev annualized management fee in basis points
    uint256 public managementFeeInBps;

    /// @dev deposit fee
    uint256 public depositFeeInBps;

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
        _name = name_;
        _symbol = symbol_;
        managementFeeInBps = managementFeeInBps_;
        depositFeeInBps = depositFeeInBps_;

        managementFeeRecipient = managementFeeRecipient_;
        depositFeeRecipient = depositFeeRecipient_;

        _setOwner(owner_);
        lastFeeAccrual = block.timestamp;

        depositCap = type(uint256).max;
    }

    /**
     * @notice Accrues management fees based on time elapsed and user deposits.
     */
    function _accrueManagementFee() internal {
        uint256 elapsedTime = block.timestamp - lastFeeAccrual;
        if (elapsedTime == 0 || managementFeeInBps == 0) return;

        // uint256 feeAmount = (totalUserDeposits * elapsedTime * managementFeeInBps) / 10_000 / 365 days;
        uint256 feeAmount =
            FixedPointMathLib.mulDivUp(totalUserDeposits * managementFeeInBps, elapsedTime, 365 days * 10_000);
        accruedManagementFees = feeAmount > 0 ? accruedManagementFees + feeAmount : accruedManagementFees;
        lastFeeAccrual = block.timestamp;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ERC20 FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override (ERC20, IERC20Metadata) returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override (ERC20, IERC20Metadata) returns (string memory) {
        return _symbol;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC4626 FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (totalAssets() + assets > depositCap) {
            revert Vault__DepositCapMAxxedOut();
        }

        _accrueManagementFee();
        totalUserDeposits += assets;
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _accrueManagementFee();
        totalUserDeposits -= assets;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Changes the name of the token.
     * @param newName The new name for the token.
     */
    function updateName(string memory newName) public onlyOwner {
        _name = newName;
    }
    /**
     * @notice Changes the symbol of the token.
     * @param newSymbol The new symbol for the token.
     */

    function updateSymbol(string memory newSymbol) public onlyOwner {
        _symbol = newSymbol;
    }

    /**
     * @notice Sets the recipient for deposit fees.
     * @param address_ The address to receive deposit fees.
     */
    function setProtocolFeeAddress(address address_) public onlyOwner {
        if (address_ == address(0)) revert Vault__ProtocolFeeAddressCannotBeZero();
        depositFeeRecipient = address_;
        emit ProtocolFeeAddressSet(address_);
    }

    /**
     * @notice Sets the deposit fee in basis points.
     * @param fee_ The new deposit fee, capped at 500 basis points.
     */
    function setDepositFeeInBps(uint256 fee_) public onlyOwner {
        if (fee_ > 500) revert Vault__ProtocolFeeCannotExceed500Bps();
        depositFeeInBps = fee_;
        emit DepositFeeSet(fee_);
    }

    /**
     * @notice Sets the management fee in basis points.
     * @param fee_ The new management fee, capped at 500 basis points.
     */
    function setManagementFeeInBps(uint256 fee_) public onlyOwner {
        if (fee_ > 500) revert Vault__ManagementFeeCannotExceed500Bps();
        managementFeeInBps = fee_;
        emit ManagementFeeSet(fee_);
    }

    /**
     * @notice Sets the recipient for management fees.
     * @param recipient_ The address to receive management fees.
     */
    function setManagementFeeRecipient(address recipient_) public onlyOwner {
        if (recipient_ == address(0)) revert Vault__ManagementFeeRecipientCannotBeZeroAddress();
        managementFeeRecipient = recipient_;
        emit ManagementFeeRecipientSet(recipient_);
    }

    function _entryFeeBasisPoints() internal view virtual override returns (uint256) {
        return depositFeeInBps;
    }

    function _entryFeeRecipient() internal view virtual override returns (address) {
        return depositFeeRecipient;
    }

    /**
     * @notice Updates the deposit cap for the vault.
     * @param newCap_ The new deposit cap value.
     */
    function updateCap(uint256 newCap_) external onlyOwner {
        if (newCap_ < totalAssets()) {
            revert Vault__NewCapCannotBeLessThanTotalAssets();
        }
        depositCap = newCap_;
        emit CapUpdated(newCap_);
    }

    /**
     * @notice Manually accrues fees for management and performance.
     */
    function harvestFees() external {
        _accrueManagementFee();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CLAIM FEE LOGIC                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Claims accrued management and performance fees.
     */
    function claimFees() external onlyOwner {
        uint256 managementFeesToClaim = accruedManagementFees;

        if (managementFeesToClaim > 0) {
            _mint(managementFeeRecipient, convertToShares(managementFeesToClaim));
            accruedManagementFees = 0;
        }

        emit ClaimedFees(managementFeesToClaim);
    }
}
