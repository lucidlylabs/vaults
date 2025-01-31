// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {FeeSplitter} from "../src/utils/FeeSplitter.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";

contract FeeSplitterTest is Test {
    FeeSplitter splitter;

    ERC20 public token;
    address public recipient0;
    address public recipient1;
    address public owner;

    function setUp() public {
        owner = address(this);
        recipient0 = address(0x123);
        recipient1 = address(0x456);

        string memory name = "Mock Token";
        string memory symbol = "MTK";
        uint8 decimals = 18;
        token = ERC20(address(new MockToken(name, symbol, decimals)));

        splitter = new FeeSplitter(address(token), recipient0, recipient1);
    }

    function testUpdateBalances() public {
        MockToken(address(token)).mint(address(splitter), 1_000_000 * 1e18);
        uint256 initialBalance0 = splitter.recipient0OwedAmount();
        uint256 initialBalance1 = splitter.recipient1OwedAmount();

        assertEq(initialBalance0, 0, "Initial balance for recipient0 should be zero");
        assertEq(initialBalance1, 0, "Initial balance for recipient1 should be zero");
        splitter.updateBalances();
        uint256 newBalance0 = splitter.recipient0OwedAmount();
        uint256 newBalance1 = splitter.recipient1OwedAmount();

        assertApproxEqAbs(newBalance0, 800_000 * 1e18, 100, "Recipient0 did not receive 80%");
        assertApproxEqAbs(newBalance1, 200_000 * 1e18, 100, "Recipient1 did not receive 20%");
    }

    function testClaimingFees() public {
        MockToken(address(token)).mint(address(splitter), 1_000_000 * 1e18);
        splitter.updateBalances();
        uint256 balanceBeforeClaim0 = token.balanceOf(recipient0);
        uint256 balanceBeforeClaim1 = token.balanceOf(recipient1);

        vm.prank(recipient0);
        splitter.claimRecipient0();
        uint256 balanceAfterClaim0 = token.balanceOf(recipient0);
        assertGt(balanceAfterClaim0, balanceBeforeClaim0, "Recipient0 did not receive any tokens");

        vm.prank(recipient1);
        splitter.claimRecipient1();
        uint256 balanceAfterClaim1 = token.balanceOf(recipient1);
        assertGt(balanceAfterClaim1, balanceBeforeClaim1, "Recipient1 did not receive any tokens");

        assertEq(splitter.recipient0OwedAmount(), 0, "Recipient0 balance not reset");
        assertEq(splitter.recipient1OwedAmount(), 0, "Recipient1 balance not reset");
    }

    function testUpdateRecipients() public {
        address newRecipient0 = address(0x789);
        address newRecipient1 = address(0x9ab);

        vm.expectRevert(bytes("Unauthorized"));
        vm.prank(owner);
        splitter.updateRecipient0(newRecipient0);

        vm.prank(recipient0);
        splitter.updateRecipient0(newRecipient0);
        assertEq(splitter.recipient0(), newRecipient0, "Recipient0 address not updated");

        vm.prank(recipient1);
        splitter.updateRecipient1(newRecipient1);
        assertEq(splitter.recipient1(), newRecipient1, "Recipient1 address not updated");
    }

    function testComplexFeeDistribution() public {
        address A = recipient0;
        address B = recipient1;

        // first fee mint
        uint256 initialFeeAmount = 1000 * 1e18;
        MockToken(address(token)).mint(address(splitter), initialFeeAmount);
        splitter.updateBalances();

        uint256 expectedA = (initialFeeAmount * 80) / 100;
        uint256 expectedB = initialFeeAmount - expectedA;
        assertApproxEqAbs(splitter.recipient0OwedAmount(), expectedA, 1, "A's balance incorrect after first deposit");
        assertApproxEqAbs(splitter.recipient1OwedAmount(), expectedB, 1, "B's balance incorrect after first deposit");

        uint256 bBalanceBeforeClaim = token.balanceOf(B);
        vm.prank(B);
        splitter.claimRecipient1();
        uint256 bBalanceAfterClaim = token.balanceOf(B);
        assertApproxEqAbs(bBalanceAfterClaim - bBalanceBeforeClaim, expectedB, 1, "B did not claim correct amount");

        // 2nd fee amount
        uint256 secondFeeAmount = 2000 * 1e18;
        MockToken(address(token)).mint(address(splitter), secondFeeAmount);
        splitter.updateBalances();

        uint256 aBalanceBeforeClaim = token.balanceOf(A);
        vm.prank(A);
        splitter.claimRecipient0();
        uint256 aBalanceAfterClaim = token.balanceOf(A);

        uint256 expectedACombined = expectedA + (secondFeeAmount * 80) / 100;
        assertApproxEqAbs(
            aBalanceAfterClaim - aBalanceBeforeClaim, expectedACombined, 1, "A did not claim correct combined amount"
        );

        // third fee amount
        uint256 thirdFeeAmount = 3000 * 10 ** 18;
        MockToken(address(token)).mint(address(splitter), thirdFeeAmount);
        splitter.updateBalances();

        bBalanceBeforeClaim = token.balanceOf(B);
        vm.prank(B);
        splitter.claimRecipient1();
        bBalanceAfterClaim = token.balanceOf(B);

        uint256 expectedBThird = (secondFeeAmount * 20) / 100 + (thirdFeeAmount * 20) / 100;
        assertApproxEqAbs(
            bBalanceAfterClaim - bBalanceBeforeClaim,
            expectedBThird,
            1,
            "B did not claim correct amount from third deposit"
        );

        aBalanceBeforeClaim = token.balanceOf(A);
        vm.prank(A);
        splitter.claimRecipient0();
        aBalanceAfterClaim = token.balanceOf(A);
        uint256 expectedAThird = (thirdFeeAmount * 80) / 100;
        assertApproxEqAbs(
            aBalanceAfterClaim - aBalanceBeforeClaim,
            expectedAThird,
            1,
            "A did not claim correct amount from third deposit"
        );

        uint256 totalExpectedA = ((initialFeeAmount + secondFeeAmount + thirdFeeAmount) * 80) / 100;
        uint256 totalExpectedB = ((initialFeeAmount + secondFeeAmount + thirdFeeAmount) * 20) / 100;
        assertApproxEqAbs(token.balanceOf(A), totalExpectedA, 1, "A's total balance incorrect");
        assertApproxEqAbs(token.balanceOf(B), totalExpectedB, 1, "B's total balance incorrect");
    }
}
