// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";
import {Aggregator} from "../src/Aggregator.sol";

contract AggregatorDeploymentScript is Script {
    Aggregator agg;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);
        agg = new Aggregator();
        vm.stopBroadcast();
    }
}
