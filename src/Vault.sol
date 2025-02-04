// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {IERC20Metadata, IERC20, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC4626Fees} from "../lib/openzeppelin-contracts/contracts/mocks/docs/ERC4626Fees.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {PoolToken} from "./PoolToken.sol";

contract Vault is ERC4626Fees, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error Vault__ProtocolFeeAddressCannotBeZero();
    error Vault__ProtocolFeeCannotExceed500Bps();
    error Vault__RecipientCannotBeZeroAddress();
    error Vault__DepositCapMaxxedOut();
    error Vault__NewCapCannotBeLessThanTotalAssets();
    error Vault__ManagementFeeCannotExceed500Bps();
    error Vault__PerformanceFeeCannotExceed6000Bps();
    error Vault__ManagementFeeRecipientCannotBeZeroAddress();
    error Vault__DepositAmountTooLess();
    error Vault__InsufficientAssetsAfterFees();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CapUpdated(uint256 indexed newCap);
    event EntryFeeAddressSet(address indexed entryFeeAddress);
    event EntryFeeSet(uint256 indexed entryFee);
    event ManagementFeeSet(uint256 indexed managementFeeInBps);
    event ManagementFeeRecipientSet(address indexed managementFeeRecipient);
    event ClaimedFees(uint256 managementFees);
    event VaultNameChanged(string indexed neName);
    event VaultSymbolChanged(string indexed newSymbol);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STATE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev name of the vault token
    string private _name;

    /// @dev symbol of the vault token
    string private _symbol;

    /// @dev annualized management fee in basis points
    uint256 public managementFeeInBps;

    /// @dev deposit fee
    uint256 public entryFeeInBps;

    /// @dev management fee recipient
    address public managementFeeRecipient;

    /// @dev fee address
    address public entryFeeRecipient;

    /// @dev timestamp of the last management fee accrual
    uint256 public lastFeeAccrual;

    /// @dev deposit cap for the vault
    uint256 public depositCap;

    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_,
        uint256 managementFeeInBps_,
        uint256 entryFeeInBps_,
        address entryFeeRecipient_,
        address managementFeeRecipient_,
        address owner_
    ) ERC20(name_, symbol_) ERC4626(IERC20(underlying_)) {
        _name = name_;
        _symbol = symbol_;
        managementFeeInBps = managementFeeInBps_;
        entryFeeInBps = entryFeeInBps_;

        managementFeeRecipient = managementFeeRecipient_;
        entryFeeRecipient = entryFeeRecipient_;

        _setOwner(owner_);
        lastFeeAccrual = block.timestamp;

        depositCap = type(uint256).max;
    }

    /**
     * @notice Getter function to view accrued managementFees since last claim
     */
    function accruedManagementFees() public view returns (uint256) {
        uint256 elapsedTime = block.timestamp - lastFeeAccrual;
        if (elapsedTime == 0 || managementFeeInBps == 0) return 0;
        uint256 feeAmount =
            FixedPointMathLib.mulDivUp(totalAssets() * managementFeeInBps, elapsedTime, 365 days * 10_000);
        return feeAmount;
    }

    /**
     * @notice Accrues management fees based on time elapsed and user deposits.
     */
    function _accrueManagementFee() internal {
        uint256 elapsedTime = block.timestamp - lastFeeAccrual;
        if (elapsedTime == 0 || managementFeeInBps == 0) return;

        uint256 feeAmount =
            FixedPointMathLib.mulDivUp(totalAssets() * managementFeeInBps, elapsedTime, 365 days * 10_000);

        if (feeAmount > 0) {
            uint256 sharesToMint = convertToShares(feeAmount);
            _mint(managementFeeRecipient, sharesToMint);
            lastFeeAccrual = block.timestamp;
            emit ClaimedFees(feeAmount);
        }
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
            revert Vault__DepositCapMaxxedOut();
        }

        _accrueManagementFee();

        uint256 entryFee = Math.mulDiv(assets, entryFeeInBps, entryFeeInBps + 10_000, Math.Rounding.Ceil);
        uint256 effectiveDeposit = assets - entryFee;

        if (effectiveDeposit > 0) {
            super._deposit(caller, receiver, assets, shares);
        } else {
            revert Vault__DepositAmountTooLess();
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _accrueManagementFee();
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
        emit VaultNameChanged(newName);
    }
    /**
     * @notice Changes the symbol of the token.
     * @param newSymbol The new symbol for the token.
     */

    function updateSymbol(string memory newSymbol) public onlyOwner {
        _symbol = newSymbol;
        emit VaultSymbolChanged(newSymbol);
    }

    /**
     * @notice Sets the recipient for deposit fees.
     * @param address_ The address to receive deposit fees.
     */
    function setEntryFeeAddress(address address_) public onlyOwner {
        if (address_ == address(0)) revert Vault__ProtocolFeeAddressCannotBeZero();
        entryFeeRecipient = address_;
        emit EntryFeeAddressSet(address_);
    }

    /**
     * @notice Sets the deposit fee in basis points.
     * @param fee_ The new deposit fee, capped at 500 basis points.
     */
    function setEntryFeeInBps(uint256 fee_) public onlyOwner {
        if (fee_ > 500) revert Vault__ProtocolFeeCannotExceed500Bps();
        entryFeeInBps = fee_;
        emit EntryFeeSet(fee_);
    }

    /**
     * @notice performance fee in basis points
     */
    function performanceFeeInBps() public view returns (uint256) {
        return PoolToken(asset()).performanceFeeInBps();
    }

    /**
     * @notice performance fee recipient's address
     */
    function performanceFeeRecipient() public view returns (address) {
        return PoolToken(asset()).performanceFeeRecipient();
    }

    /**
     * @notice Sets the performance fee in basis points.
     * @param fee_ The new performance fee, capped at 6000 basis points.
     */
    function setPerformanceFeeInBps(uint256 fee_) public onlyOwner {
        if (fee_ > 6000) revert Vault__PerformanceFeeCannotExceed6000Bps();
        PoolToken(asset()).setPerformanceFeeInBps(fee_);
    }

    /**
     * @notice Sets the recipient for management fees.
     * @param recipient_ The address to receive management fees.
     */
    function setPerformanceFeeRecipient(address recipient_) public onlyOwner {
        if (recipient_ == address(0)) revert Vault__ManagementFeeRecipientCannotBeZeroAddress();
        PoolToken(asset()).setPerformanceFeeRecipient(recipient_);
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
        return entryFeeInBps;
    }

    function _entryFeeRecipient() internal view virtual override returns (address) {
        return entryFeeRecipient;
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          HARVEST FEES                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Manually accrues fees for management
     */
    function harvestFees() external {
        _accrueManagementFee();
    }
}
