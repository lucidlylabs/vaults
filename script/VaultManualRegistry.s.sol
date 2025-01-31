// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {ManualRegistry} from "../src/ManualRegistry.sol";

contract DeployManualRegistry is Script {
    ManualRegistry res;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");

        vm.startBroadcast(adminPk);
        res = new ManualRegistry();

        res.addPoolAddress(0x4bF2D4868e7c8514093a4D548B8EDF5ae4ce9Eea, "S", "v2");

        vm.stopBroadcast();
    }
}
