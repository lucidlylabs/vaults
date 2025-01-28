// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {ReentrancyGuard} from "../lib/solady/src/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "../lib/solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";

import {IRateProvider} from "./RateProvider/IRateProvider.sol";
import {LogExpMath} from "./BalancerLibCode/LogExpMath.sol";
import {PoolToken} from "./PoolToken.sol";

contract Pool is Ownable, ReentrancyGuard {
    uint256 constant PRECISION = 1_000_000_000_000_000_000;
    uint256 constant MAX_NUM_TOKENS = 32;
    uint256 constant ALL_TOKENS_FLAG =
        14_528_991_250_861_404_666_834_535_435_384_615_765_856_667_510_756_806_797_353_855_100_662_256_435_713; // sum((i+1) << 8*i)
    uint256 constant POOL_VB_MASK = 2 ** 128 - 1;
    uint128 constant POOL_VB_SHIFT = 128;

    uint256 constant VB_MASK = 2 ** 96 - 1;
    uint256 constant RATE_MASK = 2 ** 80 - 1;
    uint128 constant RATE_SHIFT = 96;
    uint128 constant PACKED_WEIGHT_SHIFT = 176;

    uint256 constant WEIGHT_SCALE = 1_000_000_000_000;
    uint256 constant WEIGHT_MASK = 2 ** 20 - 1;
    uint128 constant TARGET_WEIGHT_SHIFT = 20;
    uint128 constant LOWER_BAND_SHIFT = 40;
    uint128 constant UPPER_BAND_SHIFT = 60;
    uint256 constant MAX_POW_REL_ERR = 100; // 1e-16

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error Pool__InputOutputTokensSame();
    error Pool__IndexOutOfBounds();
    error Pool__MaxLimitExceeded();
    error Pool__ZeroAmount();
    error Pool__MustBeInitiatedWithMoreThanOneToken();
    error Pool__MustBeInitiatedWithAGreaterThanZero();
    error Pool__InvalidParams();
    error Pool__CannotBeZeroAddress();
    error Pool__InvalidDecimals();
    error Pool__SumOfWeightsMustBeOne();
    error Pool__InvalidRateProvided();
    error Pool__NoConvergence();
    error Pool__RatioBelowLowerBound();
    error Pool__RatioAboveUpperBound();
    error Pool__SlippageLimitExceeded();
    error Pool__NeedToDepositAtleastOneToken();
    error Pool__InitialDepositAmountMustBeNonZero();
    error Pool__TokenDecimalCannotBeZero();
    error Pool__AmountsMustBeNonZero();
    error Pool__WeightOutOfBounds();
    error Pool__PoolIsFull();
    error Pool__RampActive();
    error Pool__PoolIsEmpty();
    error Pool__TokenAlreadyPartOfPool();
    error Pool__CannotRescuePoolToken();
    error Pool__BandsOutOfBounds();
    error Pool__WeightsDoNotAddUp();
    error Pool__AlreadyPaused();
    error Pool__NotPaused();
    error Pool__Killed();
    error Pool__NoSurplus();
    error Pool__NoRate();
    error Pool__Paused();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    event Swap(
        address indexed caller, address receiver, uint256 tokenIn, uint256 tokenOut, uint256 amountIn, uint256 amountOut
    );
    event AddLiquidity(address indexed caller, address receiver, uint256[] amountsIn, uint256 lpAmount);
    event RemoveLiquidity(address indexed caller, address receiver, uint256 lpAmount);
    event RemoveLiquiditySingle(
        address indexed caller, address receiver, uint256 token, uint256 amountOut, uint256 lpAmount
    );
    event RateUpdate(uint256 indexed token, uint256 rate);
    event Pause(address indexed caller);
    event Unpause(address indexed caller);
    event Kill();
    event AddToken(uint256 index, address token, address rateProvider, uint256 rate, uint256 weight, uint256 amount);
    event SetSwapFeeRate(uint256 rate);
    event SetWeightBand(uint256 indexed token, uint256 lower, uint256 upper);
    event SetRateProvider(uint256 token, address rateProvider);
    event SetRamp(uint256 amplification, uint256[] weights, uint256 duration, uint256 start);
    event SetRampStep(uint256 rampStep);
    event StopRamp();
    event SetVaultAddress(address vaultAddress);
    event SetGuardian(address indexed caller, address guardian);

    uint256 public amplification; // A * f**n
    uint256 public numTokens;
    uint256 public supply;
    address public tokenAddress;
    address public vaultAddress;
    address[MAX_NUM_TOKENS] public tokens;
    uint256[MAX_NUM_TOKENS] public rateMultipliers; // An array of: [10 ** (36 - tokens_[n].decimals()), ... for n in range(numTokens)]
    address[MAX_NUM_TOKENS] public rateProviders;
    uint256[MAX_NUM_TOKENS] public packedVirtualBalances; // x_i = b_i r_i (96) | r_i (80) | w_i (20) | target w_i (20) | lower (20) | upper (20)
    bool public paused;
    bool public killed;
    uint256 public swapFeeRate;
    uint256 public rampStep;
    uint256 public rampLastTime;
    uint256 public rampStopTime;
    uint256 public targetAmplification;
    uint256 packedPoolVirtualBalance; // vbProd (128) | vbSum (128)
    // vbProd: pi, product term `product((w_i * D / x_i)^(w_i n))`
    // vbSum: sigma, sum term `sum(x_i)`

    /// @notice constructor
    /// @dev sum of all weights
    /// @dev rebasing tokens not supported
    /// @param tokenAddress_ address of the poolToken
    /// @param amplification_ the pool amplification factor (in 18 decimals)
    /// @param tokens_ array of addresses of tokens in the pool
    /// @param rateProviders_ array of addresses of rate providers for the tokens in the pool
    /// @param weights_ weight of each token (in 18 decimals)
    constructor(
        address tokenAddress_,
        uint256 amplification_,
        address[] memory tokens_,
        address[] memory rateProviders_,
        uint256[] memory weights_,
        address owner_
    ) {
        if (tokenAddress_ == address(0)) revert Pool__InvalidParams();
        uint256 _numTokens = tokens_.length;

        if (_numTokens > MAX_NUM_TOKENS) revert Pool__MaxLimitExceeded();

        if (_numTokens < 2) {
            revert Pool__MustBeInitiatedWithMoreThanOneToken();
        }
        if (rateProviders_.length != _numTokens || weights_.length != _numTokens) {
            revert Pool__InvalidParams();
        }
        if (amplification_ < PRECISION) {
            revert Pool__MustBeInitiatedWithAGreaterThanZero();
        }

        amplification = amplification_;
        numTokens = _numTokens;

        uint256 weightSum;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;
            if (tokens_[t] == address(0)) {
                revert Pool__CannotBeZeroAddress();
            }
            tokens[t] = tokens_[t];

            if (rateProviders_[t] == address(0)) {
                revert Pool__CannotBeZeroAddress();
            }
            rateProviders[t] = rateProviders_[t];

            uint8 decimals = ERC20(tokens_[t]).decimals();
            if (decimals == 0) {
                revert Pool__TokenDecimalCannotBeZero();
            }
            rateMultipliers[t] = 10 ** (36 - decimals);

            if (weights_[t] == 0) {
                revert Pool__InvalidParams();
            }

            uint256 _packedWeight = _packWeight(weights_[t], weights_[t], PRECISION, PRECISION);

            packedVirtualBalances[t] = _packVirtualBalance(0, 0, _packedWeight);

            weightSum += weights_[t];
        }

        if (weightSum != PRECISION) {
            revert Pool__SumOfWeightsMustBeOne();
        }

        rampStep = 1;
        _setOwner(owner_);

        tokenAddress = tokenAddress_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       POOL FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice swap one pool token for another
    /// @param tokenIn_ index of the input token
    /// @param tokenOut_ index of the output token
    /// @param tokenInAmount_ amount of input token to take from the caller
    /// @param minTokenOutAmount_ minimum amount of output token to send
    /// @param receiver_ account to receive the output token
    /// @return the amount of output token
    function swap(
        uint256 tokenIn_,
        uint256 tokenOut_,
        uint256 tokenInAmount_,
        uint256 minTokenOutAmount_,
        address receiver_
    ) external nonReentrant returns (uint256) {
        uint256 _numTokens = numTokens;
        if (tokenIn_ == tokenOut_) revert Pool__InputOutputTokensSame();
        if (tokenIn_ >= _numTokens || tokenOut_ >= _numTokens) revert Pool__IndexOutOfBounds();
        if (tokenInAmount_ == 0) revert Pool__ZeroAmount();

        // update rates for from and to tokens
        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _unpackPoolVirtualBalance(packedPoolVirtualBalance);
        (_virtualBalanceProd, _virtualBalanceSum) = _updateRates(
            FixedPointMathLib.rawAdd(tokenIn_, 1) | (FixedPointMathLib.rawAdd(tokenOut_, 1) << 8),
            _virtualBalanceProd,
            _virtualBalanceSum
        );

        uint256 _prevVirtualBalanceSum = _virtualBalanceSum;

        (uint256 _prevVirtualBalanceX, uint256 _rateX, uint256 _packedWeightX) =
            _unpackVirtualBalance(packedVirtualBalances[tokenIn_]);
        uint256 _weightTimesNOfX = _unpackWeightTimesN(_packedWeightX, _numTokens);

        (uint256 _prevVirtualBalanceY, uint256 _rateY, uint256 _packedWeightY) =
            _unpackVirtualBalance(packedVirtualBalances[tokenOut_]);
        uint256 _weightTimesNOfY = _unpackWeightTimesN(_packedWeightY, _numTokens);

        // adjust tokenInAmount_ to 18 decimals
        uint256 _adjustedTokenInAmount = FixedPointMathLib.mulWad(tokenInAmount_, rateMultipliers[tokenIn_]); // (tokenInAmount_ * rateMultipliers[tokenIn_]) / PRECISION

        uint256 _tokenInFee = (_adjustedTokenInAmount * swapFeeRate) / PRECISION;
        uint256 _changeInVirtualBalanceTokenIn = ((_adjustedTokenInAmount - _tokenInFee) * _rateX) / PRECISION;
        uint256 _virtualBalanceX = _prevVirtualBalanceX + _changeInVirtualBalanceTokenIn;

        // update x_i and remove x_j from variables
        _virtualBalanceProd = _virtualBalanceProd * _powUp(_prevVirtualBalanceY, _weightTimesNOfY)
            / _powDown((_virtualBalanceX * PRECISION) / _prevVirtualBalanceX, _weightTimesNOfX);
        _virtualBalanceSum = _virtualBalanceSum + _changeInVirtualBalanceTokenIn - _prevVirtualBalanceY;

        // calculate new balance of out token
        uint256 _virtualBalanceY = _calculateVirtualBalance(
            _weightTimesNOfY, _prevVirtualBalanceY, supply, amplification, _virtualBalanceProd, _virtualBalanceSum
        );

        _virtualBalanceSum += _virtualBalanceY;

        // check bands
        _checkBands(
            (_prevVirtualBalanceX * PRECISION) / _prevVirtualBalanceSum,
            (_virtualBalanceX * PRECISION) / _virtualBalanceSum,
            _packedWeightX
        );
        _checkBands(
            (_prevVirtualBalanceY * PRECISION) / _prevVirtualBalanceSum,
            (_virtualBalanceY * PRECISION) / _virtualBalanceSum,
            _packedWeightY
        );

        uint256 _adjustedTokenOutAmount = FixedPointMathLib.divWad(_prevVirtualBalanceY - _virtualBalanceY, _rateY);
        uint256 _tokenOutAmount = FixedPointMathLib.divWad(_adjustedTokenOutAmount, rateMultipliers[tokenOut_]); // (_adjustedTokenOutAmount * PRECISION) / rateMultipliers[tokenOut_]

        if (_tokenOutAmount < minTokenOutAmount_) {
            revert Pool__SlippageLimitExceeded();
        }

        if (_tokenInFee > 0) {
            // add fee to pool
            _changeInVirtualBalanceTokenIn = (_tokenInFee * _rateX) / PRECISION;
            _virtualBalanceProd = (_virtualBalanceProd * PRECISION)
                / _powDown(
                    (_virtualBalanceX + _changeInVirtualBalanceTokenIn) * PRECISION / _virtualBalanceX, _weightTimesNOfX
                );
            _virtualBalanceX += _changeInVirtualBalanceTokenIn;
            _virtualBalanceSum += _changeInVirtualBalanceTokenIn;
        }

        // update variables
        packedVirtualBalances[tokenIn_] = _packVirtualBalance(_virtualBalanceX, _rateX, _packedWeightX);
        packedVirtualBalances[tokenOut_] = _packVirtualBalance(_virtualBalanceY, _rateY, _packedWeightY);
        _virtualBalanceProd = (_virtualBalanceProd * PRECISION) / _powUp(_virtualBalanceY, _weightTimesNOfY);

        // mint fees
        if (_tokenInFee > 0) {
            uint256 _supply;
            (_supply, _virtualBalanceProd) = _updateSupply(supply, _virtualBalanceProd, _virtualBalanceSum);
        }

        packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProd, _virtualBalanceSum);

        // transfer tokens
        SafeTransferLib.safeTransferFrom(tokens[tokenIn_], msg.sender, address(this), tokenInAmount_);
        SafeTransferLib.safeTransfer(tokens[tokenOut_], receiver_, _tokenOutAmount);
        emit Swap(msg.sender, receiver_, tokenIn_, tokenOut_, tokenInAmount_, _tokenOutAmount);

        return _tokenOutAmount;
    }

    /// @notice deposit tokens into the pool
    /// @param amounts_ array of the amount for each token to take from caller
    /// @param minLpAmount_ minimum amount of lp tokens to mint
    /// @param receiver_ account to receive the lp tokens
    /// @return amount of LP tokens minted
    function addLiquidity(uint256[] calldata amounts_, uint256 minLpAmount_, address receiver_)
        external
        nonReentrant
        returns (uint256)
    {
        uint256 _numTokens = numTokens;
        if (amounts_.length != _numTokens) revert Pool__InvalidParams();

        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _unpackPoolVirtualBalance(packedPoolVirtualBalance);

        uint256 _prevVirtualBalance;
        uint256 _rate;
        uint256 _packedWeight;

        // find lowest relative increase in balance
        uint256 _tokens = 0;
        uint256 _lowest = type(uint256).max;
        uint256 _sh;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;

            uint256 __amount = amounts_[t];

            if (__amount > 0) {
                uint256 _adjustedAmount = FixedPointMathLib.mulWad(__amount, rateMultipliers[t]); // (__amount * rateMultipliers[t]) / PRECISION
                _tokens = _tokens | (FixedPointMathLib.rawAdd(t, 1) << _sh);
                _sh = FixedPointMathLib.rawAdd(_sh, 8);
                if (_virtualBalanceSum > 0 && _lowest > 0) {
                    (_prevVirtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
                    _lowest = FixedPointMathLib.min(_adjustedAmount * _rate / _prevVirtualBalance, _lowest);
                }
            } else {
                _lowest = 0;
            }
        }
        if (_sh == 0) revert Pool__NeedToDepositAtleastOneToken();

        // update rates
        (_virtualBalanceProd, _virtualBalanceSum) = _updateRates(_tokens, _virtualBalanceProd, _virtualBalanceSum);
        uint256 _prevSupply = supply;

        uint256 _virtualBalanceProdFinal = _virtualBalanceProd;
        uint256 _virtualBalanceSumFinal = _virtualBalanceSum;
        uint256 _prevVirtualBalanceSum = _virtualBalanceSum;
        uint256[] memory _prevRatios = new uint256[](_numTokens);
        uint256 _virtualBalance;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;

            uint256 __amount = amounts_[t];
            uint256 _adjustedAmount = FixedPointMathLib.mulWad(__amount, rateMultipliers[t]); // (__amount * rateMultipliers[t]) / PRECISION

            if (_adjustedAmount == 0) {
                if (!(_prevSupply > 0)) {
                    revert Pool__InitialDepositAmountMustBeNonZero();
                }
                continue;
            }

            // update stored virtual balance
            (_prevVirtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
            uint256 _changeInVirtualBalance = (_adjustedAmount * _rate) / PRECISION;
            _virtualBalance = _prevVirtualBalance + _changeInVirtualBalance;
            packedVirtualBalances[t] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);

            if (_prevSupply > 0) {
                _prevRatios[t] = (_prevVirtualBalance * PRECISION) / _prevVirtualBalanceSum;
                uint256 _weightTimesN = _unpackWeightTimesN(_packedWeight, _numTokens);

                // update product and sum of virtual balances
                _virtualBalanceProdFinal = (
                    _virtualBalanceProdFinal
                        * _powUp((_prevVirtualBalance * PRECISION) / _virtualBalance, _weightTimesN)
                ) / PRECISION;

                // the `D^n` factor will be updated in `_calculateSupply()`
                _virtualBalanceSumFinal += _changeInVirtualBalance;

                // remove fees from balance and recalculate sum and product
                uint256 _fee = (
                    (_changeInVirtualBalance - (_prevVirtualBalance * _lowest) / PRECISION) * (swapFeeRate / 2)
                ) / PRECISION;
                _virtualBalanceProd = (
                    _virtualBalanceProd
                        * _powUp((_prevVirtualBalance * PRECISION) / (_virtualBalance - _fee), _weightTimesN)
                ) / PRECISION;
                _virtualBalanceSum += _changeInVirtualBalance - _fee;
            }

            SafeTransferLib.safeTransferFrom(tokens[t], msg.sender, address(this), __amount);
        }

        uint256 _supply = _prevSupply;
        if (_prevSupply == 0) {
            // initial deposit, calculate necessary variables
            (_virtualBalanceProd, _virtualBalanceSum) = _calculateVirtualBalanceProdSum();
            if (!(_virtualBalanceProd > 0)) revert Pool__AmountsMustBeNonZero();
            _supply = _virtualBalanceSum;
        } else {
            // check bands
            for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
                if (t == _numTokens) break;
                if (amounts_[t] == 0) continue;
                (_virtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
                _checkBands(_prevRatios[t], (_virtualBalance * PRECISION) / _virtualBalanceSumFinal, _packedWeight);
            }
        }

        // mint LP tokens
        (_supply, _virtualBalanceProd) = _calculateSupply(
            _numTokens, _supply, amplification, _virtualBalanceProd, _virtualBalanceSum, _prevSupply == 0
        );
        uint256 _toMint = _supply - _prevSupply;

        if (!(_toMint > 0 && _toMint >= minLpAmount_)) {
            revert Pool__SlippageLimitExceeded();
        }
        PoolToken(tokenAddress).mint(receiver_, _toMint);
        emit AddLiquidity(msg.sender, receiver_, amounts_, _toMint);

        uint256 _supplyFinal = _supply;
        if (_prevSupply > 0) {
            // mint fees
            (_supplyFinal, _virtualBalanceProdFinal) = _calculateSupply(
                _numTokens, _prevSupply, amplification, _virtualBalanceProdFinal, _virtualBalanceSumFinal, true
            );
            PoolToken(tokenAddress).mint(vaultAddress, _supplyFinal - _supply);
        } else {
            _virtualBalanceProdFinal = _virtualBalanceProd;
            _virtualBalanceSumFinal = _virtualBalanceSum;
        }
        supply = _supplyFinal;

        packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProdFinal, _virtualBalanceSumFinal);
        return _toMint;
    }

    /// @notice deposit tokens into the pool
    /// @param amounts_ array of the amount for each token to take from caller
    /// @param minLpAmount_ minimum amount of lp tokens to mint
    /// @param receiver_ account to receive the lp tokens
    /// @return amount of LP tokens minted
    function addLiquidityFor(uint256[] calldata amounts_, uint256 minLpAmount_, address owner_, address receiver_)
        external
        nonReentrant
        returns (uint256)
    {
        uint256 _numTokens = numTokens;
        if (amounts_.length != _numTokens) revert Pool__InvalidParams();

        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _unpackPoolVirtualBalance(packedPoolVirtualBalance);

        uint256 _prevVirtualBalance;
        uint256 _rate;
        uint256 _packedWeight;

        // find lowest relative increase in balance
        uint256 _tokens = 0;
        uint256 _lowest = type(uint256).max;
        uint256 _sh;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;

            uint256 __amount = amounts_[t];

            if (__amount > 0) {
                uint256 _adjustedAmount = FixedPointMathLib.mulWad(__amount, rateMultipliers[t]); // (__amount * rateMultipliers[t]) / PRECISION
                _tokens = _tokens | (FixedPointMathLib.rawAdd(t, 1) << _sh);
                _sh = FixedPointMathLib.rawAdd(_sh, 8);
                if (_virtualBalanceSum > 0 && _lowest > 0) {
                    (_prevVirtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
                    _lowest = FixedPointMathLib.min(_adjustedAmount * _rate / _prevVirtualBalance, _lowest);
                }
            } else {
                _lowest = 0;
            }
        }
        if (_sh == 0) revert Pool__NeedToDepositAtleastOneToken();

        // update rates
        (_virtualBalanceProd, _virtualBalanceSum) = _updateRates(_tokens, _virtualBalanceProd, _virtualBalanceSum);
        uint256 _prevSupply = supply;

        uint256 _virtualBalanceProdFinal = _virtualBalanceProd;
        uint256 _virtualBalanceSumFinal = _virtualBalanceSum;
        uint256 _prevVirtualBalanceSum = _virtualBalanceSum;
        uint256[] memory _prevRatios = new uint256[](_numTokens);
        uint256 _virtualBalance;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;

            uint256 __amount = amounts_[t];
            uint256 _adjustedAmount = FixedPointMathLib.mulWad(__amount, rateMultipliers[t]); // (__amount * rateMultipliers[t]) / PRECISION

            if (_adjustedAmount == 0) {
                if (!(_prevSupply > 0)) {
                    revert Pool__InitialDepositAmountMustBeNonZero();
                }
                continue;
            }

            // update stored virtual balance
            (_prevVirtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
            uint256 _changeInVirtualBalance = (_adjustedAmount * _rate) / PRECISION;
            _virtualBalance = _prevVirtualBalance + _changeInVirtualBalance;
            packedVirtualBalances[t] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);

            if (_prevSupply > 0) {
                _prevRatios[t] = (_prevVirtualBalance * PRECISION) / _prevVirtualBalanceSum;
                uint256 _weightTimesN = _unpackWeightTimesN(_packedWeight, _numTokens);

                // update product and sum of virtual balances
                _virtualBalanceProdFinal = (
                    _virtualBalanceProdFinal
                        * _powUp((_prevVirtualBalance * PRECISION) / _virtualBalance, _weightTimesN)
                ) / PRECISION;

                // the `D^n` factor will be updated in `_calculateSupply()`
                _virtualBalanceSumFinal += _changeInVirtualBalance;

                // remove fees from balance and recalculate sum and product
                uint256 _fee = (
                    (_changeInVirtualBalance - (_prevVirtualBalance * _lowest) / PRECISION) * (swapFeeRate / 2)
                ) / PRECISION;
                _virtualBalanceProd = (
                    _virtualBalanceProd
                        * _powUp((_prevVirtualBalance * PRECISION) / (_virtualBalance - _fee), _weightTimesN)
                ) / PRECISION;
                _virtualBalanceSum += _changeInVirtualBalance - _fee;
            }

            SafeTransferLib.safeTransferFrom(tokens[t], owner_, address(this), __amount);
        }

        uint256 _supply = _prevSupply;
        if (_prevSupply == 0) {
            // initial deposit, calculate necessary variables
            (_virtualBalanceProd, _virtualBalanceSum) = _calculateVirtualBalanceProdSum();
            if (!(_virtualBalanceProd > 0)) revert Pool__AmountsMustBeNonZero();
            _supply = _virtualBalanceSum;
        } else {
            // check bands
            for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
                if (t == _numTokens) break;
                if (amounts_[t] == 0) continue;
                (_virtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
                _checkBands(_prevRatios[t], (_virtualBalance * PRECISION) / _virtualBalanceSumFinal, _packedWeight);
            }
        }

        // mint LP tokens
        (_supply, _virtualBalanceProd) = _calculateSupply(
            _numTokens, _supply, amplification, _virtualBalanceProd, _virtualBalanceSum, _prevSupply == 0
        );
        uint256 _toMint = _supply - _prevSupply;

        if (!(_toMint > 0 && _toMint >= minLpAmount_)) {
            revert Pool__SlippageLimitExceeded();
        }
        PoolToken(tokenAddress).mint(receiver_, _toMint);
        emit AddLiquidity(msg.sender, receiver_, amounts_, _toMint);

        uint256 _supplyFinal = _supply;
        if (_prevSupply > 0) {
            // mint fees
            (_supplyFinal, _virtualBalanceProdFinal) = _calculateSupply(
                _numTokens, _prevSupply, amplification, _virtualBalanceProdFinal, _virtualBalanceSumFinal, true
            );
            PoolToken(tokenAddress).mint(vaultAddress, _supplyFinal - _supply);
        } else {
            _virtualBalanceProdFinal = _virtualBalanceProd;
            _virtualBalanceSumFinal = _virtualBalanceSum;
        }
        supply = _supplyFinal;

        packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProdFinal, _virtualBalanceSumFinal);
        return _toMint;
    }

    /// @notice withdraw tokens from the pool in a balanced manner
    /// @param lpAmount_ amount of lp tokens to burn
    /// @param minAmounts_ array of minimum amount of each token to send
    /// @param receiver_ account to receive the tokens
    function removeLiquidity(uint256 lpAmount_, uint256[] calldata minAmounts_, address receiver_)
        external
        nonReentrant
    {
        uint256 _numTokens = numTokens;

        if (minAmounts_.length != _numTokens || minAmounts_.length > MAX_NUM_TOKENS) revert Pool__InvalidParams();

        // update supply
        uint256 _prevSupply = supply;
        uint256 _supply = _prevSupply - lpAmount_;
        supply = _supply;
        PoolToken(tokenAddress).burn(msg.sender, lpAmount_);
        emit RemoveLiquidity(msg.sender, receiver_, lpAmount_);

        // update variables and transfer tokens
        uint256 _virtualBalanceProd = PRECISION;
        uint256 _virtualBalanceSum = 0;

        uint256 _prevVirtualBalance;
        uint256 _rate;
        uint256 _packedWeight;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;

            (_prevVirtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);

            uint256 __weight = _unpackWeightTimesN(_packedWeight, 1);

            uint256 dVb = (_prevVirtualBalance * lpAmount_) / _prevSupply;
            uint256 vb = _prevVirtualBalance - dVb;
            packedVirtualBalances[t] = _packVirtualBalance(vb, _rate, _packedWeight);

            _virtualBalanceProd = FixedPointMathLib.rawDiv(
                FixedPointMathLib.rawMul(
                    _virtualBalanceProd,
                    _powDown(
                        FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(_supply, __weight), vb),
                        FixedPointMathLib.rawMul(__weight, _numTokens)
                    )
                ),
                PRECISION
            );
            _virtualBalanceSum = FixedPointMathLib.rawAdd(_virtualBalanceSum, vb);

            uint256 _adjustedAmount = (dVb * PRECISION) / _rate;
            uint256 _amount = FixedPointMathLib.divWad(_adjustedAmount, rateMultipliers[t]); // (_adjustedAmount * PRECISION) / rateMultiplers[t]

            if (_amount < minAmounts_[t]) revert Pool__SlippageLimitExceeded();
            SafeTransferLib.safeTransfer(tokens[t], receiver_, _amount);
        }

        packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProd, _virtualBalanceSum);
    }

    /// @notice withdraw a single token from the pool
    /// @param token_ index of the token to withdraw
    /// @param lpAmount_ amount of lp tokens to burn
    /// @param minTokenOutAmount_ minimum amount of tokens to send
    /// @param receiver_ account to receive the token
    /// @return the amount of the token sent
    function removeLiquiditySingle(uint256 token_, uint256 lpAmount_, uint256 minTokenOutAmount_, address receiver_)
        external
        nonReentrant
        returns (uint256)
    {
        uint256 _numTokens = numTokens;
        if (token_ >= _numTokens) revert Pool__InvalidParams();

        // update rate
        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _unpackPoolVirtualBalance(packedPoolVirtualBalance);
        (_virtualBalanceProd, _virtualBalanceSum) =
            _updateRates(FixedPointMathLib.rawAdd(token_, 1), _virtualBalanceProd, _virtualBalanceSum);
        uint256 _prevVirtualBalanceSum = _virtualBalanceSum;

        // update supply
        uint256 _prevSupply = supply;
        uint256 _newSupply = _prevSupply - lpAmount_;
        supply = _newSupply;
        PoolToken(tokenAddress).burn(msg.sender, lpAmount_);

        (uint256 _prevVirtualBalance, uint256 _rate, uint256 _packedWeight) =
            _unpackVirtualBalance(packedVirtualBalances[token_]);
        uint256 _weightTimesN = _unpackWeightTimesN(_packedWeight, _numTokens);

        // update variables
        _virtualBalanceProd = (_virtualBalanceProd * _powUp(_prevVirtualBalance, _weightTimesN)) / PRECISION;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;
            _virtualBalanceProd = (_virtualBalanceProd * _newSupply) / _prevSupply;
        }
        _virtualBalanceSum = _virtualBalanceSum - _prevVirtualBalance;

        // calculate new balance of token
        uint256 _virtualBalance = _calculateVirtualBalance(
            _weightTimesN, _prevVirtualBalance, _newSupply, amplification, _virtualBalanceProd, _virtualBalanceSum
        );
        uint256 _changeInVirtualBalance = _prevVirtualBalance - _virtualBalance;
        uint256 _fee = _changeInVirtualBalance * swapFeeRate / 2 / PRECISION;
        _changeInVirtualBalance -= _fee;
        _virtualBalance += _fee;

        uint256 _adjustedTokenOutAmount = (_changeInVirtualBalance * PRECISION) / _rate;
        uint256 _tokenOutAmount = FixedPointMathLib.divWad(_adjustedTokenOutAmount, rateMultipliers[token_]); // _adjustedTokenOutAmount * PRECISION / rateMultipliers[token_]
        if (_tokenOutAmount < minTokenOutAmount_) {
            revert Pool__SlippageLimitExceeded();
        }

        // update variables
        packedVirtualBalances[token_] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);
        _virtualBalanceProd = (_virtualBalanceProd * PRECISION) / _powUp(_virtualBalance, _weightTimesN);
        _virtualBalanceSum = _virtualBalanceSum + _virtualBalance;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;
            if (t == token_) {
                _checkBands(
                    (_prevVirtualBalance * PRECISION) / _prevVirtualBalanceSum,
                    (_virtualBalance * PRECISION) / _virtualBalanceSum,
                    _packedWeight
                );
            } else {
                (uint256 _virtualBalanceLoop,, uint256 _packedWeightLoop) =
                    _unpackVirtualBalance(packedVirtualBalances[t]);
                _checkBands(
                    (_virtualBalanceLoop * PRECISION) / _prevVirtualBalanceSum,
                    (_virtualBalanceLoop * PRECISION) / _virtualBalanceSum,
                    _packedWeightLoop
                );
            }
        }

        if (_fee > 0) {
            // mint fee
            (_newSupply, _virtualBalanceProd) = _updateSupply(_newSupply, _virtualBalanceProd, _virtualBalanceSum);
        }

        packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProd, _virtualBalanceSum);

        SafeTransferLib.safeTransfer(tokens[token_], receiver_, _tokenOutAmount);

        emit RemoveLiquiditySingle(msg.sender, receiver_, token_, _tokenOutAmount, lpAmount_);
        return _tokenOutAmount;
    }

    /// @notice update the stored rate of any of the pool's tokens
    /// @dev if no assets are passed in, every asset will be updated
    /// @param tokens_ array of indices of tokens to update
    function updateRates(uint256[] calldata tokens_) external {
        uint256 _numTokens = numTokens;

        uint256 _tokens;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == tokens_.length) break;
            if (tokens_[t] >= _numTokens) revert Pool__IndexOutOfBounds();
            _tokens = _tokens | ((tokens_[t] + 1) << (FixedPointMathLib.rawMul(8, t)));
        }

        if (tokens_.length == 0) _tokens = ALL_TOKENS_FLAG;
        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _unpackPoolVirtualBalance(packedPoolVirtualBalance);
        (_virtualBalanceProd, _virtualBalanceSum) = _updateRates(_tokens, _virtualBalanceProd, _virtualBalanceSum);
        packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProd, _virtualBalanceSum);
    }

    /// @notice update weights and amplification factor, if possible
    /// @dev will only update the weights if a ramp is active and at least the minimum time step has been reached
    /// @return boolean to indicate whether the weights and amplification factor have been updated
    function updateWeights() external returns (bool) {
        _checkIfPaused();
        bool _updated = false;
        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _unpackPoolVirtualBalance(packedPoolVirtualBalance);
        (_virtualBalanceProd, _updated) = _updateWeights(_virtualBalanceProd);
        if (_updated && _virtualBalanceSum > 0) {
            (, _virtualBalanceProd) = _updateSupply(supply, _virtualBalanceProd, _virtualBalanceSum);
            packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProd, _virtualBalanceSum);
        }
        return _updated;
    }

    /// @notice get the pool's virtual balance product (pi) and sum (sigma)
    /// @return tuple with product and sum
    function virtualBalanceProdSum() external view returns (uint256, uint256) {
        return _unpackPoolVirtualBalance(packedPoolVirtualBalance);
    }

    /// @notice get the virtual balance of a token
    /// @param token_ index of the token in the pool
    /// @return virtual balance of the token
    function virtualBalance(uint256 token_) external view returns (uint256) {
        if (token_ >= numTokens) revert Pool__IndexOutOfBounds();
        return packedVirtualBalances[token_] & VB_MASK;
    }

    /// @notice get the rate of an token
    /// @param token_ index of the token
    /// @return rate of the token
    function rate(uint256 token_) external view returns (uint256) {
        if (token_ >= numTokens) revert Pool__IndexOutOfBounds();
        return (packedVirtualBalances[token_] >> RATE_SHIFT) & RATE_MASK;
    }

    /// @notice get the weight of a token
    /// @dev does not take into account any active ramp
    /// @param token_ index of the token
    /// @return tuple with weight, target weight, lower band width, upper weight band width
    function weight(uint256 token_) external view returns (uint256, uint256, uint256, uint256) {
        if (token_ >= numTokens) revert Pool__IndexOutOfBounds();
        (uint256 _weight, uint256 _target, uint256 _lower, uint256 _upper) =
            _unpackWeight(packedVirtualBalances[token_] >> PACKED_WEIGHT_SHIFT);
        if (rampLastTime == 0) _target = _weight;
        return (_weight, _target, _lower, _upper);
    }

    /// @notice get the packed weight of a token in a packed format
    /// @dev does not take into account any active ramp
    /// @param token_ index of the token
    /// @return weight in packed format
    function packedWeight(uint256 token_) external view returns (uint256) {
        if (token_ >= numTokens) revert Pool__IndexOutOfBounds();
        return packedVirtualBalances[token_] >> PACKED_WEIGHT_SHIFT;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice pause the pool
    function pause() external onlyOwner {
        if (paused) revert Pool__AlreadyPaused();
        paused = true;
        emit Pause(msg.sender);
    }

    /// @notice unpause the pool
    function unpause() external onlyOwner {
        if (!paused) revert Pool__NotPaused();
        if (killed) revert Pool__Killed();
        paused = false;
        emit Unpause(msg.sender);
    }

    /// @notice kill the pool
    function kill() external onlyOwner {
        if (!paused) revert Pool__NotPaused();
        if (killed) revert Pool__Killed();
        killed = true;
        emit Kill();
    }

    /// @notice add a new token to the pool
    /// @dev can only be called if no ramp is currently active
    /// @dev every other token will their weight reduced pro rata
    /// @dev caller should assure that amplification before and after the call are the same
    /// @param token_ address of the token to add
    /// @param rateProvider_ rate provider for the token
    /// @param weight_ weight of the new token
    /// @param lower_ lower band width
    /// @param upper_ upper band width
    /// @param amount_ amount of tokens
    /// @param amplification_ new pool amplification factor
    /// @param receiver_ account to receive the lp tokens minted
    function addToken(
        address token_,
        address rateProvider_,
        uint256 weight_,
        uint256 lower_,
        uint256 upper_,
        uint256 amount_,
        uint256 amplification_,
        uint256 minLpAmount_,
        address receiver_
    ) external onlyOwner {
        if (amount_ == 0) revert Pool__ZeroAmount();
        uint256 _prevNumTokens = numTokens;
        if (_prevNumTokens >= MAX_NUM_TOKENS) revert Pool__PoolIsFull();
        if (amplification_ == 0) revert Pool__ZeroAmount();
        if (rampLastTime != 0) revert Pool__RampActive();
        if (supply == 0) revert Pool__PoolIsEmpty();

        if (!(weight_ > 0 && weight_ <= PRECISION / 100)) {
            revert Pool__InvalidParams();
        }
        if (lower_ > PRECISION || upper_ > PRECISION) {
            revert Pool__InvalidParams();
        }

        // update weights for existing tokens
        uint256 _numTokens = _prevNumTokens + 1;
        uint256 _virtualBalance;
        uint256 _rate;
        uint256 _packedWeight;
        uint256 _prevWeight;
        uint256 _target;
        uint256 _lower;
        uint256 _upper;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _prevNumTokens) break;
            if (tokens[t] == token_) revert Pool__TokenAlreadyPartOfPool();
            (_virtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
            (_prevWeight, _target, _lower, _upper) = _unpackWeight(_packedWeight);
            _packedWeight = _packWeight(
                FixedPointMathLib.rawSub(
                    _prevWeight, FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(_prevWeight, weight_), PRECISION)
                ),
                _target,
                _lower,
                _upper
            );
            packedVirtualBalances[t] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);
        }

        // IRateProvider(provider).rate(address) is assumed to be 10**18 precision
        _rate = IRateProvider(rateProvider_).rate(token_);
        if (_rate == 0) revert Pool__NoRate();

        uint256 _adjustedAmount = FixedPointMathLib.mulWad(amount_, (10 ** (36 - ERC20(token_).decimals()))); // (amount_ *  (10 ** (36 - ERC20(token_).decimals()))) / PRECISION
        _virtualBalance = (_adjustedAmount * _rate) / PRECISION;
        _packedWeight = _packWeight(weight_, weight_, _lower, _upper);

        // set parameters for new token
        numTokens = _numTokens;
        tokens[_prevNumTokens] = token_;
        rateMultipliers[_prevNumTokens] = 10 ** (36 - ERC20(token_).decimals());
        rateProviders[_prevNumTokens] = rateProvider_;
        packedVirtualBalances[_prevNumTokens] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);

        // recalculate variables
        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _calculateVirtualBalanceProdSum();

        // update supply
        uint256 _prevSupply = supply;
        uint256 __supply;
        (__supply, _virtualBalanceProd) = _calculateSupply(
            _numTokens, _virtualBalanceSum, amplification_, _virtualBalanceProd, _virtualBalanceSum, true
        );

        amplification = amplification_;
        supply = __supply;
        packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProd, _virtualBalanceSum);

        SafeTransferLib.safeTransferFrom(token_, msg.sender, address(this), amount_);
        if (__supply <= _prevSupply) revert Pool__InvalidParams();
        uint256 _lpAmount = FixedPointMathLib.rawSub(__supply, _prevSupply);
        if (_lpAmount < minLpAmount_) revert Pool__InvalidParams();
        PoolToken(tokenAddress).mint(receiver_, _lpAmount);
        emit AddToken(_prevNumTokens, token_, rateProvider_, _rate, weight_, amount_);
    }

    /// @notice rescue tokens from this contract
    /// @dev cannot be used to rescue pool tokens
    /// @param token_ the token to be rescued
    /// @param receiver_ receiver of the rescued tokens
    function rescue(address token_, address receiver_) external onlyOwner {
        uint256 _numTokens = numTokens;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;
            if (!(token_ != tokens[t])) revert Pool__CannotRescuePoolToken();
        }
        uint256 _amount = ERC20(token_).balanceOf(address(this));
        SafeTransferLib.safeTransfer(token_, receiver_, _amount);
    }

    /// @notice skim surplus of a pool token
    /// @param token_ index of the token
    /// @param receiver_ receiver of the skimmed tokens
    function skim(uint256 token_, address receiver_) external onlyOwner {
        if (token_ >= numTokens) revert Pool__IndexOutOfBounds();
        (uint256 _virtualBalance, uint256 _rate,) = _unpackVirtualBalance(packedVirtualBalances[token_]);
        uint256 _adjustedExpected = (_virtualBalance * PRECISION) / _rate + 1;
        uint256 _expected = FixedPointMathLib.divWad(_adjustedExpected, rateMultipliers[token_]); // (_adjustedExpected * PRECISION) / rateMultiplers[token_]
        address _token = tokens[token_];
        uint256 _actual = ERC20(_token).balanceOf(address(this));
        if (_actual <= _expected) revert Pool__NoSurplus();
        SafeTransferLib.safeTransfer(_token, receiver_, _actual - _expected);
    }

    /// @notice set new swap fee rate
    /// @param feeRate_ new swap fee rate (in 18 decimals)
    function setSwapFeeRate(uint256 feeRate_) external onlyOwner {
        if (feeRate_ > PRECISION / 100) revert Pool__InvalidParams();
        swapFeeRate = feeRate_;
        emit SetSwapFeeRate(feeRate_);
    }

    /// @notice set safety weight bands, if any user operation puts the weight outside of the bands, the transaction will revert
    /// @param tokens_ array of indices of the tokens to set the bands for
    /// @param lower_ array of widths of the lower band
    /// @param upper_ array of widths of the upper band
    function setWeightBands(uint256[] calldata tokens_, uint256[] calldata lower_, uint256[] calldata upper_)
        external
        onlyOwner
    {
        if (!(lower_.length == tokens_.length && upper_.length == tokens_.length)) revert Pool__InvalidParams();

        uint256 _numTokens = numTokens;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == tokens_.length) break;
            uint256 _token = tokens_[t];
            if (_token >= _numTokens) revert Pool__IndexOutOfBounds();
            if (!(lower_[t] <= PRECISION && upper_[t] <= PRECISION)) {
                revert Pool__BandsOutOfBounds();
            }

            (uint256 _virtualBalance, uint256 _rate, uint256 _packedWeight) =
                _unpackVirtualBalance(packedVirtualBalances[_token]);
            (uint256 _weight, uint256 _target,,) = _unpackWeight(_packedWeight);
            _packedWeight = _packWeight(_weight, _target, lower_[t], upper_[t]);
            packedVirtualBalances[_token] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);
            emit SetWeightBand(_token, lower_[t], upper_[t]);
        }
    }

    /// @notice set a rate provider for a token
    /// @param token_ index of the token
    /// @param rateProvider_ new rate provider for the token
    function setRateProvider(uint256 token_, address rateProvider_) external onlyOwner {
        if (token_ >= numTokens) revert Pool__IndexOutOfBounds();

        rateProviders[token_] = rateProvider_;
        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _unpackPoolVirtualBalance(packedPoolVirtualBalance);
        (_virtualBalanceProd, _virtualBalanceSum) = _updateRates(token_ + 1, _virtualBalanceProd, _virtualBalanceSum);
        packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProd, _virtualBalanceSum);
        emit SetRateProvider(token_, rateProvider_);
    }

    /// @notice schedule an amplification and/or weight change
    /// @dev effective amplification at any time is `amplification/f^n`
    /// @param amplification_ new amplification factor (in 18 decimals)
    /// @param weights_ array of the new weight for each token (in 18 decimals)
    /// @param duration_ duration of the ramp (in seconds)
    /// @param start_ ramp start time
    function setRamp(uint256 amplification_, uint256[] calldata weights_, uint256 duration_, uint256 start_)
        external
        onlyOwner
    {
        uint256 _numTokens = numTokens;
        if (amplification_ == 0) revert Pool__InvalidParams();
        if (weights_.length != _numTokens) revert Pool__InvalidParams();
        if (start_ < block.timestamp) revert Pool__InvalidParams();

        bool _updated;
        (uint256 _virtualBalanceProd, uint256 _virtualBalanceSum) = _unpackPoolVirtualBalance(packedPoolVirtualBalance);
        (_virtualBalanceProd, _updated) = _updateWeights(_virtualBalanceProd);
        if (_updated) {
            uint256 _supply;
            (_supply, _virtualBalanceProd) = _updateSupply(supply, _virtualBalanceProd, _virtualBalanceSum);
            packedPoolVirtualBalance = _packPoolVirtualBalance(_virtualBalanceProd, _virtualBalanceSum);
        }

        if (rampLastTime != 0) revert Pool__RampActive();

        rampLastTime = start_;
        rampStopTime = start_ + duration_;

        targetAmplification = amplification_;

        uint256 _total;

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == _numTokens) break;
            uint256 _newWeight = weights_[t];
            if (_newWeight >= PRECISION) revert Pool__WeightOutOfBounds();
            _total += _newWeight;

            (uint256 _virtualBalance, uint256 _rate, uint256 _packedWeight) =
                _unpackVirtualBalance(packedVirtualBalances[t]);

            (uint256 _weight,, uint256 _lower, uint256 _upper) = _unpackWeight(_packedWeight);

            _packedWeight = _packWeight(_weight, _newWeight, _lower, _upper);
            packedVirtualBalances[t] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);
        }

        if (_total != PRECISION) revert Pool__WeightsDoNotAddUp();
        emit SetRamp(amplification_, weights_, duration_, start_);
    }

    /// @notice set the minimum time b/w ramp step
    /// @param rampStep_ minimum step time (in seconds)
    function setRampStep(uint256 rampStep_) external onlyOwner {
        if (rampStep_ == 0) revert Pool__InvalidParams();
        rampStep = rampStep_;
        emit SetRampStep(rampStep_);
    }

    /// @notice stop an active ramp
    function stopRamp() external onlyOwner {
        rampLastTime = 0;
        rampStopTime = 0;
        emit StopRamp();
    }

    /// @notice set the address that receives yield, slashings and swap fees
    /// @param vaultAddress_ new vault address
    function setVaultAddress(address vaultAddress_) external onlyOwner {
        if (vaultAddress_ == address(0)) revert Pool__InvalidParams();
        vaultAddress = vaultAddress_;
        emit SetVaultAddress(vaultAddress_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice update rates of specific tokens
    /// @dev loops through the bytes in `token_` until a zero or a number larger than the number of assets is encountered
    /// @dev update weights (if needed) prior to checking any rates
    /// @dev will recalculate supply and mint/burn to vault contract if any weight or rate has updated
    /// @dev will revert if any rate increases by more than 10%, unless called by management
    /// @param tokens_ integer where each byte represents a token index offset by one
    /// @param virtualBalanceProd_ product term (pi) before update
    /// @param virtualBalanceSum_ sum term (sigma) before update
    /// @return tuple with new product and sum term
    function _updateRates(uint256 tokens_, uint256 virtualBalanceProd_, uint256 virtualBalanceSum_)
        internal
        returns (uint256, uint256)
    {
        _checkIfPaused();

        uint256 _virtualBalanceSum = virtualBalanceSum_;
        (uint256 _virtualBalanceProd, bool _updated) = _updateWeights(virtualBalanceProd_);

        uint256 _numTokens = numTokens;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            uint256 token = (tokens_ >> FixedPointMathLib.rawMul(8, t)) & 255;
            if (token == 0 || token > _numTokens) {
                break;
            }
            token = FixedPointMathLib.rawSub(token, 1);
            address provider = rateProviders[token];

            (uint256 _prevVirtualBalance, uint256 _prevRate, uint256 _packedWeight) =
                _unpackVirtualBalance(packedVirtualBalances[token]);

            // IRateProvider(provider).rate(address) is assumed to be 10**18 precision
            uint256 _rate = IRateProvider(provider).rate(tokens[token]);

            if (!(_rate > 0)) revert Pool__InvalidRateProvided();

            // no rate change
            if (_rate == _prevRate) continue;

            // cap upward rate movement to 10%
            if (_rate > (_prevRate * 11) / 10 && _prevRate > 0) {
                _checkOwner();
            }

            uint256 _virtualBalance;
            if (_prevRate > 0 && _virtualBalanceSum > 0) {
                // factor out old rate and factor in new rate
                uint256 weightTimesN = _unpackWeightTimesN(_packedWeight, _numTokens);
                _virtualBalanceProd =
                    (_virtualBalanceProd * _powUp((_prevRate * PRECISION) / _rate, weightTimesN)) / PRECISION;
                _virtualBalance = (_prevVirtualBalance * _rate) / _prevRate;
                _virtualBalanceSum = _virtualBalanceSum + _virtualBalance - _prevVirtualBalance;
            }

            packedVirtualBalances[token] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);
            emit RateUpdate(token, _rate);
        }

        if (!_updated && _virtualBalanceProd == virtualBalanceProd_ && _virtualBalanceSum == virtualBalanceSum_) {
            return (_virtualBalanceProd, _virtualBalanceSum);
        }

        // recalculate supply and mint/burn token to vault address
        uint256 _supply;
        (_supply, _virtualBalanceProd) = _updateSupply(supply, _virtualBalanceProd, _virtualBalanceSum);
        return (_virtualBalanceProd, _virtualBalanceSum);
    }

    /// @notice apply a step in amplitude and weight ramp, if applicable
    /// @dev caller is reponsible for updating supply if a step has been taken
    /// @param vbProd_ product term(pi) before update
    /// @return tuple with new product term and flag indicating if a step has been taken
    function _updateWeights(uint256 vbProd_) internal returns (uint256, bool) {
        uint256 _span = rampLastTime;
        uint256 _duration = rampStopTime;
        if (
            _span == 0 || _span > block.timestamp || (block.timestamp - _span < rampStep && _duration > block.timestamp)
        ) {
            // scenarios:
            //  1) no ramp is active
            //  2) ramp is scheduled for in the future
            //  3) weights have been updated too recently and ramp hasnt finished yet
            return (vbProd_, false);
        }

        if (block.timestamp < _duration) {
            // ramp in progress
            _duration -= _span;
            rampLastTime = block.timestamp;
        } else {
            // ramp has finished
            _duration = 0;
            rampLastTime = 0;
            rampStopTime = 0;
        }

        _span = block.timestamp - _span;

        // update amplification
        uint256 _current = amplification;
        uint256 _target = targetAmplification;

        if (_duration == 0) {
            _current = _target;
        } else {
            if (_current > _target) {
                _current = _current - ((_current - _target) * _span) / _duration;
            } else {
                _current = _current + ((_target - _current) * _span) / _duration;
            }
        }
        amplification = _current;

        // update weights
        uint256 _virtualBalance = 0;
        uint256 _rate = 0;
        uint256 _packedWeight = 0;
        uint256 _lower = 0;
        uint256 _upper = 0;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == numTokens) break;
            (_virtualBalance, _rate, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
            (_current, _target, _lower, _upper) = _unpackWeight(_packedWeight);
            if (_duration == 0) {
                _current = _target;
            } else {
                if (_current > _target) {
                    _current -= ((_current - _target) * _span) / _duration;
                } else {
                    _current += ((_target - _current) * _span) / _duration;
                }
            }
            _packedWeight = _packWeight(_current, _target, _lower, _upper);
            packedVirtualBalances[t] = _packVirtualBalance(_virtualBalance, _rate, _packedWeight);
        }

        uint256 vbProd = 0;
        uint256 _supply = supply;
        if (_supply > 0) {
            vbProd = _calculateVirtualBalanceProd(_supply);
        }
        return (vbProd, true);
    }

    /// @notice calculate supply and burn or mint difference from the vault contract
    /// @param supply_ previous supply
    /// @param vbProd_ product term (pi)
    /// @param vbSum_ sum term (sigma)
    /// @return tuple with new supply and product term
    function _updateSupply(uint256 supply_, uint256 vbProd_, uint256 vbSum_) internal returns (uint256, uint256) {
        if (supply_ == 0) return (0, vbProd_);

        (uint256 _supply, uint256 _virtualBalanceProd) =
            _calculateSupply(numTokens, supply_, amplification, vbProd_, vbSum_, true);

        if (_supply > supply_) {
            PoolToken(tokenAddress).mint(vaultAddress, _supply - supply_);
        } else if (_supply < supply_) {
            PoolToken(tokenAddress).burn(vaultAddress, supply_ - _supply);
        }
        supply = _supply;
        return (_supply, _virtualBalanceProd);
    }

    /// @notice check whether asset is within safety band, or if previously outside, moves closer to it
    /// @dev reverts if conditions are not met
    /// @param prevRatio_ token ratio before user action
    /// @param ratio_ token ratio after user action
    /// @param packedWeight_ packed weight
    function _checkBands(uint256 prevRatio_, uint256 ratio_, uint256 packedWeight_) internal pure {
        uint256 _weight = FixedPointMathLib.rawMul(packedWeight_ & WEIGHT_MASK, WEIGHT_SCALE);

        // lower limit check
        uint256 limit = FixedPointMathLib.rawMul((packedWeight_ >> LOWER_BAND_SHIFT) & WEIGHT_MASK, WEIGHT_SCALE);
        if (limit > _weight) {
            limit = 0;
        } else {
            limit = FixedPointMathLib.rawSub(_weight, limit);
        }
        if (ratio_ < limit) {
            if (ratio_ <= prevRatio_) {
                revert Pool__RatioBelowLowerBound();
            }
            return;
        }

        // upper limit check
        limit = FixedPointMathLib.min(
            FixedPointMathLib.rawAdd(_weight, FixedPointMathLib.rawMul(packedWeight_ >> UPPER_BAND_SHIFT, WEIGHT_SCALE)),
            PRECISION
        );
        if (ratio_ > limit) {
            if (ratio_ >= prevRatio_) {
                revert Pool__RatioAboveUpperBound();
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MATH FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice calculate product term (pi) and sum term (sigma)
    /// @return tuple with product and sum term
    function _calculateVirtualBalanceProdSum() internal view returns (uint256, uint256) {
        uint256 s = 0;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == numTokens) {
                break;
            }
            s = FixedPointMathLib.rawAdd(s, packedVirtualBalances[t] & VB_MASK);
        }
        uint256 p = _calculateVirtualBalanceProd(s);
        return (p, s);
    }

    /// @notice calculate product term (pi)
    /// @param supply_ supply to use in product term
    /// @return product term
    function _calculateVirtualBalanceProd(uint256 supply_) internal view returns (uint256) {
        uint256 _numTokens = numTokens;
        uint256 _p = PRECISION;
        for (uint256 t = 0; t < MAX_NUM_TOKENS; ++t) {
            if (t == _numTokens) {
                break;
            }
            uint256 _virtualBalance;
            uint256 _packedWeight;
            (_virtualBalance,, _packedWeight) = _unpackVirtualBalance(packedVirtualBalances[t]);
            uint256 _weight = _unpackWeightTimesN(_packedWeight, 1);

            if (!(_weight > 0 && _virtualBalance > 0)) revert Pool__InvalidParams();

            // p = product((D * w_i / vb_i)^(w_i * n))
            _p = FixedPointMathLib.rawDiv(
                FixedPointMathLib.rawMul(
                    _p,
                    _powDown(
                        FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(supply_, _weight), _virtualBalance),
                        FixedPointMathLib.rawMul(_weight, _numTokens)
                    )
                ),
                PRECISION
            );
        }
        return _p;
    }

    /// @notice calculate supply iteratively
    /// @param numTokens_ number of tokens in the pool
    /// @param supply_ supply as used in product term
    /// @param amplification_ amplification factor (A f^n)
    /// @param virtualBalanceProd_ product term (pi)
    /// @param virtualBalanceSum_ sum term (sigma)
    /// @param up_ whether to round up
    /// @return tuple with new supply and product term
    function _calculateSupply(
        uint256 numTokens_,
        uint256 supply_,
        uint256 amplification_,
        uint256 virtualBalanceProd_,
        uint256 virtualBalanceSum_,
        bool up_
    ) internal pure returns (uint256, uint256) {
        // D[m+1] = (A f^n sigma - D[m] pi[m] )) / (A f^n - 1)
        //        = (_l - _s _r) / _d

        uint256 _l = amplification_; // left: A f^n sigma
        uint256 _d = _l - PRECISION; // denominator: A f*n - 1
        _l = _l * virtualBalanceSum_;
        uint256 _s = supply_; // supply: D[m]
        uint256 _r = virtualBalanceProd_; // right: pi[m]

        for (uint256 i = 0; i < 256; i++) {
            if (!(_s > 0)) {
                revert Pool__InvalidParams();
            }
            uint256 _sp = FixedPointMathLib.rawDiv(FixedPointMathLib.rawSub(_l, FixedPointMathLib.rawMul(_s, _r)), _d); // D[m+1] = (_l - _s * _r) / _d
            // update product term pi[m+1] = (D[m+1]/D[m])^n pi(m)
            for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
                if (t == numTokens_) {
                    break;
                }
                _r = FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(_r, _sp), _s); // _r * _sp / _s
            }
            uint256 _delta = 0;
            if (_sp >= _s) {
                _delta = FixedPointMathLib.rawSub(_sp, _s);
            } else {
                _delta = FixedPointMathLib.rawSub(_s, _sp);
            }

            if (FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(_delta, PRECISION), _s) <= MAX_POW_REL_ERR) {
                _delta = FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(_sp, MAX_POW_REL_ERR), PRECISION);
                if (up_) {
                    _sp += _delta;
                } else {
                    _sp -= _delta;
                }
                return (_sp, _r);
            }

            _s = _sp;
        }

        revert Pool__NoConvergence();
    }

    /// @notice calculate a single token's virtual balance iteratively using newton's method
    /// @param wn_ token weight times number of tokens
    /// @param y_ starting value
    /// @param supply_ supply
    /// @param amplification_ amplification factor `A f^n`
    /// @param vbProd_ intermediary product term (pi~), pi with previous balances factored out and new balance factored in
    /// @param vbSum_ intermediary sum term (sigma~), sigma with previous balances subtracted and new balance added
    /// @return new token virtual balance
    function _calculateVirtualBalance(
        uint256 wn_,
        uint256 y_,
        uint256 supply_,
        uint256 amplification_,
        uint256 vbProd_,
        uint256 vbSum_
    ) internal pure returns (uint256) {
        // y = x_j, sum' = sum(x_i, i != j), prod' = D^n w_j^(v_j) prod((w_i/x_i)^v_i, i != j)
        // Iteratively find root of g(y) using Newton's method
        // g(y) = y^(v_j + 1) + (sum' + (1 / (A f^n) - 1) D) y^(v_j) - D prod' / (A f^n)
        //      = y^(v_j + 1) + b y^(v_j) - c
        // y[n+1] = y[n] - g(y[n])/g'(y[n])
        //        = (y[n]^2 + b (1 - q) y[n] + c q y[n]^(1 - v_j)) / ((q + 1) y[n] + b))

        uint256 b = (supply_ * PRECISION) / amplification_; // b' = sigma + D / (A f^n)
        uint256 c = (vbProd_ * b) / PRECISION; // c' = D / (A f^n) * pi
        b += vbSum_;
        uint256 q = (PRECISION * PRECISION) / wn_; // q = 1 / v_i = 1 / (w_i n)

        uint256 y = y_;
        for (uint256 i = 0; i < 256; i++) {
            if (!(y > 0)) revert Pool__InvalidParams();

            uint256 yp = (y + b + supply_ * q / PRECISION + c * q / _powUp(y, wn_) - b * q / PRECISION - supply_) * y
                / (q * y / PRECISION + y + b - supply_);
            uint256 delta = 0;
            if (yp >= y) {
                delta = yp - y;
            } else {
                delta = y - yp;
            }

            if (FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(delta, PRECISION), y) <= MAX_POW_REL_ERR) {
                yp += FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(yp, MAX_POW_REL_ERR), PRECISION);
                return yp;
            }
            y = yp;
        }

        revert Pool__NoConvergence();
    }

    /// @notice pack virtual balance of a token along with other related variables
    /// @param virtualBalance_ virtual balance of a token
    /// @param rate_ token rate
    /// @param packedWeight_ packed weight of a token
    /// @return packed variable
    function _packVirtualBalance(uint256 virtualBalance_, uint256 rate_, uint256 packedWeight_)
        internal
        pure
        returns (uint256)
    {
        if (virtualBalance_ > VB_MASK || rate_ > RATE_MASK) {
            revert Pool__InvalidParams();
        }

        return virtualBalance_ | (rate_ << RATE_SHIFT) | (packedWeight_ << PACKED_WEIGHT_SHIFT);
    }

    /// @notice unpack variable to it's components
    /// @param packed_ packed variable
    /// @return tuple with virtual balance, rate and packed weight
    function _unpackVirtualBalance(uint256 packed_) internal pure returns (uint256, uint256, uint256) {
        return (packed_ & VB_MASK, (packed_ >> RATE_SHIFT) & RATE_MASK, packed_ >> PACKED_WEIGHT_SHIFT);
    }

    /// @notice pack weight with target and bands
    /// @param weight_ weight with 18 decimals
    /// @param target_ target weight with 18 decimals
    /// @param lower_ lower band with 18 decimals, allowed distance from weight in negative direction
    /// @param upper_ upper band with 18 decimal, allowed distance  from weight in positive direction
    function _packWeight(uint256 weight_, uint256 target_, uint256 lower_, uint256 upper_)
        internal
        pure
        returns (uint256)
    {
        return (
            (FixedPointMathLib.rawDiv(weight_, WEIGHT_SCALE))
                | (FixedPointMathLib.rawDiv(target_, WEIGHT_SCALE) << TARGET_WEIGHT_SHIFT)
                | (FixedPointMathLib.rawDiv(lower_, WEIGHT_SCALE) << LOWER_BAND_SHIFT)
                | (FixedPointMathLib.rawDiv(upper_, WEIGHT_SCALE) << UPPER_BAND_SHIFT)
        );
    }

    /// @notice unpack weight to its components
    /// @param packed_ packed weight
    /// @return tuple with weight, target weight, lower band and upper band (all in 18 decimals)
    function _unpackWeight(uint256 packed_) internal pure returns (uint256, uint256, uint256, uint256) {
        return (
            FixedPointMathLib.rawMul(packed_ & WEIGHT_MASK, WEIGHT_SCALE),
            FixedPointMathLib.rawMul((packed_ >> TARGET_WEIGHT_SHIFT) & WEIGHT_MASK, WEIGHT_SCALE),
            FixedPointMathLib.rawMul((packed_ >> LOWER_BAND_SHIFT) & WEIGHT_MASK, WEIGHT_SCALE),
            FixedPointMathLib.rawMul(packed_ >> UPPER_BAND_SHIFT, WEIGHT_SCALE)
        );
    }

    /// @notice unpack weight and multiply by number of tokens
    /// @param packed_ packed weight
    /// @param numTokens_ number of tokens
    /// @return weight multiplied by number of tokens (18 decimals)
    function _unpackWeightTimesN(uint256 packed_, uint256 numTokens_) internal pure returns (uint256) {
        return FixedPointMathLib.rawMul(FixedPointMathLib.rawMul(packed_ & WEIGHT_MASK, WEIGHT_SCALE), numTokens_);
    }

    /// @notice pack pool product and sum term
    /// @param prod_ Product term (pi)
    /// @param sum_ Sum term (sigma)
    /// @return packed term
    function _packPoolVirtualBalance(uint256 prod_, uint256 sum_) internal pure returns (uint256) {
        if (prod_ <= POOL_VB_MASK && sum_ <= POOL_VB_MASK) {
            return prod_ | (sum_ << POOL_VB_SHIFT);
        }
        revert Pool__InvalidParams();
    }

    /// @notice unpack pool product and sum term
    /// @param packed_ packed terms
    /// @return tuple with pool product term (pi) and pool sum term (sigma)
    function _unpackPoolVirtualBalance(uint256 packed_) internal pure returns (uint256, uint256) {
        return (packed_ & POOL_VB_MASK, packed_ >> POOL_VB_SHIFT);
    }

    function _checkIfPaused() internal view {
        if (paused == true) {
            revert Pool__Paused();
        }
    }

    function _powUp(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 p = LogExpMath.pow(x, y);
        // uint256 p = FixedPointMathLib.rpow(x, y, 1);
        if (p == 0) return 0;
        // p + (p * MAX_POW_REL_ERR - 1) / PRECISION + 1
        return FixedPointMathLib.rawAdd(
            FixedPointMathLib.rawAdd(
                p,
                FixedPointMathLib.rawDiv(
                    FixedPointMathLib.rawSub(FixedPointMathLib.rawMul(p, MAX_POW_REL_ERR), 1), PRECISION
                )
            ),
            1
        );
    }

    function _powDown(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 p = LogExpMath.pow(x, y);
        // uint256 p = FixedPointMathLib.rpow(x, y, 1);
        if (p == 0) return 0;
        // (p * MAX_POW_REL_ERR - 1) / PRECISION + 1
        uint256 e = FixedPointMathLib.rawAdd(
            FixedPointMathLib.rawDiv(
                FixedPointMathLib.rawSub(FixedPointMathLib.rawMul(p, MAX_POW_REL_ERR), 1), PRECISION
            ),
            1
        );
        if (p < e) return 0;
        return FixedPointMathLib.rawSub(p, e);
    }
}