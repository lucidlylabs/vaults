// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {console} from "../lib/forge-std/src/console.sol";

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SpectraLPWrapper} from "../src/WrapperToken/SpectraLPWrapper.sol";
import {ISpectraCampaignManager} from "../src/WrapperToken/interfaces/ISpectraCampaignManager.sol";

// contract SpectraLPWrapperTest is Test {
//     SpectraLPWrapper public wrapper;

//     address public constant LP_WAN_S = 0xEc81ee88906ED712deA0a17A3Cd8A869eBFA89A0;
//     address public constant WAN_S = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;
//     IERC20 public constant USDCe = IERC20(0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
//     ISpectraCampaignManager public constant CAMPAIGN_MANAGER = ISpectraCampaignManager(0x1C5Ecca381961D92b6aAF7bC1656C37021b0F1D9);

//     // wanS Whale
//     address public constant WAN_S_WHALE = 0x62a4A8f9f5F3AaE9Ee9CEE780285A0D501C12d09;
//     address public constant SCUSD_WHALE = 0xaa17879e7cac3AEE12D6aa568691e638EF0C57f0;
    
//     // Test User
//     address public user = makeAddr("user");

//     function setUp() public {
//         vm.createSelectFork(vm.rpcUrl("https://rpc.ankr.com/sonic_mainnet"));

//         // Deploy SpectraLPWrapper
//         wrapper = new SpectraLPWrapper(
//             "Wrapped Spectra",
//             "wSPECTRA",
//             LP_WAN_S
//         );
//     }

//     function testClaim() public {

//         vm.startPrank(SCUSD_WHALE);
//         bytes32[] memory merkleProof = new bytes32[](9);
//         merkleProof[0] = bytes32(0x740ce7fc766398d9dcb6b22883009ad343437b0b7e8cf88f7299ee8383ae30af);
//         merkleProof[1] = bytes32(0x524fefa6cbaf1fc479088aae3fa45e3d9960da48cb28ca79ffbc6ec22f8bf5a4);
//         merkleProof[2] = bytes32(0x927ef7e9939605d41f2e8a6afbd54141ea5fd7cf81f6fd9f35fddbd9324fcfa5);
//         merkleProof[3] = bytes32(0x7569a239affff88d139d77637e6efa3cbb04afa118002b150743776d4c2863da);
//         merkleProof[4] = bytes32(0x784e649940d16eb40967a272b2ecf88c94ad33c3eaf8236a1a16cb385926108b);
//         merkleProof[5] = bytes32(0x43a8ffc334c3053334d90ca51aae51fdcc5aed20e823a950c35b5a1115e5e40b);
//         merkleProof[6] = bytes32(0x57f6554bc9209ce2e9f6160adbf9f2dbf377e873e9d8e83e206bf51debb67b6c);
//         merkleProof[7] = bytes32(0xa882489e1d89347abf844f72d24cd8afce81f73963444222a0252215d7915abf);
//         merkleProof[8] = bytes32(0xbf1aab61100d9a3726464d13f7a462eb8819b6c4c32aaa725dbbf031d375999f);

//         console.log("Before claim: ", USDCe.balanceOf(SCUSD_WHALE));

//         CAMPAIGN_MANAGER.claim(
//             address(0x7006BFCa68C46A3bf98B41D0Bd5665846A99440d),
//             address(0x29219dd400f2Bf60E5a23d13Be72B486D4038894),
//             86733720,
//             86733720,
//             merkleProof
//         );

//         console.log("After claim: ", USDCe.balanceOf(SCUSD_WHALE));
//         vm.stopPrank();
//     }

//     // function testCompoundRewards() public {
//     //     bytes32[] memory merkleProof = new bytes32[](0);
//     //     wrapper.compoundRewards(SpectraLPWrapper.ClaimCalldataType(
//     //         address(0x7006BFCa68C46A3bf98B41D0Bd5665846A99440d),
//     //         address(0x29219dd400f2Bf60E5a23d13Be72B486D4038894),
//     //         86733720,
//     //         86733720,
//     //         merkleProof
//     //     ));
//     // }
// }
