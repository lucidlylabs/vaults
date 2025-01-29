// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {Aggregator} from "../src/Aggregator.sol";

import {PoolV2} from "../src/Poolv2.sol";
//
// contract AggregatorDeploymentScript is Script {
//     Aggregator agg;
//     address constant MAGPIEROUTER = 0x15392211222B46A0eA85a9A800830486D144848D;
//
//     address constant pool = 0x82Fbc848eeCeC6D0a2eBdC8A9420826AE8d2952d;
//
//     address private ADMIN_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
//
//     address constant receiver = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
//
//     function run() public {
//         vm.startBroadcast(adminPk);
//         agg = new Aggregator();
//         console.log(address(agg));
//         vm.stopBroadcast();
//     }
// }
