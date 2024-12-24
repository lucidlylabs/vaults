// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";

import {Pool} from "../src/Pool.sol";
import {SwapAdapter} from "../src/SwapAdapters/SwapAdapter.sol";
import {SwapAdapter} from "../src/SwapAdapters/EthenaVaultSwapAdapters/SwapAdapter.sol";

contract SwapAdapterTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("http://127.0.0.1:8545"));
    }
}
