// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {PoolOwner} from "../src/PoolOwner.sol";
import {Pool} from "../src/Pool.sol";

contract PoolOwnerDeploymentScript is Script {
    PoolOwner ownerContract;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);
        ownerContract = new PoolOwner(0x001DF2Cc0c3433beAd3703575F13841d2EBC078f);
        vm.stopBroadcast();
    }
}

contract GrantMonitorRoleScript is Script {
    address private poolMonitor = 0x8ee56e4F5Ae93c5B8c18C4c54C923E7A9af5E3dD;
    PoolOwner ownerContractUSDeVault = PoolOwner(0x6Cb9b40603Cf268A06187B2FA67e3a3DF941612A);
    PoolOwner ownerContractSwBtcVault = PoolOwner(0x2FF077876860E9edf05a8cfA692DAA0096C4e109);
    PoolOwner ownerContractPufVault = PoolOwner(0x2ca1Da5915da19f8417be961D6CC21232778530b);

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);
        ownerContractUSDeVault.grantRoles(poolMonitor, ownerContractUSDeVault.ROLE_POOL_MONITOR());

        Pool swBtcPool = Pool(0xC4Ab94075b209fe18759208fa0355C5037F82bdD);
        swBtcPool.transferOwnership(address(ownerContractSwBtcVault));
        ownerContractSwBtcVault.grantRoles(poolMonitor, ownerContractSwBtcVault.ROLE_POOL_MONITOR());
        vm.stopBroadcast();

        uint256 adminPkPufVault = vm.envUint("ADMIN_KEY");
        vm.startBroadcast(adminPkPufVault);
        Pool pufEthPool = Pool(0x82Fbc848eeCeC6D0a2eBdC8A9420826AE8d2952d);
        pufEthPool.transferOwnership(address(ownerContractPufVault));
        vm.stopBroadcast();

        vm.startBroadcast(adminPk);
        ownerContractPufVault.grantRoles(poolMonitor, ownerContractPufVault.ROLE_POOL_MONITOR());
        vm.stopBroadcast();
    }
}
