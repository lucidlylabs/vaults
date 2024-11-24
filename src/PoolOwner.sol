// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableRoles} from "../lib/solady/src/auth/OwnableRoles.sol";
import {Pool} from "./Pool.sol";

contract PoolOwner is OwnableRoles {
    address public poolAddress;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             AUTH                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    uint256 constant ROLE_POOL_OWNER = 1 << 0; // 0x1
    uint256 constant ROLE_POOL_MANAGER = 1 << 1; // 0x2
    uint256 constant ROLE_POOL_MONITOR = 1 << 2; // 0x4

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
    /*                      MONITOR FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function pausePool(address poolAddress_) external onlyPoolMonitor {
        (bool success, bytes memory data) = poolAddress_.call(abi.encodeWithSignature("pause()"));

        if (!success) {
            _handleRevert(data, "Failed to pause the pool.");
        }
    }

    function unpausePool(address poolAddress_) external onlyPoolMonitor {
        (bool success, bytes memory data) = poolAddress_.call(abi.encodeWithSignature("unpause()"));

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

    function setSwapFeeRate(uint256 feeRate_) external onlyPoolMonitor {
        (bool success, bytes memory data) =
            poolAddress.call(abi.encodeWithSelector(bytes4(keccak256("setSwapFeeRate(uint256)")), feeRate_));

        if (!success) {
            _handleRevert(data, "Failed to set swap fee rate");
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
