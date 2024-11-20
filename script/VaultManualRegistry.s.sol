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

        res.addPoolAddress(0x82Fbc848eeCeC6D0a2eBdC8A9420826AE8d2952d, "ETH", "v1");
        res.addPoolAddress(0x001DF2Cc0c3433beAd3703575F13841d2EBC078f, "USD", "v1");
        res.addPoolAddress(0x188B679c0bAf56b9838584AfaC82D713e68112fC, "ETH", "v1");

        vm.stopBroadcast();
    }
}
