import * as weiroll from "@weiroll/weiroll.js";
import hre, { ethers, network } from "hardhat";
import CURVE_LP_ABI from "../abis/curveLpAbi";
import ERC20_ABI from "../abis/erc20Abi";

describe('Poolv2', function () {
  let jake: any;
  let alice: any;
  let bob: any;

  const PRECISION = hre.ethers.parseUnits("1", 18);
  const INITIAL_AMOUNT = hre.ethers.parseUnits("1000", 18);

  before(async () => {
  });

  it("Should remove a token from the pool", async () => {
    [jake, alice, bob] = await hre.ethers.getSigners();

    const ERC20 = await hre.ethers.getContractFactory("MockToken");
    const SUSDE = ERC20.attach("0x9D39A5DE30e57443BfF2A8307A4256c8797A3497");
    const SDAISUSDE_CURVE = ERC20.attach("0x167478921b907422F8E88B43C4Af2B8BEa278d3A");
    const YPTSUSDE = ERC20.attach("0x57fC2D9809F777Cd5c8C433442264B6E8bE7Fce4");
    const GAUNTLET_USDC_PRIME = ERC20.attach("0x5D2F4460Ac3514AdA79f5D9838916E508Ab39Bb7");

    const MockRateProvider = await hre.ethers.getContractFactory("MockRateProvider");
    const mrp = await MockRateProvider.deploy();
    const mrpAddress = await mrp.getAddress();

    const PoolToken = await hre.ethers.getContractFactory("PoolToken");
    const poolToken = await PoolToken.deploy("PoolToken1", "XYZ-PT1", 18, await jake.getAddress());
    const poolTokenAddress = await poolToken.getAddress();

    const Pool = await hre.ethers.getContractFactory("PoolV2");
    const averageWeight = PRECISION / BigInt(4);
    const pool = await Pool.deploy(
      poolTokenAddress,
      PRECISION * BigInt(10),
      [
        "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497",
        "0x167478921b907422F8E88B43C4Af2B8BEa278d3A",
        "0x57fC2D9809F777Cd5c8C433442264B6E8bE7Fce4",
        "0xdd0f28e19C1780eb6396170735D45153D261490d"
      ],
      [
        mrpAddress,
        mrpAddress,
        mrpAddress,
        mrpAddress
      ],
      [
        averageWeight,
        averageWeight,
        averageWeight,
        averageWeight
      ],
      await jake.getAddress()
    );

    await poolToken.setPool(pool.address);

    const susdeWhaleAddress = "0x31173Ed183e5a9450C3671018ec4d770c8A8bF18";
    const sdaiSusdeCurveWhaleAddress = "0xd3E0d660d8Fab05B34CCb7Fe7681628d9a46c675";
    const yptSusdeWhaleAddress = "0x8ee796309494a10B4170F8912613Ee78C75a3430";
    const gauntletUsdcPrimeWhaleAddress = "";

    // impersonating whale addresses
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [susdeWhaleAddress],
    });
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [sdaiSusdeCurveWhaleAddress],
    });
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [yptSusdeWhaleAddress],
    });
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [gauntletUsdcPrimeWhaleAddress],
    });

    const susdeWhaleSigner = await hre.ethers.getSigners(susdeWhaleAddress);
    const sdaiSusdeCurveWhaleSigner = await hre.ethers.getSigners(sdaiSusdeCurveWhaleAddress);
    const yptSusdeWhaleSigner = await hre.ethers.getSigners(yptSusdeWhaleAddress);
    const gauntletUsdcPrimeWhaleSigner = await hre.ethers.getSigners(gauntletUsdcPrimeWhaleAddress);

    // Distribute tokens to Jake
    await SUSDE.connect(susdeWhaleSigner).transfer(await jake.getAddress(), INITIAL_AMOUNT);
    await SDAISUSDE_CURVE.connect(sdaiSusdeCurveWhaleSigner).transfer(await jake.getAddress(), INITIAL_AMOUNT);
    await YPTSUSDE.connect(yptSusdeWhaleSigner).transfer(await jake.getAddress(), INITIAL_AMOUNT);
    await GAUNTLET_USDC_PRIME.connect(gauntletUsdcPrimeWhaleSigner).transfer(await jake.getAddress(), INITIAL_AMOUNT);

    // Approve Pool
    await SUSDE.connect(jake).approve(pool.address, INITIAL_AMOUNT);
    await SDAISUSDE_CURVE.connect(jake).approve(pool.address, INITIAL_AMOUNT);
    await YPTSUSDE.connect(jake).approve(pool.address, INITIAL_AMOUNT);
    await GAUNTLET_USDC_PRIME.connect(jake).approve(pool.address, INITIAL_AMOUNT);

    // Add liquidity
    await pool.connect(jake).addLiquidity(
        [INITIAL_AMOUNT, INITIAL_AMOUNT, INITIAL_AMOUNT, INITIAL_AMOUNT],
        0,
        await jake.getAddress()
    );

    const SDAISUSDE_CURVE_ADDRESS = "0x167478921b907422F8E88B43C4Af2B8BEa278d3A";
    const POOL_ADDRESS = "0xec970a39fc83A492103Ed707a290e050E2DA375c";

    const susdeContract = new ethers.Contract(SUSDE, ERC20_ABI);
    const susdeWeiroll = weiroll.Contract.createContract(susdeContract);

    const curveLpContract = new ethers.Contract(SDAISUSDE_CURVE_ADDRESS, CURVE_LP_ABI);
    const curveLpWeiroll = weiroll.Contract.createContract(curveLpContract);

    const planner = new weiroll.Planner();

    const balance = await susdeContract.balanceOf(POOL_ADDRESS);

    planner.add(susdeWeiroll.approve(SDAISUSDE_CURVE, balance));
    planner.add(curveLpWeiroll.add_liquidity([0, balance], 0));

    const { commands, state } = planner.plan();

    await pool.connect(jake).removeToken(0, commands);

    // Stop impersonating the whale accounts
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [susdeWhaleAddress],
    });
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [sdaiSusdeCurveWhaleAddress],
    });
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [yptSusdeWhaleAddress],
    });
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [gauntletUsdcPrimeWhaleAddress],
    });
  });
});
