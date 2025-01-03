// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IXERC20} from "../interface/IXERC20.sol";

abstract contract xVaultStorage {
    struct xVault {
        /**
         * @notice The address of the lockbox contract
         */
        address lockbox;
        /**
         * @notice Maps bridge address to bridge configurations
         */
        mapping(address bridge => IXERC20.Bridge config) bridges;
    }

    // keccak256(abi.encode(uint256(keccak256("xVault.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _STORAGE_LOCATION = 0x3233e2211a1a4c1c52b80cd3679c02dbb443534a536ab3c7068efd2ca95db000;

    function _getXVaultStorage() internal pure returns (xVault storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := _STORAGE_LOCATION
        }
    }
}
