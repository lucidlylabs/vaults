// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {PendleLPWrapper} from "../src/WrapperToken/PendleLPWrapper.sol";

contract DeployPendleLPWrapper is Script {
    // Mainnet Pendle Market address
    address public constant LP_SUSDA = 0xD75FC2B1ca52e72163787D1C370650F952E75DD7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_1");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy wrapper with same parameters as test
        PendleLPWrapper wrapper = new PendleLPWrapper("Wrapped Pendle LP-sUSDa", "wPendle LP-sUSDa", LP_SUSDA);

        vm.stopBroadcast();
    }
}
