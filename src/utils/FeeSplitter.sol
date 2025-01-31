// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC20} from "../../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solady/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "../../lib/solady/src/utils/ReentrancyGuard.sol";

contract FeeSplitter is ReentrancyGuard {
    event FeesDistributed(uint256 amountForRecipient0, uint256 amountForRecipient1);
    event FeesClaimed(address indexed recipient, uint256 amount);

    ERC20 public token;
    address public recipient0;
    address public recipient1;

    uint256 public recipient0OwedAmount;
    uint256 public recipient1OwedAmount;

    constructor(address feeToken, address r0, address r1) {
        token = ERC20(feeToken);

        recipient0 = r0;
        recipient1 = r1;
    }

    function updateBalances() public {
        uint256 currentBalance = token.balanceOf(address(this));
        uint256 newFees = currentBalance - (recipient0OwedAmount + recipient1OwedAmount);

        if (newFees > 0) {
            uint256 amountForRecipient0 = newFees * 80 / 100;
            uint256 amountForRecipient1 = newFees - amountForRecipient0;
            recipient0OwedAmount += amountForRecipient0;
            recipient1OwedAmount += amountForRecipient1;
        }

        emit FeesDistributed(recipient0OwedAmount, recipient1OwedAmount);
    }

    function claimRecipient0() external nonReentrant {
        require(msg.sender == recipient0, "Only recipient0 can claim this");
        updateBalances();
        uint256 amount = recipient0OwedAmount;
        recipient0OwedAmount = 0;

        SafeTransferLib.safeTransfer(address(token), recipient0, amount);
        emit FeesClaimed(msg.sender, amount);
    }

    function claimRecipient1() external nonReentrant {
        require(msg.sender == recipient1, "Only recipient1 can claim this");
        updateBalances();
        uint256 amount = recipient1OwedAmount;
        recipient1OwedAmount = 0;
        SafeTransferLib.safeTransfer(address(token), recipient1, amount);
        emit FeesClaimed(msg.sender, amount);
    }

    function checkBalanceRecipient0() external view returns (uint256) {
        uint256 currentBalance = token.balanceOf(address(this));
        return recipient0OwedAmount + ((currentBalance - (recipient0OwedAmount + recipient1OwedAmount)) * 80 / 100);
    }

    function checkBalanceRecipient1() external view returns (uint256) {
        uint256 currentBalance = token.balanceOf(address(this));
        return recipient1OwedAmount + ((currentBalance - (recipient0OwedAmount + recipient1OwedAmount)) * 20 / 100);
    }

    function updateRecipient0(address newRecipient0) external {
        require(msg.sender == recipient0, "Unauthorized");
        require(newRecipient0 != address(0), "New recipient cannot be zero address");
        recipient0 = newRecipient0;
    }

    function updateRecipient1(address newRecipient1) external {
        require(msg.sender == recipient1, "Unauthorized");
        require(newRecipient1 != address(0), "New recipient cannot be zero address");
        recipient1 = newRecipient1;
    }
}
