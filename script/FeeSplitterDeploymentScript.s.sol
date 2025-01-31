// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";
import {FeeSplitter} from "../src/utils/FeeSplitter.sol";

contract DeployFeeSplitter is Script {
    FeeSplitter splitter;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);
        new FeeSplitter(
            0x3BcB4F5C22758b145820E1126E69d96F891d5F8b,
            0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5,
            0x7e431e5fF0EE4cAD26347C0674aFa9c30502b535
        );
        vm.stopBroadcast();
    }
}
