// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableRoles} from "../../lib/solady/src/auth/OwnableRoles.sol";
import {ReentrancyGuard} from "../../lib/solady/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "../../lib/solady/src/utils/FixedPointMathLib.sol";
import {Address} from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {SafeTransferLib} from "../../lib/solady/src/utils/SafeTransferLib.sol";
import {ERC20} from "../../lib/solady/src/tokens/ERC20.sol";

import {IRateProvider} from "../RateProvider/IRateProvider.sol";
import {IAtomicSolver} from "./IAtomicSolver.sol";

abstract contract AtomicSolver is IAtomicSolver {
    /// @notice to be called be the queue
    function finishSolve(
        bytes calldata runData,
        address initiator,
        ERC20 offer,
        ERC20 want,
        uint256 assetsToOffer,
        uint256 assetsForWant
    ) external virtual {
        (address[] memory targets, bytes[] memory datas, uint256[] memory values) =
            abi.decode(runData, (address[], bytes[], uint256[]));
        for (uint256 i; i < datas.length; ++i) {
            Address.functionCallWithValue(targets[i], datas[i], values[i]);
        }
        SafeTransferLib.safeApprove(address(want), msg.sender, assetsForWant);
    }
}
