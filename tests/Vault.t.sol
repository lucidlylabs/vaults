// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {Vault} from "../src/Vault.sol";
import {IERC20, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

contract VaultTest is Test {
    using Math for uint256;

    Vault public vault;
    IERC20 public asset;
    address public owner;
    address public user;
    address public user2;
    address public user3;
    address public user4;

    function setUp() public {
        string memory name = "Mock Token";
        string memory symbol = "MTK";
        uint8 decimals = 18;
        uint256 initialSupply = 1_000_000 * 10 ** decimals;
        asset = IERC20(address(new MockToken(name, symbol, 18)));

        owner = address(this);
        user = address(0x123);
        user2 = address(0x456);

        vault = new Vault(address(asset), "Vault Token", "VTK", 0, 0, address(0x456), address(0x789), owner);

        MockToken(address(asset)).mint(user, 100_000 * 10 ** decimals);
        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);

        MockToken(address(asset)).mint(user2, 100_000 * 10 ** decimals);
        vm.prank(user2);
        asset.approve(address(vault), type(uint256).max);

        MockToken(address(asset)).mint(user3, 100_000 * 10 ** decimals);
        vm.prank(user3);
        asset.approve(address(vault), type(uint256).max);

        MockToken(address(asset)).mint(user4, 100_000 * 10 ** decimals);
        vm.prank(user4);
        asset.approve(address(vault), type(uint256).max);
    }

    function testUpdateCap() public {
        uint256 initialCap = vault.depositCap();
        uint256 newCap = 1_000_000 * 1e18;

        vm.expectRevert(bytes4(keccak256(bytes("Unauthorized()"))));
        vm.prank(user);
        vault.updateCap(newCap);

        vault.updateCap(newCap);
        assertEq(vault.depositCap(), newCap, "Cap was not updated correctly");

        vm.prank(user);
        vault.deposit(100 * 10 ** 18, user);

        uint256 tooLowCap = vault.totalAssets() - 1;
        vm.expectRevert(abi.encodeWithSelector(Vault.Vault__NewCapCannotBeLessThanTotalAssets.selector));
        vault.updateCap(tooLowCap);
    }

    function testManagementFeeAccounting() public {
        vault.setManagementFeeInBps(100);
        uint256 initialTime = vault.lastFeeAccrual();
        vm.warp(initialTime + 365 days);

        uint256 initialTotalAssets = vault.totalAssets();
        vm.prank(user);
        vault.deposit(100 * 10 ** 18, user);

        vault.harvestFees();
        // vault.claimFees();

        uint256 expectedFee = (initialTotalAssets * 100) / 10_000;
        assertApproxEqAbs(vault.accruedManagementFees(), expectedFee, 1e15, "Management fee not accrued correctly");
    }

    function testNameChange() public {
        string memory oldName = vault.name();
        vault.updateName("helloToken");

        assertNotEq(oldName, vault.name(), "name did not change");
        assertEq(vault.name(), "helloToken", "name changed");

        oldName = vault.name();
        vault.updateName("newhelloToken");
        assertNotEq(oldName, vault.name(), "name did not change");
        assertEq(vault.name(), "newhelloToken", "name changed");
    }

    function testSymbolChange() public {
        string memory oldName = vault.symbol();
        vault.updateSymbol("helloToken");

        assertNotEq(oldName, vault.symbol(), "name did not change");
        assertEq(vault.symbol(), "helloToken", "name changed");

        oldName = vault.symbol();
        vault.updateSymbol("newhelloToken");
        assertNotEq(oldName, vault.symbol(), "name did not change");
        assertEq(vault.symbol(), "newhelloToken", "name changed");
    }

    function testAccrueManagementFee() public {
        vault.setManagementFeeInBps(100);
        address managementFeeRecipient = address(0x789);
        uint256 depositAmount = 1000 * 10 ** 18;

        vm.prank(user);
        vault.deposit(depositAmount, user);

        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialAccruedFees = vault.accruedManagementFees();
        uint256 initialLastFeeAccrual = vault.lastFeeAccrual();
        uint256 initialRecipientBalance = vault.balanceOf(managementFeeRecipient);

        vm.warp(initialLastFeeAccrual + 365 days);

        uint256 accruedBeforeHarvest = vault.accruedManagementFees();
        uint256 expectedFee = FixedPointMathLib.mulDivUp(initialTotalAssets * 100, 365 days, 365 days * 10_000);

        assertApproxEqAbs(
            accruedBeforeHarvest, expectedFee, 1e15, "Management fee not accrued correctly before harvest"
        );

        vault.harvestFees();

        assertEq(vault.accruedManagementFees(), 0, "Accrued fees should be reset after harvest");

        assertEq(vault.lastFeeAccrual(), block.timestamp, "lastFeeAccrual not updated");

        uint256 newTotalSupply = initialTotalAssets + expectedFee;
        uint256 expectedShares = expectedFee * initialTotalAssets / (newTotalSupply - expectedFee);
        // vault.convertToShares(expectedFee);

        assertApproxEqAbs(
            vault.balanceOf(managementFeeRecipient) - initialRecipientBalance,
            expectedShares,
            1e15,
            "Management fee recipient did not receive expected shares"
        );

        assertApproxEqAbs(
            vault.totalSupply() - initialTotalAssets,
            expectedShares,
            1e15,
            "Total supply of shares did not increase as expected"
        );
    }

    function testAccrueManagementFeeAfterMultipleDeposits() public {
        vault.setManagementFeeInBps(100);
        uint256 depositAmount = 1000 * 10 ** 18;
        address managementFeeRecipient = address(0x789);
        uint256 initialLastFeeAccrual = vault.lastFeeAccrual();
        vm.prank(user);
        vault.deposit(depositAmount, user);

        vm.warp(initialLastFeeAccrual + 182.5 days);
        vault.harvestFees();

        uint256 firstHalfYearFee = vault.balanceOf(managementFeeRecipient);

        vm.prank(user2);
        vault.deposit(depositAmount, user2);
        vm.warp(block.timestamp + 182.5 days);
        vault.harvestFees();

        uint256 secondHalfYearFee = vault.balanceOf(managementFeeRecipient) - firstHalfYearFee;
        assertTrue(
            secondHalfYearFee > firstHalfYearFee, "Second half year fee should be higher due to increased assets"
        );
    }

    function testZeroManagementFee() public {
        uint256 initialAccruedFees = vault.accruedManagementFees();
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(user);
        vault.deposit(depositAmount, user);
        vm.warp(block.timestamp + 365 days);
        vault.harvestFees();
        assertEq(vault.accruedManagementFees(), initialAccruedFees, "Should not accrue fees when fee is 0");
    }

    function testAccrueManagementFeeWithDifferentTimeIntervals() public {
        vault.setEntryFeeInBps(10);
        vault.setManagementFeeInBps(100);

        uint256 initialTotalAssets = 1000 * 10 ** 18;
        vm.prank(user);
        vault.deposit(initialTotalAssets, user);

        uint256 initialLastFeeAccrual = vault.lastFeeAccrual();
        uint256[] memory intervals = new uint256[](3);
        intervals[0] = 30 days;
        intervals[1] = 90 days;
        intervals[2] = 180 days;

        for (uint256 i = 0; i < intervals.length; i++) {
            vm.warp(initialLastFeeAccrual + intervals[i]);
            uint256 accruedBeforeHarvest = vault.accruedManagementFees();
            uint256 expectedFee = FixedPointMathLib.mulDivUp(vault.totalAssets() * 100, intervals[i], 365 days * 10_000);
            assertApproxEqAbs(
                accruedBeforeHarvest,
                expectedFee,
                1e15,
                string(abi.encodePacked("Incorrect fee accrual for interval ", uint2str(i)))
            );
            vault.harvestFees();
            assertEq(vault.accruedManagementFees(), 0, "Accrued fees should be reset after harvest");
            assertEq(vault.lastFeeAccrual(), block.timestamp, "lastFeeAccrual not updated");
            initialLastFeeAccrual = block.timestamp;
        }
    }

    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function testDepositWithdrawWithFees() public {
        uint256 depositFeeBps = 50; // 0.5% deposit fee
        uint256 managementFeeBps = 100; // 1% annual management fee
        vault.setEntryFeeInBps(depositFeeBps);
        vault.setManagementFeeInBps(managementFeeBps);

        console.log("Deposit Fee BPS:", vault.entryFeeInBps());
        console.log("Management Fee BPS:", vault.managementFeeInBps());

        uint256 initialUserBalance = asset.balanceOf(user);
        uint256 depositAmount = 100_000e18;
        uint256 _BASIS_POINT_SCALE = 10_000;

        uint256 expectedDepositFee =
            depositAmount.mulDiv(depositFeeBps, depositFeeBps + _BASIS_POINT_SCALE, Math.Rounding.Ceil);
        uint256 actualDepositAmount = depositAmount - expectedDepositFee;

        console.log("Deposit Amount:", depositAmount);
        console.log("Expected Deposit Fee:", expectedDepositFee);
        console.log("Actual Deposit Amount:", actualDepositAmount);

        vm.prank(user);
        vault.deposit(depositAmount, user);

        assertEq(
            actualDepositAmount,
            vault.totalAssets(),
            "actualDepositAmount should be equal to vault.totalAssets() after deposit"
        );

        assertEq(
            depositAmount - expectedDepositFee,
            vault.totalAssets(),
            "vault.totalAssets() should be equal to deposit amount - deposit fee"
        );

        console.log("User Balance After Deposit:", asset.balanceOf(user));
        console.log("Vault Balance After Deposit:", asset.balanceOf(address(vault)));

        assertEq(
            depositAmount,
            asset.balanceOf(address(vault)) + expectedDepositFee,
            "depositAmount != balanceOf(vault) + expectedDepositFee"
        );

        assertEq(asset.balanceOf(user), initialUserBalance - depositAmount, "User balance after deposit incorrect");

        assertEq(asset.balanceOf(address(vault)), actualDepositAmount, "Vault balance after deposit incorrect");

        uint256 initialLastFeeAccrual = vault.lastFeeAccrual();
        vm.warp(initialLastFeeAccrual + 365 days);

        console.log("Accrued Management Fees Before Harvest:", vault.accruedManagementFees());
        console.log("Share price before harvesting:", vault.convertToAssets(1e18));
        vault.harvestFees();
        console.log("Accrued Management Fees After Harvest:", vault.accruedManagementFees());
        console.log("Share price after harvesting:", vault.convertToAssets(1e18));

        uint256 expectedManagementFee =
            FixedPointMathLib.mulDivUp(vault.totalAssets() * managementFeeBps, 365 days, 365 days * 10_000);

        uint256 totalFees = expectedDepositFee + expectedManagementFee;
        uint256 shareBalance = vault.balanceOf(user);

        uint256 assetsToWithdraw = vault.convertToAssets(shareBalance);

        console.log("Share Balance Before Withdraw:", shareBalance);
        console.log("Assets to Withdraw:", assetsToWithdraw);

        uint256 userBalanceBeforeWithdraw = asset.balanceOf(user);
        console.log("User Balance Before Withdraw:", userBalanceBeforeWithdraw);

        vm.prank(user);
        vault.redeem(shareBalance, user, user);

        uint256 userBalanceAfterWithdraw = asset.balanceOf(user);
        console.log("User Balance After Withdraw:", userBalanceAfterWithdraw);
        console.log("Vault Balance After Withdraw:", asset.balanceOf(address(vault)));
        uint256 vaultBalanceAfterWithdraw = asset.balanceOf(address(vault));

        assertApproxEqAbs(
            userBalanceAfterWithdraw,
            userBalanceBeforeWithdraw + assetsToWithdraw,
            1e15,
            "User did not receive expected amount after fees"
        );

        address managementFeeRecipient = address(0x789);
        uint256 managementFeeShares = vault.balanceOf(managementFeeRecipient);
        uint256 expectedVaultBalanceAfterWithdraw = vault.convertToAssets(managementFeeShares);

        assertApproxEqAbs(
            vaultBalanceAfterWithdraw,
            expectedVaultBalanceAfterWithdraw,
            1e15,
            "Vault balance not zero after withdrawal"
        );

        uint256 actualTotalFeesPaid = initialUserBalance - userBalanceAfterWithdraw;

        assertApproxEqAbs((totalFees - actualTotalFeesPaid) * 1e18 / totalFees, 1e16, 1e16, "Net loss on expected fees");
    }
}
