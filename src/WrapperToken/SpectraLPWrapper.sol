// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626, IERC4626} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ReentrancyGuard} from "../../lib/solady/src/utils/ReentrancyGuard.sol";
import {ERC20, IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ISpectraCampaignManager} from "./interfaces/ISpectraCampaignManager.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {ISilo} from "./interfaces/ISilo.sol";
import {IBalancerVaultV3} from "./interfaces/IBalancerVaultV3.sol";
import {ISpectraPool} from "./interfaces/ISpectraPool.sol";

contract SpectraLPWrapper is ERC4626, ReentrancyGuard {
    ISpectraCampaignManager public constant CAMPAIGN_MANAGER = ISpectraCampaignManager(0x1C5Ecca381961D92b6aAF7bC1656C37021b0F1D9);
    IERC20 public constant SPECTRA = IERC20(0xb827E91C5cd4d6aCa2FC0cD93A07dB61896Af40B);
    IERC20 public constant USDCe = IERC20(0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
    IBalancerVault public constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerVaultV3 public constant BALANCER_VAULT_V3 = IBalancerVaultV3(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
    IERC20 public constant ST_S = IERC20(0xE5DA20F15420aD15DE0fa650600aFc998bbE3955);
    IERC20 public constant W_S = IERC20(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    bytes32 public constant usdce_stS_PoolId = 0x713fb5036dc70012588d77a5b066f1dd05c712d7000200000000000000000041;
    bytes32 public constant wS_stS_PoolId = 0x374641076b68371e69d03c417dac3e5f236c32fa000000000000000000000006;
    ISilo public constant silo_wS = ISilo(0x016C306e103FbF48EC24810D078C65aD13c5f11B);
    IERC20 public constant silo_wS_anS_LP = IERC20(0x944D4AE892dE4BFd38742Cc8295d6D5164c5593C);
    IERC20 public constant AN_S = IERC20(0x0C4E186Eae8aCAA7F7de1315D5AD174BE39Ec987);
    IERC4626 public constant WAN_S = IERC4626(0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70);
    ISpectraPool public constant SPECTRA_POOL = ISpectraPool(0x2386ebDE944e723Ffd9066bE23709444342d2685);
    IERC20 public immutable lpToken;
    
    struct ClaimCalldataType {
        address token;
        address rewardToken;
        uint256 earnedAmount;
        uint256 claimAmount;
        bytes32[] merkleProof;
    }

    /// @notice Parameters for Balancer swap operations
    /// @param amount Amount of tokens to swap
    /// @param assetIn Address of input token
    /// @param assetOut Address of output token
    /// @param recipient Address to receive swapped tokens
    /// @param poolId Balancer pool ID to use for swap
    /// @param limit Minimum expected output amount (slippage protection)
    /// @param deadline Transaction expiration timestamp
    struct BalancerSwapParam {
        uint256 amount;
        address assetIn;
        address assetOut;
        address recipient;
        bytes32 poolId;
        uint256 limit;
        uint256 deadline;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _lpToken
    ) ERC20(_name, _symbol) ERC4626(IERC20(_lpToken)) {
        lpToken = IERC20(_lpToken);
    }

    function deposit(uint256 assets, address receiver, ClaimCalldataType memory claimCalldata) public nonReentrant returns (uint256) {
        _compoundRewards(claimCalldata);

        uint256 shares = super.deposit(assets, receiver);
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address owner, ClaimCalldataType memory claimCalldata) public nonReentrant returns (uint256) {
        _compoundRewards(claimCalldata);

        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }

    function compoundRewards(ClaimCalldataType memory claimCalldata) public nonReentrant returns (uint256) {
        return _compoundRewards(claimCalldata);
    }

    function _compoundRewards(ClaimCalldataType memory claimCalldata) internal returns (uint256) {
        CAMPAIGN_MANAGER.claim(
            claimCalldata.token,
            claimCalldata.rewardToken,
            claimCalldata.earnedAmount,
            claimCalldata.claimAmount,
            claimCalldata.merkleProof
        );

        uint256 spectraAmount = SPECTRA.balanceOf(address(this));
        uint256 usdceAmount = USDCe.balanceOf(address(this));

        if (spectraAmount > 0) {
            // leave it for now as SPECTRA doesn't have liquidity
        }

        if (usdceAmount == 0) return 0;

        // swap USDCe to stS (beets), stS to wS (beets), wS to silo_wS (silo),
        // silo_wS to anS (beets), anS to wanS (angles), wanS to lpToken (spectra)
        _balancerSwapOut(
            BALANCER_VAULT,
            IBalancerVault.SwapKind.GIVEN_IN,
            BalancerSwapParam({
                amount: usdceAmount,
                assetIn: address(USDCe),
                assetOut: address(ST_S),
                recipient: address(this),
                poolId: usdce_stS_PoolId,
                limit: 0,
                deadline: block.timestamp
            })
        );

        uint256 stSBalance = ST_S.balanceOf(address(this));
        if (stSBalance == 0) return 0;

        _balancerSwapOut(
            BALANCER_VAULT,
            IBalancerVault.SwapKind.GIVEN_IN,
            BalancerSwapParam({
                amount: stSBalance,
                assetIn: address(ST_S),
                assetOut: address(W_S),
                recipient: address(this),
                poolId: wS_stS_PoolId,
                limit: 0,
                deadline: block.timestamp
            })
        );

        uint256 wSBalance = W_S.balanceOf(address(this));
        if (wSBalance == 0) return 0;

        W_S.approve(address(silo_wS), wSBalance);
        silo_wS.deposit(wSBalance, address(this));

        uint256 siloWSBalance = silo_wS.balanceOf(address(this));
        if (siloWSBalance == 0) return 0;

        silo_wS.approve(address(BALANCER_VAULT_V3), siloWSBalance);
        _balancerSwapOutV3(
            IBalancerVaultV3.VaultSwapParams({
                kind: IBalancerVaultV3.SwapKind.EXACT_IN,
                pool: address(silo_wS_anS_LP),
                tokenIn: address(silo_wS),
                tokenOut: address(AN_S),
                amountGivenRaw: siloWSBalance,
                limitRaw: 0,
                userData: ""
            })
        );
        uint256 anSBalance = AN_S.balanceOf(address(this));
        if (anSBalance == 0) return 0;

        AN_S.approve(address(WAN_S), anSBalance);
        WAN_S.deposit(anSBalance, address(this));
        uint256 wanSBalance = WAN_S.balanceOf(address(this));
        if (wanSBalance == 0) return 0;

        WAN_S.approve(address(SPECTRA_POOL), wanSBalance);
        // need to test
        SPECTRA_POOL.add_liquidity(
            [wanSBalance, 0],
            0,
            false,
            address(this)
        );
        uint256 lpTokenBalance = lpToken.balanceOf(address(this));
        return lpTokenBalance;
    }

    /// @notice Internal function to execute Balancer swaps
    /// @param _balancerVault Reference to Balancer vault contract
    /// @param _swap Type of swap to perform (GIVEN_IN or GIVEN_OUT)
    /// @param _param Structured swap parameters
    /// @return amountCalculated Actual amount of output tokens received
    function _balancerSwapOut(
        IBalancerVault _balancerVault,
        IBalancerVault.SwapKind _swap,
        BalancerSwapParam memory _param
    ) internal returns (uint256) {
        IERC20(_param.assetIn).approve(address(_balancerVault), _param.amount);
        return _balancerVault.swap(
            IBalancerVault.SingleSwap(
                _param.poolId,
                _swap,
                _param.assetIn,
                _param.assetOut,
                _param.amount,
                ""
            ),
            IBalancerVault.FundManagement(
                address(this),
                false,
                payable(_param.recipient),
                false
            ),
            _param.limit,
            _param.deadline
        );
    }

    function _balancerSwapOutV3(
        IBalancerVaultV3.VaultSwapParams memory _param
    ) internal returns (uint256, uint256, uint256) {
        IERC20(_param.tokenIn).approve(address(BALANCER_VAULT_V3), _param.amountGivenRaw);
        return BALANCER_VAULT_V3.swap(_param);
    }
}
