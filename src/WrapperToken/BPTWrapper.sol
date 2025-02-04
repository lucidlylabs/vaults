// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20Metadata, IERC20, ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IBeetsGauge} from "./interfaces/IBeetsGauge.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../../lib/solady/src/utils/ReentrancyGuard.sol";

contract BPTWrapper is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public constant BEETS = IERC20(0x2D0E0814E62D80056181F5cd932274405966e4f0);
    IBalancerVault public constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IERC20 public constant W_S = IERC20(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
    IERC20 public constant ST_S = IERC20(0xE5DA20F15420aD15DE0fa650600aFc998bbE3955);
    bytes32 public constant beets_stS_PoolId = 0x10ac2f9dae6539e77e372adb14b1bf8fbd16b3e8000200000000000000000005;
    bytes32 public constant wS_stS_PoolId = 0x374641076b68371e69d03c417dac3e5f236c32fa000000000000000000000006;
    IBeetsGauge public immutable gauge;
    bytes32 public immutable poolId;
    IERC20 public immutable poolToken;

    struct BalancerSwapParam {
        uint256 amount;
        address assetIn;
        address assetOut;
        address recipient;
        bytes32 poolId;
        uint256 limit;
        uint256 deadline;
    }

    error BPTWrapper__NoClaimableRewards();
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _poolToken,
        address _gauge,
        bytes32 _poolId
    ) ERC20(_name, _symbol) ERC4626(IERC20(_poolToken)) {
        poolToken = IERC20(_poolToken);
        gauge = IBeetsGauge(_gauge);
        poolId = _poolId;
    }

    function totalAssets() public view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        poolToken.approve(address(gauge), assets);
        gauge.deposit(assets);

        claimAndHarvest();
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        gauge.withdraw(assets);
        super._withdraw(caller, receiver, owner, assets, shares);

        claimAndHarvest();
    }

    function claimAndHarvest() public nonReentrant {
        gauge.claim_rewards(address(this));
        uint256 beetsBalance = BEETS.balanceOf(address(this));
        if (beetsBalance == 0) revert BPTWrapper__NoClaimableRewards();

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
        if (stSBalance == 0) revert BPTWrapper__NoClaimableRewards();
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
        if (wSBalance == 0) revert BPTWrapper__NoClaimableRewards();

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = wSBalance;
        maxAmountsIn[1] = 0;
        address[] memory tokens = new address[](2);
        tokens[0] = address(W_S);
        tokens[1] = address(ST_S); // will be AnS

        _balancerJoinPool(BALANCER_VAULT, tokens, maxAmountsIn, poolId);

        uint256 poolTokenBalance = poolToken.balanceOf(address(this));
        if (poolTokenBalance == 0) revert BPTWrapper__NoClaimableRewards();

        poolToken.approve(address(gauge), poolTokenBalance);
        gauge.deposit(poolTokenBalance);
    }

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

    function _balancerJoinPool(
        IBalancerVault _balancerVault,
        address[] memory _tokens,
        uint256[] memory _maxAmountsIn,
        bytes32 _poolId
    ) internal {
        bytes memory userData = abi.encode(1, _maxAmountsIn, 0); // JoinKind: 1
        _balancerVault.joinPool(
            _poolId,
            address(this),
            address(this),
            IBalancerVault.JoinPoolRequest(
                _tokens,
                _maxAmountsIn,
                userData,
                false
            )
        );
    }
}
