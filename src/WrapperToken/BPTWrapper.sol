// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20Metadata, IERC20, ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../../lib/solady/src/utils/ReentrancyGuard.sol";
import {IBeetsGauge} from "./interfaces/IBeetsGauge.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {IBalancerVaultV3} from "./interfaces/IBalancerVaultV3.sol";
import {ISilo} from "./interfaces/ISilo.sol";
import {console} from "../../lib/forge-std/src/console.sol";

/// @title BPTWrapper - Balancer Pool Token Wrapper with Yield Compounding
/// @notice ERC4626-compatible vault that wraps Balancer pool tokens and automatically compounds rewards
contract BPTWrapper is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public constant BEETS = IERC20(0x2D0E0814E62D80056181F5cd932274405966e4f0);
    IBalancerVault public constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerVaultV3 public constant BALANCER_VAULT_V3 = IBalancerVaultV3(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
    IERC20 public constant AN_S = IERC20(0x0C4E186Eae8aCAA7F7de1315D5AD174BE39Ec987);
    IERC20 public constant W_S = IERC20(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    ISilo public constant silo_wS = ISilo(0x016C306e103FbF48EC24810D078C65aD13c5f11B);
    IERC20 public constant ST_S = IERC20(0xE5DA20F15420aD15DE0fa650600aFc998bbE3955);
    bytes32 public constant beets_stS_PoolId = 0x10ac2f9dae6539e77e372adb14b1bf8fbd16b3e8000200000000000000000005;
    bytes32 public constant wS_stS_PoolId = 0x374641076b68371e69d03c417dac3e5f236c32fa000000000000000000000006;

    IBeetsGauge public immutable gauge;
    IERC20 public immutable poolToken;

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

    /// @notice Emitted when rewards are compounded
    /// @param bptAdded Amount of BPT added to the gauge
    event RewardsCompounded(
        uint256 bptAdded
    );

    error BPTWrapper__NoClaimableRewards();
    
    /// @notice Initializes the BPT wrapper contract
    /// @param _name Name for the ERC20 share token
    /// @param _symbol Symbol for the ERC20 share token
    /// @param _poolToken Address of the underlying BPT token
    /// @param _gauge Address of the Beets gauge contract
    constructor(
        string memory _name,
        string memory _symbol,
        address _poolToken,
        address _gauge
    ) ERC20(_name, _symbol) ERC4626(IERC20(_poolToken)) {
        poolToken = IERC20(_poolToken);
        gauge = IBeetsGauge(_gauge);
    }

    function totalAssets() public view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        compoundRewards();
        
        super._deposit(caller, receiver, assets, shares);
        poolToken.approve(address(gauge), assets);
        gauge.deposit(assets);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        compoundRewards();
        
        gauge.withdraw(assets);
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Compounds earned rewards back into the vault
    /// @dev Claims rewards → Converts BEETS → ST_S → W_S → SILO_W_S → BPT → Deposits to gauge
    /// @dev Emits RewardsCompounded event with conversion amounts
    function compoundRewards() public nonReentrant returns (uint256) {
        gauge.claim_rewards(address(this));
        uint256 beetsBalance = BEETS.balanceOf(address(this));
        if (beetsBalance == 0) return 0;

        _balancerSwapOut(
            BALANCER_VAULT,
            IBalancerVault.SwapKind.GIVEN_IN,
            BalancerSwapParam({
                amount: beetsBalance,
                assetIn: address(BEETS),
                assetOut: address(ST_S),
                recipient: address(this),
                poolId: beets_stS_PoolId,
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

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = siloWSBalance;
        maxAmountsIn[1] = 0;
        address[] memory tokens = new address[](2);
        tokens[0] = address(silo_wS);
        tokens[1] = address(AN_S);

        silo_wS.approve(address(BALANCER_VAULT_V3), siloWSBalance);
        BALANCER_VAULT_V3.addLiquidity(
            IBalancerVaultV3.AddLiquidityParams({
                pool: address(poolToken),
                to: address(this),
                maxAmountsIn: maxAmountsIn,
                minBptAmountOut: 0,
                kind: IBalancerVaultV3.AddLiquidityKind.UNBALANCED,
                userData: ""
            })
        );

        uint256 poolTokenBalance = poolToken.balanceOf(address(this));
        if (poolTokenBalance == 0) return 0;

        poolToken.approve(address(gauge), poolTokenBalance);
        gauge.deposit(poolTokenBalance);

        emit RewardsCompounded(poolTokenBalance);
        return poolTokenBalance;
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
}
