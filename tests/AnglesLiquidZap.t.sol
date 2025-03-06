// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "../lib/forge-std/src/Test.sol";

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";

import {PoolV2} from "../src/Poolv2.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";
import {Aggregator} from "../src/Aggregator.sol";

import {IBalancerVault} from "../src/Interfaces/IBalancerVault.sol";
import {IBalancerVaultV3} from "../src/Interfaces/IBalancerVaultV3.sol";

import {SiloBorrowableWsRateProvider} from "../src/RateProvider/angles-liquid/SiloBorrowableWsRateProvider.sol";
import {BeetsLpRateProvider} from "../src/RateProvider/angles-liquid/BeetsLpRateProvider.sol";
import {SpectraLpRateProvider} from "../src/RateProvider/angles-liquid/SpectraLpRateProvider.sol";

contract ZapTest is Test {
    PoolV2 pool = PoolV2(0x033f4A109Fc11a11d3AFB92dCA0AB6C30BB3c722);
    PoolToken poolToken = PoolToken(0x88cf500dA90aC0351A5b886b73678D183bc3bb7D);
    Vault vault = Vault(0x15E96CDecA34B9DE1B31586c1206206aDb92E69D);
    address admin = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;
    uint256 public PRECISION = 1e18;

    ERC20 public ANS = ERC20(0x0C4E186Eae8aCAA7F7de1315D5AD174BE39Ec987);
    ERC20 public WS = ERC20(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    ERC20 public WANS = ERC20(0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70);
    ERC20 public BWS25 = ERC20(0x016C306e103FbF48EC24810D078C65aD13c5f11B); // silo borrowable wS in market 25
    ERC20 public SLP = ERC20(0xEc81ee88906ED712deA0a17A3Cd8A869eBFA89A0); // spectra wans market LP token
    ERC20 public BPT = ERC20(0x944D4AE892dE4BFd38742Cc8295d6D5164c5593C); // beets pool token

    IBalancerVault public constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerVaultV3 public constant BALANCER_VAULT_V3 = IBalancerVaultV3(0xbA1333333333a1BA1108E8412f11850A5C319bA9);

    address[] public rateProviders = new address[](4);

    function setUp() public {
        vm.selectFork(vm.createFork("http://127.0.0.1:8545"));

        IRateProvider rp2 = new SiloBorrowableWsRateProvider();
        IRateProvider rp3 = new BeetsLpRateProvider();
        rateProviders[0] = pool.rateProviders(0);
        rateProviders[1] = pool.rateProviders(1);
        rateProviders[2] = address(rp2);
        rateProviders[3] = address(rp3);

        deal(address(BWS25), admin, 200e21); // @dev 1 wS ~= 1000 bws25
        // deal(address(BPT), admin, 200e18);

        vm.startPrank(admin);
        BWS25.approve(address(pool), 200e21);

        // add bwS25 to Pool
        pool.addToken(
            address(BWS25), // token address
            rateProviders[2], // rate provider address
            PRECISION / 100, // weight
            0, // lower
            PRECISION, // upper
            200e21, // amount
            10_000e18, // ampl
            0, // minlp
            admin // receiver
        );

        pool.removeLiquiditySingle(1, poolToken.balanceOf(admin), 0, admin);

        deal(address(BWS25), admin, 500e21); // @dev 1 wS ~= 1000 bws25
        BWS25.approve(address(BALANCER_VAULT_V3), 250e21);
        ANS.approve(address(BALANCER_VAULT_V3), 250e18);

        uint256[] memory amountsIn = new uint256[](2);
        address[] memory tokens = new address[](2);
        amountsIn[0] = 250e21;
        amountsIn[1] = 250e18;
        tokens[0] = address(BWS25);
        tokens[1] = address(ANS);

        // add liquidity
        BALANCER_VAULT_V3.addLiquidity(
            IBalancerVaultV3.AddLiquidityParams({
                pool: address(BPT),
                to: admin,
                maxAmountsIn: amountsIn,
                minBptAmountOut: 0,
                kind: IBalancerVaultV3.AddLiquidityKind.UNBALANCED,
                userData: ""
            })
        );

        vm.stopPrank();
    }

    function test__Hello() public {
        console.log("hello");
    }
}
