// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISpectraCampaignManager {
    function claim(
        address token,
        address rewardToken,
        uint256 earnedAmount,
        uint256 claimAmount,
        bytes32[] calldata merkleProof
    ) external;
}
