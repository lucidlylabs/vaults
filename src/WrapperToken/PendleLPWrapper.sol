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
import {IPendleRouterV4} from "./interfaces/IPendleRouterV4.sol";
import {IPendleMarket} from "./interfaces/IPendleMarket.sol";
import {IUniswapSwapRouter02} from "./interfaces/IUniswapSwapRouter02.sol";
import {IAvalonSaving} from "./interfaces/IAvalonSaving.sol";
import {console} from "forge-std/console.sol";

contract PendleLPWrapper is ERC4626, ReentrancyGuard {
    IERC20 public constant PENDLE = IERC20(0x808507121B80c02388fAd14726482e061B8da827);
    IERC20 public constant USDa = IERC20(0x8A60E489004Ca22d775C5F2c657598278d17D9c2);
    IERC20 public constant SUSDa = IERC20(0x2B66AAdE1e9C062FF411bd47C44E0Ad696d43BD9);
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    IPendleRouterV4 public constant PENDLE_ROUTER = IPendleRouterV4(0x888888888889758F76e7103c6CbF23ABbF58F946);
    IUniswapSwapRouter02 public constant UNISWAP_ROUTER =
        IUniswapSwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    IAvalonSaving public constant AVALON_SAVING = IAvalonSaving(0x01e3cc8E17755989ad2CAFE78A822354Eb5DdFA6);

    IPendleMarket public immutable lpToken;

    // EmptySwap means no swap aggregator is involved
    IPendleRouterV4.SwapData public emptySwap;

    // EmptyLimit means no limit order is involved
    IPendleRouterV4.LimitOrderData public emptyLimit;

    constructor(string memory _name, string memory _symbol, address _lpToken)
        ERC20(_name, _symbol)
        ERC4626(IERC20(_lpToken))
    {
        lpToken = IPendleMarket(_lpToken);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _compoundRewards();

        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _compoundRewards();

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function compoundRewards() public nonReentrant returns (uint256) {
        return _compoundRewards();
    }

    function _compoundRewards() internal returns (uint256) {
        (address SY,, address YT) = lpToken.readTokens();

        address[] memory sys = new address[](1);
        sys[0] = SY;
        address[] memory yts = new address[](1);
        yts[0] = YT;
        address[] memory markets = new address[](1);
        markets[0] = address(lpToken);
        PENDLE_ROUTER.redeemDueInterestAndRewards(address(this), sys, yts, markets);

        uint256 pendleBalance = PENDLE.balanceOf(address(this));
        if (pendleBalance == 0) return 0;

        bytes memory path =
            abi.encodePacked(address(PENDLE), uint24(3000), WETH, uint24(3000), USDT, uint24(100), address(USDa));

        _uniswapV3Swap(address(PENDLE), pendleBalance, path);
        uint256 usdaBalance = USDa.balanceOf(address(this));
        if (usdaBalance == 0) return 0;
        USDa.approve(address(AVALON_SAVING), usdaBalance);
        AVALON_SAVING.mint(usdaBalance);

        uint256 susdaBalance = SUSDa.balanceOf(address(this));
        SUSDa.approve(address(PENDLE_ROUTER), susdaBalance);
        PENDLE_ROUTER.addLiquiditySingleToken(
            address(this),
            address(lpToken),
            0,
            IPendleRouterV4.ApproxParams(0, type(uint256).max, 0, 256, 1e14),
            IPendleRouterV4.TokenInput(address(SUSDa), susdaBalance, address(SUSDa), address(0), emptySwap),
            emptyLimit
        );

        uint256 lpBalance = lpToken.balanceOf(address(this));
        return lpBalance;
    }

    function _uniswapV3Swap(address tokenIn, uint256 amountIn, bytes memory path) internal returns (uint256) {
        IERC20(tokenIn).approve(address(UNISWAP_ROUTER), amountIn);

        IUniswapSwapRouter02.ExactInputParams memory params = IUniswapSwapRouter02.ExactInputParams({
            path: path,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        return UNISWAP_ROUTER.exactInput(params);
    }
}
