// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {IRateProvider} from "../src/RateProvider/IRateProvider.sol";
import {RingsVaultRateProvider} from "../src/RateProvider/sonic-rings/RingsVaultRateProvider.sol";
import {PoolOwner} from "../src/PoolOwner.sol";

contract RingsVaultDeploymentScript is Script {
    PoolToken poolToken;
    Pool pool;
    Vault vault;
    PoolOwner ownerContract;
    IRateProvider rateProvider;

    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private constant USDC_BRIDGED = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address private constant SCUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address private constant SCUSD_USDC_REDSTONE_FEED = 0xb81131B6368b3F0a83af09dB4E39Ac23DA96C2Db;

    MockToken token0 = MockToken(USDC_BRIDGED);
    MockToken token1 = MockToken(SCUSD);

    uint256 private PRECISION = 1e18;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);

        rateProvider = new RingsVaultRateProvider();

        address[] memory tokens = new address[](2);
        uint256[] memory weights = new uint256[](2);
        address[] memory rateProviders = new address[](2);

        // tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);

        // set weights
        weights[0] = 40 * PRECISION / 100;
        weights[1] = 60 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(rateProvider);
        rateProviders[1] = address(rateProvider);

        address admin = vm.addr(adminPk);
        poolToken = new PoolToken("**", "**", 18, admin);
        pool = new Pool(address(poolToken), 450 * PRECISION, tokens, rateProviders, weights, admin);
        vault = new Vault(address(poolToken), "lucidly rings vault share", "lcdRingsUSD", 100, admin, admin);
        ownerContract = new PoolOwner(address(pool));

        poolToken.setPool(address(pool));
        pool.setVaultAddress(address(vault));
        pool.setSwapFeeRate(3 * PRECISION / 10_000); // 3bps
        vault.setDepositFeeInBps(100);
        vault.setProtocolFeeAddress(admin);

        vm.stopBroadcast();
    }
}

contract RingsVaultSeedingScript is Script {
    PoolToken poolToken = PoolToken(0xa93C9411f8FeCF5E6aCd81ECd99a71C165d48c4D);
    Pool pool = Pool(0xc8291D518fE771B5612Ecc0D6A99D5DC03db3DD8);
    Vault vault = Vault(0xedEa2647CfE580c9B6f2148C270f9aaE6B08bcA5);
    PoolOwner ownerContract = PoolOwner(0x2210A9357D51fF909EAa43570b3F1275E76cB6d6);
    IRateProvider rateProvider = IRateProvider(0xa633C15E09cA2a8DBB6CD52aae915a3b379dEEb3);

    address private ADMIN_ADDRESS = 0x1b514df3413DA9931eB31f2Ab72e32c0A507Cad5;

    address private constant USDC_BRIDGED = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address private constant SCUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address private constant SCUSD_USDC_REDSTONE_FEED = 0xb81131B6368b3F0a83af09dB4E39Ac23DA96C2Db;

    MockToken token0 = MockToken(USDC_BRIDGED);
    MockToken token1 = MockToken(SCUSD);

    uint256 private PRECISION = 1e18;

    function run() public {
        uint256 adminPk = vm.envUint("PRIVATE_KEY_1");
        vm.startBroadcast(adminPk);
        address admin = vm.addr(adminPk);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 4 * 10 ** (token0.decimals());
        amounts[1] = 6 * 10 ** (token1.decimals());

        require(token0.approve(address(pool), type(uint256).max), "pool cannot spend USDC.e");
        require(token1.approve(address(pool), type(uint256).max), "pool cannot spend scUSD");
        uint256 lp = pool.addLiquidity(amounts, 0, admin);
        require(poolToken.approve(address(vault), type(uint256).max), "vault cannot spend poolToken");
        vault.deposit(lp, admin);

        vm.stopBroadcast();
    }
}
