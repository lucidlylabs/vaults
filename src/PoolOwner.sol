// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {OwnableRoles} from "../lib/solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";

contract PoolOwner is OwnableRoles {
    address public poolAddress;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             AUTH                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    uint256 public constant ROLE_POOL_OWNER = 1 << 0; // 0x1
    uint256 public constant ROLE_POOL_MANAGER = 1 << 1; // 0x2
    uint256 public constant ROLE_POOL_MONITOR = 1 << 2; // 0x4

    modifier onlyPoolOwner() {
        _checkRoles(ROLE_POOL_OWNER);
        _;
    }

    modifier onlyPoolMonitor() {
        _checkRoles(ROLE_POOL_MONITOR | ROLE_POOL_OWNER);
        _;
    }

    modifier onlyPoolManager() {
        _checkRoles(ROLE_POOL_MANAGER | ROLE_POOL_OWNER);
        _;
    }

    constructor(address poolAddress_) {
        poolAddress = poolAddress_;
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ROLE_POOL_OWNER);
    }

    function assignRole(address user_, uint256 role_) external onlyPoolOwner {
        _grantRoles(user_, role_);
    }

    function revokeRole(address user_, uint256 role_) external onlyPoolOwner {
        _removeRoles(user_, role_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      POOL AUTH FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function transferPoolOwnership(address newOwner_) external onlyPoolOwner {
        (bool success, bytes memory data) =
            poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("transferOwnership(address)")), newOwner_));

        if (!success) {
            _handleRevert(data, "Failed to transfer pool ownership.");
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      MONITOR FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function pausePool() external onlyPoolMonitor {
        (bool success, bytes memory data) = poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("pause()"))));

        if (!success) {
            _handleRevert(data, "Failed to pause the pool.");
        }
    }

    function unpausePool() external onlyPoolMonitor {
        (bool success, bytes memory data) = poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("unpause()"))));

        if (!success) {
            _handleRevert(data, "Failed to unpause the pool.");
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      MANAGER FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function addToken(
        address token_,
        address rateProvider_,
        uint256 weight_,
        uint256 lower_,
        uint256 upper_,
        uint256 amount_,
        uint256 amplification_,
        uint256 minLpAmount_,
        address receiver_
    ) external onlyPoolManager {
        SafeTransferLib.safeTransferFrom(token_, msg.sender, address(this), amount_);
        ERC20(token_).approve(poolAddress, amount_);

        (bool success, bytes memory data) = poolAddress.call(
            abi.encodeWithSelector(
                bytes4(keccak256("addToken(address,address,uint256,uint256,uint256,uint256,uint256,uint256,address)")),
                token_,
                rateProvider_,
                weight_,
                lower_,
                upper_,
                amount_,
                amplification_,
                minLpAmount_,
                receiver_
            )
        );

        if (!success) {
            _handleRevert(data, "Failed to add new token");
        }
    }

    function setSwapFeeRate(uint256 feeRate_) external onlyPoolManager {
        (bool success, bytes memory data) =
            poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("setSwapFeeRate(uint256)")), feeRate_));

        if (!success) {
            _handleRevert(data, "Failed to set swap fee rate");
        }
    }

    function setWeightBands(uint256[] calldata tokens_, uint256[] calldata lower_, uint256[] calldata upper_)
        external
        onlyPoolManager
    {
        (bool success, bytes memory data) = poolAddress.call(
            abi.encodeWithSelector(
                bytes4(keccak256("setWeightBands(uint256[],uint256[],uint256[])")), tokens_, lower_, upper_
            )
        );

        if (!success) {
            _handleRevert(data, "Failed to set weight bands.");
        }
    }

    function setVaultAddress(address vaultAddress_) external onlyPoolManager {
        (bool success, bytes memory data) =
            poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("setVaultAddress(address)")), vaultAddress_));

        if (!success) {
            _handleRevert(data, "Failed to set vault address.");
        }
    }

    function setRateProvider(uint256 token_, address rateProvider_) external onlyPoolManager {
        (bool success, bytes memory data) = poolAddress.call(
            abi.encodeWithSelector(bytes4(keccak256("setRateProvider(uint256,address)")), token_, rateProvider_)
        );

        if (!success) {
            _handleRevert(data, "Failed to set rateProvider");
        }
    }

    function setRamp(uint256 amplification_, uint256[] calldata weights_, uint256 duration_, uint256 start_)
        external
        onlyPoolManager
    {
        (bool success, bytes memory data) = poolAddress.call(
            abi.encodeWithSelector(
                bytes4(keccak256("setRamp(uint256,uint256[],uint256,uint256)")),
                amplification_,
                weights_,
                duration_,
                start_
            )
        );

        if (!success) {
            _handleRevert(data, "Failed to set ramp.");
        }
    }

    function setRampStep(uint256 rampStep_) external onlyPoolManager {
        (bool success, bytes memory data) =
            poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("setRampStep(uint256)")), rampStep_));

        if (!success) {
            _handleRevert(data, "Failed to set ramp step.");
        }
    }

    function stopRamp() external onlyPoolManager {
        (bool success, bytes memory data) = poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("stopRamp()"))));

        if (!success) {
            _handleRevert(data, "Failed to stop ramp.");
        }
    }

    function rescue(address token_, address receiver_) external onlyPoolOwner {
        (bool success, bytes memory data) =
            poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("rescue(uint256,address)")), token_, receiver_));

        if (!success) {
            _handleRevert(data, "Failed to rescue token.");
        }
    }

    function skim(uint256 token_, address receiver_) external onlyPoolOwner {
        (bool success, bytes memory data) =
            poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("skim(uint256,address)")), token_, receiver_));

        if (!success) {
            _handleRevert(data, "Failed to skim token.");
        }
    }

    function _handleRevert(bytes memory data_, string memory defaultMessage_) internal pure {
        if (data_.length > 0) {
            assembly {
                let returndata_size := mload(data_)
                revert(add(32, data_), returndata_size)
            }
        } else {
            revert(defaultMessage_);
        }
    }
}
