// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {Vault} from "../src/Vault.sol";
import {IERC20, ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";

contract VaultTest is Test {
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

        MockToken(address(asset)).mint(user, 100_000 * 10 ** decimals);
        vm.prank(user2);
        asset.approve(address(vault), type(uint256).max);

        MockToken(address(asset)).mint(user, 100_000 * 10 ** decimals);
        vm.prank(user3);
        asset.approve(address(vault), type(uint256).max);

        MockToken(address(asset)).mint(user, 100_000 * 10 ** decimals);
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
        vault.claimFees();

        uint256 expectedFee = (initialTotalAssets * 100) / 10_000;
        assertApproxEqAbs(vault.accruedManagementFees(), expectedFee, 1e15, "Management fee not accrued correctly");
    }

    function testPerformanceFeeAccounting() public {
        vault.setPerformanceFeeInBps(100);
        vault.setPerformanceFeeRecipient(address(0xABC));

        uint256 initialTime = vm.getBlockTimestamp();

        vm.prank(user);
        vault.deposit(10e18, user);

        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialUserDeposits = vault.totalUserDeposits();

        MockToken(address(asset)).mint(address(vault), 1e18);
        vm.warp(initialTime + 365 days);

        vault.harvestFees();

        uint256 accruedPerformanceFees = vault.accruedPerformanceFees();
        vault.claimFees();

        uint256 profit = vault.totalAssets() - initialUserDeposits;
        uint256 expectedPerformanceFee = profit * vault.performanceFeeInBps() / 10_000;

        assert(expectedPerformanceFee == accruedPerformanceFees);
    }
}
