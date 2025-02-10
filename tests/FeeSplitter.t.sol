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
}
