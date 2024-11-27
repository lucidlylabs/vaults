// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {PoolOwner} from "../src/PoolOwner.sol";

contract PoolOwnerDeploymentScript is Script {
    PoolOwner ownerContract;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);
        ownerContract = new PoolOwner(0x001DF2Cc0c3433beAd3703575F13841d2EBC078f);
        vm.stopBroadcast();
    }
}
