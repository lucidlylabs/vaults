// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {Aggregator} from "../src/Aggregator.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {PoolV2} from "../src/Poolv2.sol";

contract Zap is Script {
    Aggregator agg;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);
        agg = new Aggregator();
        vm.stopBroadcast();
    }
}

// contract ZapAndDeposit is Script {
//     Aggregator agg = Aggregator(0xA342a00f66783A4ca59d0c0716f2d24f593b9070);
//     address private constant STS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;
//     address private constant router = 0xba7bAC71a8Ee550d89B827FE6d67bc3dCA07b104;
//
//     function run() public {
//         uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
//         address admin = vm.addr(adminPk);
//         vm.startBroadcast(adminPk);
//
//         require(MockToken(STS).approve(address(agg), type(uint256).max), "could approve router as spender");
//
//         bytes memory routerCalldata =
//             hex"73fc44570000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000013401170020a342a00f66783a4ca59d0c0716f2d24f593b9070e5da20f15420ad15de0fa650600afc998bbe395529219dd400f2bf60e5a23d13be72b486d4038894e000d4e800d9f800ddc000df1944834d282f1cc873e782c418cf9a89dbe0fe913f71fdbded65ff4f695a650d48cf02f0f25158e73179373e273260ba2382e4966641079acf75710ed8ec85db1b0000e06790e555e80951baf800c00de0b6b3a7640000060300deba12222222228d8ba445958a75a0704d566bf2c802005c0200eb0300de52bbbe29f8e0713fb5036dc70012588d77a5b066f1dd05c712d7000200000000000000000041f8c001010803010c0603008a02004803008a03008a0300d304010e002003008a02005c0200700300de03012e03008a02000000e700eb000001000000ff010800000000200130015d00eb000000000000000000000000";
//
//         uint256 shares = agg.executeZapAndDeposit(
//             STS,
//             1 ether,
//             0,
//             admin,
//             0,
//             0xc8291D518fE771B5612Ecc0D6A99D5DC03db3DD8,
//             0xba7bAC71a8Ee550d89B827FE6d67bc3dCA07b104,
//             routerCalldata
//         );
//
//         vm.stopBroadcast();
//     }
// }

// contract TestMagpieCall is Script {
//     Aggregator agg = Aggregator(0xFB644ceA02886dDc1b56d6D9FECE811C941d41CD);
//     address private constant router = 0xba7bAC71a8Ee550d89B827FE6d67bc3dCA07b104;
//
//     function run() public {
//         uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
//         address admin = vm.addr(adminPk);
//         vm.startBroadcast(adminPk);
//
//         require(
//             MockToken(0xE5DA20F15420aD15DE0fa650600aFc998bbE3955).approve(router, type(uint256).max),
//             "could approve router as spender"
//         );
//
//         bytes memory routerCalldata =
//             hex"73fc445700000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000139011c00201b514df3413da9931eb31f2ab72e32c0a507cad5e5da20f15420ad15de0fa650600afc998bbe395529219dd400f2bf60e5a23d13be72b486d4038894e000d4e800d9f800ddc000dfcdcef9143ec4be47b37f3bbd9b5977053388ed33cd15b5bed2f915a4bafd8d6e039c99085e9eae96570ab91a8980af4f4f520b83371116314e760504bcfd314e1c0000e06790e096e809dcadf800c00de0b6b3a7640000060300deba12222222228d8ba445958a75a0704d566bf2c802005c0200eb0300de52bbbe29f8e0e06790e098df49944d79b4032e244063ebfe413a3179d6b2e7000100000000000000000084f8c001010803010c0603008a02004803008a03008a03010e040113002003008a02005c0200700300de03013303008a02000000e700eb000001000000ff010800000000200135016200eb00000000000000";
//
//         (bool success, bytes memory data) = router.call(routerCalldata);
//
//         vm.stopBroadcast();
//     }
// }
