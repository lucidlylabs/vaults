// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {console} from "forge-std/console.sol";

import {Pool} from "../src/Pool.sol";
import {RateProvider} from "../src/RateProvider/RateProvider.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";

contract PoolEstimator {
    uint256 public constant PRECISION = 1_000_000_000_000_000_000;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public constant ALL_TOKENS_FLAG =
        14_528_991_250_861_404_666_834_535_435_384_615_765_856_667_510_756_806_797_353_855_100_662_256_435_713; // sum((i+1) << 8*i)
    uint256 public constant POOL_VB_MASK = 2 ** 128 - 1;
    uint128 public constant POOL_VB_SHIFT = 128;

    uint256 public constant VB_MASK = 2 ** 96 - 1;
    uint256 public constant RATE_MASK = 2 ** 80 - 1;
    uint128 public constant RATE_SHIFT = 96;
    uint128 public constant PACKED_WEIGHT_SHIFT = 176;

    uint256 public constant WEIGHT_SCALE = 1_000_000_000_000;
    uint256 public constant WEIGHT_MASK = 2 ** 20 - 1;
    uint128 public constant TARGET_WEIGHT_SHIFT = 20;
    uint128 public constant LOWER_BAND_SHIFT = 40;
    uint128 public constant UPPER_BAND_SHIFT = 60;

    uint256 constant MAX_POW_REL_ERR = 100; // 1e-16

    Pool public immutable pool;

    constructor(address pool_) {
        pool = Pool(pool_);
    }

    function getEffectiveAmplification() external view returns (uint256) {
        (uint256 vbProd, uint256 vbSum) = pool.virtualBalanceProdSum();

        uint256 amplification;
        uint256[] memory packedWeights = new uint256[](4);
        bool updated;
        // (amplification, vbProd, packedWeights, updated) =
        (amplification, vbProd, packedWeights, updated) = _getPackedWeights(vbProd, vbSum);

        uint256 numTokens = pool.numTokens();

        uint256 t = 0;
        while (t < MAX_NUM_TOKENS) {
            if (t == numTokens) break;

            uint256 weight = 0;
            if (updated) weight = packedWeights[t];
            else weight = pool.packedWeight(t);

            weight = _unpackWeightNumTokens(weight, 1);
            amplification = amplification * _powDown(weight, weight * numTokens) / PRECISION;
            t++;
        }

        return amplification;
    }

    function getEffectiveTargetAmplification() external view returns (uint256) {
        uint256 amplification = 0;

        if (pool.rampLastTime() == 0) {
            amplification = pool.amplification();
        } else {
            amplification = pool.targetAmplification();
        }

        uint256 numTokens = pool.numTokens();

        for (uint256 t = 0; t < MAX_NUM_TOKENS; t++) {
            if (t == numTokens) break;
            uint256 weight =
                FixedPointMathLib.rawMul((pool.packedWeight(t) >> TARGET_WEIGHT_SHIFT) & WEIGHT_MASK, WEIGHT_SCALE);
            amplification = amplification * _powDown(weight, weight * numTokens) / PRECISION;
        }

        return amplification;
    }

    function getOutputToken(uint256 inputToken, uint256 outputToken, uint256 tokenInAmount)
        external
        view
        returns (uint256)
    {
        uint256 numTokens = pool.numTokens();

        require(inputToken != outputToken, "input and output token are the same");
        require(inputToken < numTokens && outputToken < numTokens, "invalid token indexes");
        require(tokenInAmount > 0, "input amount must be > 0");

        // update rates for from and to tokens
        uint256 supply;
        uint256 amplification;
        (uint256 vbProd, uint256 vbSum) = pool.virtualBalanceProdSum();
        uint256[] memory packedWeights = new uint256[](numTokens);
        uint256[] memory rates = new uint256[](numTokens);

        (supply, amplification, vbProd, vbSum, packedWeights, rates) =
            _getRates(_add(inputToken, 1) | (_add(outputToken, 1) << 8), vbProd, vbSum);
        uint256 prevVbSum = vbSum;

        uint256 prevVbInputToken = pool.virtualBalance(inputToken) * rates[0] / pool.rate(inputToken);
        uint256 wnInputToken = _unpackWeightNumTokens(packedWeights[inputToken], numTokens);

        uint256 prevVbOutputToken = pool.virtualBalance(outputToken) * rates[1] / pool.rate(outputToken);
        uint256 wnOutputToken = _unpackWeightNumTokens(packedWeights[outputToken], numTokens);

        uint256 adjustedTokenInAmount = (tokenInAmount * pool.rateMultipliers(inputToken)) / PRECISION;

        uint256 feeInputToken = adjustedTokenInAmount * pool.swapFeeRate() / PRECISION;
        uint256 dVbInputToken = (adjustedTokenInAmount - feeInputToken) * rates[0] / PRECISION;
        uint256 vbInputToken = prevVbInputToken + dVbInputToken;

        // update x_i and remove x_j from variables
        vbProd = vbProd * _powUp(prevVbOutputToken, wnOutputToken)
            / _powDown(vbInputToken * PRECISION / prevVbInputToken, wnInputToken);
        vbSum = vbSum + dVbInputToken - prevVbOutputToken;

        // calculate new balance of out token
        uint256 vbOutputToken =
            _calculateVirtualBalance(wnOutputToken, prevVbOutputToken, supply, amplification, vbProd, vbSum);

        vbSum += vbOutputToken + feeInputToken * rates[0] / PRECISION;

        _checkBands(
            prevVbInputToken * PRECISION / prevVbSum, vbInputToken * PRECISION / vbSum, packedWeights[inputToken]
        );
        _checkBands(
            prevVbOutputToken * PRECISION / prevVbSum, vbOutputToken * PRECISION / vbSum, packedWeights[outputToken]
        );

        uint256 adjustedTokenOutAmount = (prevVbOutputToken - vbOutputToken) * PRECISION / rates[1];
        return (adjustedTokenOutAmount * PRECISION) / pool.rateMultipliers(outputToken);
    }

    function getAddLp(uint256[] memory amounts_) external view returns (uint256) {
        uint256 numTokens = pool.numTokens();
        if (amounts_.length != numTokens) revert("invalid length of input array");

        (uint256 virtualBalanceProd, uint256 virtualBalanceSum) = pool.virtualBalanceProdSum();

        require(virtualBalanceSum > 0, "vbSum is equal to 0"); // neglect estimates for the first deposits

        // find lowest relative increase in balance
        uint256 tokens = 0;
        uint256 lowest = type(uint256).max;
        uint256 sh = 0;

        for (uint256 i = 0; i < MAX_NUM_TOKENS; i++) {
            if (i == numTokens) break;

            if (amounts_[i] > 0) {
                uint256 adjustedAmount = (amounts_[i] * pool.rateMultipliers(i)) / PRECISION;
                tokens = tokens | (_add(i, 1) << sh);
                sh = _add(sh, 8);
                if (virtualBalanceSum > 0 && lowest > 0) {
                    lowest = FixedPointMathLib.min(adjustedAmount * pool.rate(i) / pool.virtualBalance(i), lowest);
                }
            } else {
                lowest = 0;
            }
        }

        require(sh > 0, "need to deposit at least 1 token");

        // update rates
        uint256 prevSupply;
        uint256 amplification;
        uint256[] memory packedWeights = new uint256[](MAX_NUM_TOKENS);
        uint256[] memory rates = new uint256[](MAX_NUM_TOKENS);

        (prevSupply, amplification, virtualBalanceProd, virtualBalanceSum, packedWeights, rates) =
            _getRates(tokens, virtualBalanceProd, virtualBalanceSum);

        uint256 virtualBalanceProdFinal = virtualBalanceProd;
        uint256 virtualBalanceSumFinal = virtualBalanceSum;
        uint256 prevVirtualBalanceSum = virtualBalanceSum;
        uint256[] memory balances = new uint256[](MAX_NUM_TOKENS);
        uint256 j = 0;
        for (uint256 i = 0; i <= MAX_NUM_TOKENS; i++) {
            if (i == numTokens) break;

            uint256 amount = amounts_[i];
            if (amount == 0) continue;
            uint256 adjustedAmount = (amount * pool.rateMultipliers(i)) / PRECISION;

            uint256 prevVirtualBalance = pool.virtualBalance(i) * rates[j] / pool.rate(i);

            uint256 deltaVirtualBalance = adjustedAmount * rates[j] / PRECISION;
            uint256 virtualBalance = prevVirtualBalance + deltaVirtualBalance;
            balances[i] = virtualBalance;

            if (prevSupply > 0) {
                uint256 wn = _unpackWeightNumTokens(packedWeights[i], numTokens);

                // update product and sum of virtual balances
                virtualBalanceProdFinal =
                    virtualBalanceProdFinal * _powUp(prevVirtualBalance * PRECISION / virtualBalance, wn) / PRECISION;

                // the `D^n` factor will be updated in `_calculateSupply()`
                virtualBalanceSumFinal += deltaVirtualBalance;

                // remove fees from balance and recalculate sum and product
                uint256 fee = (deltaVirtualBalance - prevVirtualBalance * lowest / PRECISION) * (pool.swapFeeRate() / 2)
                    / PRECISION;
                virtualBalanceProd =
                    virtualBalanceProd * _powUp(prevVirtualBalance * PRECISION / (virtualBalance - fee), wn) / PRECISION;
                virtualBalanceSum += deltaVirtualBalance - fee;
            }
            j = _add(j, 1);
        }

        // check bands
        j = 0;
        for (uint256 i = 0; i < MAX_NUM_TOKENS; i++) {
            if (i == numTokens) {
                break;
            }
            if (amounts_[i] == 0) {
                continue;
            }

            _checkBands(
                pool.virtualBalance(i) * rates[j] / pool.rate(i) * PRECISION / prevVirtualBalanceSum,
                balances[j] * PRECISION / virtualBalanceSumFinal,
                packedWeights[i]
            );
            j = _add(j, 1);
        }

        uint256 supply = 0;
        (supply,) = _calculateSupply(
            numTokens, prevSupply, amplification, virtualBalanceProd, virtualBalanceSum, prevSupply == 0
        );

        return supply - prevSupply;
    }

    function getRemoveLp(uint256 lpAmount) external view returns (uint256[] memory) {
        uint256 numTokens = pool.numTokens();
        uint256 prevSupply = pool.supply();

        require(lpAmount <= prevSupply, "logical error");

        uint256[] memory amounts = new uint256[](numTokens);

        for (uint256 i = 0; i < MAX_NUM_TOKENS; i++) {
            if (i == numTokens) break;

            uint256 prevBalance = pool.virtualBalance(i);
            uint256 dBalance = prevBalance * lpAmount / prevSupply;
            uint256 amount = dBalance * PRECISION / pool.rate(i);
            amounts[i] = FixedPointMathLib.divWad(amount, pool.rateMultipliers(i));
        }

        return amounts;
    }

    function getRemoveSingleLp(uint256 token, uint256 lpAmount) external view returns (uint256) {
        uint256 numTokens = pool.numTokens();
        require(token < numTokens, "index out of bounds");

        // update rate
        uint256 prevSupply;
        uint256 amplification;
        (uint256 vbProd, uint256 vbSum) = pool.virtualBalanceProdSum();
        uint256[] memory packedWeights = new uint256[](numTokens);
        uint256[] memory rates = new uint256[](numTokens);

        (prevSupply, amplification, vbProd, vbSum, packedWeights, rates) = _getRates(_add(token, 1), vbProd, vbSum);
        uint256 prevVbSum = vbSum;

        uint256 supply = prevSupply - lpAmount;
        uint256 prevVb = pool.virtualBalance(token) * rates[0] / pool.rate(token);
        uint256 wn = _unpackWeightNumTokens(packedWeights[token], numTokens);

        // update variables
        vbProd = vbProd * _powUp(prevVb, wn) / PRECISION;
        for (uint256 i = 0; i < MAX_NUM_TOKENS; i++) {
            if (i == numTokens) break;
            vbProd = vbProd * supply / prevSupply;
        }
        vbSum = vbSum - prevVb;

        // calculate new balance of token
        uint256 vb = _calculateVirtualBalance(wn, prevVb, supply, amplification, vbProd, vbSum);
        uint256 dVb = prevVb - vb;
        uint256 fee = dVb * pool.swapFeeRate() / 2 / PRECISION;

        dVb -= fee;
        vb += fee;
        uint256 tokenOutAmount = dVb * PRECISION / rates[0];
        vbSum = vbSum + vb;

        for (uint256 i = 0; i < MAX_NUM_TOKENS; i++) {
            if (i == numTokens) break;

            if (i == token) {
                _checkBands(prevVb * PRECISION / prevVbSum, vb * PRECISION / vbSum, packedWeights[i]);
            } else {
                uint256 balance = pool.virtualBalance(i);
                _checkBands(balance * PRECISION / prevVbSum, balance * PRECISION / vbSum, packedWeights[i]);
            }
        }

        return (tokenOutAmount * PRECISION) / pool.rateMultipliers(token);
    }

    function getVirtualBalance(uint256[] memory amounts_) external view returns (uint256) {
        require(amounts_.length <= MAX_NUM_TOKENS, "Invalid amounts_ length");
        uint256 numTokens = pool.numTokens();

        uint256 virtualBalance;
        for (uint256 t = 0; t <= MAX_NUM_TOKENS; t++) {
            if (t == numTokens) break;
            uint256 amount = amounts_[t];
            if (amount == 0) continue;

            address provider = pool.rateProviders(t);
            uint256 rate = RateProvider(provider).rate(pool.tokens(t));
            virtualBalance += amount * rate / PRECISION;
        }

        return virtualBalance;
    }

    function _getRates(uint256 tokens_, uint256 virtualBalanceProd_, uint256 virtualBalanceSum_)
        internal
        view
        returns (uint256, uint256, uint256, uint256, uint256[] memory, uint256[] memory)
    {
        uint256[] memory packedWeights = new uint256[](MAX_NUM_TOKENS);
        uint256[] memory rates = new uint256[](MAX_NUM_TOKENS);

        uint256 amplification;
        uint256 virtualBalanceProd;
        uint256 virtualBalanceSum = virtualBalanceSum_;
        bool updated;
        (amplification, virtualBalanceProd, packedWeights, updated) =
            _getPackedWeights(virtualBalanceProd_, virtualBalanceSum_);
        uint256 numTokens = pool.numTokens();

        if (!updated) {
            for (uint256 t = 0; t <= MAX_NUM_TOKENS; t++) {
                if (t == numTokens) break;
                packedWeights[t] = pool.packedWeight(t);
            }
        }

        for (uint256 t = 0; t <= MAX_NUM_TOKENS; t++) {
            uint256 token = (tokens_ >> (8 * t)) & 255;
            if (token == 0 || token > numTokens) break;
            token = _sub(token, 1);
            address provider = pool.rateProviders(token);
            uint256 prevRate = pool.rate(token);
            uint256 rate = RateProvider(provider).rate(pool.tokens(token));
            require(rate > 0, "no rate");
            rates[t] = rate;

            if (rate == prevRate) continue;

            if (prevRate > 0 && virtualBalanceSum > 0) {
                // factor out old rate and factor in new
                uint256 wn = _unpackWeightNumTokens(packedWeights[token], numTokens);
                virtualBalanceProd = virtualBalanceProd * _powUp(prevRate * PRECISION / rate, wn) / PRECISION;

                uint256 prevBalance = pool.virtualBalance(token);
                uint256 balance = prevBalance * rate / prevRate;

                virtualBalanceSum = virtualBalanceSum + balance - prevBalance;
            }
        }

        if (!updated && virtualBalanceProd == virtualBalanceProd_ && virtualBalanceSum == virtualBalanceSum_) {
            return (pool.supply(), amplification, virtualBalanceProd, virtualBalanceSum, packedWeights, rates);
        }

        uint256 supply;
        (supply, virtualBalanceProd) =
            _calculateSupply(numTokens, pool.supply(), amplification, virtualBalanceProd, virtualBalanceSum, true);
        return (supply, amplification, virtualBalanceProd, virtualBalanceSum, packedWeights, rates);
    }

    function _calculateVirtualBalance(
        uint256 wn,
        uint256 y,
        uint256 supply,
        uint256 amplification,
        uint256 vbProd,
        uint256 vbSum
    ) internal pure returns (uint256) {
        // y = x_j, sum' = sum(x_i, i != j), prod' = prod(x_i^w_i, i != j)
        // w = product(w_i), v_i = w_i n, f_i = 1/v_i
        // Iteratively find root of g(y) using Newton's method
        // g(y) = y^(v_j + 1) + (sum' + (w^n / A - 1) D y^(w_j n) - D^(n+1) w^2n / prod'^n
        //      = y^(v_j + 1) + b y^(v_j) - c
        // y[n+1] = y[n] - g(y[n])/g'(y[n])
        //        = (y[n]^2 + b (1 - f_j) y[n] + c f_j y[n]^(1 - v_j)) / (f_j + 1) y[n] + b)

        uint256 d = supply;
        uint256 b = d * PRECISION / amplification; // actually b + D
        uint256 c = vbProd * b / PRECISION;
        b += vbSum;
        uint256 f = PRECISION * PRECISION / wn;

        uint256 __y = y;
        for (uint256 i = 0; i < 256; i++) {
            uint256 yp = (__y + b + d * f / PRECISION + c * f / _powUp(__y, wn) - b * f / PRECISION - d) * __y
                / (f * __y / PRECISION + __y + b - d);
            if (yp >= __y) {
                if ((yp - __y) * PRECISION / __y <= MAX_POW_REL_ERR) {
                    yp += yp * MAX_POW_REL_ERR / PRECISION;
                    return yp;
                }
            } else {
                if ((__y - yp) * PRECISION / __y <= MAX_POW_REL_ERR) {
                    yp += yp * MAX_POW_REL_ERR / PRECISION;
                    return yp;
                }
            }
            __y = yp;
        }

        revert("No Convergence");
    }

    function _calculateSupply(
        uint256 numTokens_,
        uint256 supply_,
        uint256 amplification_,
        uint256 vbProd_,
        uint256 vbSum_,
        bool up_
    ) internal pure returns (uint256, uint256) {
        // s[n+1] = (A sum / w^n - s^(n+1) w^n /prod^n)) / (A w^n - 1)
        //        = (l - s r) / d

        uint256 l = amplification_;
        uint256 d = l - PRECISION;
        uint256 s = supply_;
        uint256 r = vbProd_;
        l = l * vbSum_;

        uint256 numTokens = numTokens_;
        for (uint256 i = 0; i < 256; i++) {
            uint256 sp = _div(_sub(l, _mul(s, r)), d); // (l - s * r) / d

            for (uint256 j = 0; j <= MAX_NUM_TOKENS; j++) {
                if (j == numTokens) break;

                r = _div(_mul(r, sp), s); // r * sp / s
            }
            if (sp >= s) {
                if ((sp - s) * PRECISION / s <= MAX_POW_REL_ERR) {
                    if (up_) {
                        sp += sp * MAX_POW_REL_ERR / PRECISION;
                    } else {
                        sp -= sp * MAX_POW_REL_ERR / PRECISION;
                    }
                    return (sp, r);
                }
            } else {
                if ((s - sp) * PRECISION / s <= MAX_POW_REL_ERR) {
                    if (up_) {
                        sp += sp * MAX_POW_REL_ERR / PRECISION;
                    } else {
                        sp -= sp * MAX_POW_REL_ERR / PRECISION;
                    }
                    return (sp, r);
                }
            }
            s = sp;
        }

        revert("no convergence");
    }

    function _getPackedWeights(uint256 virtualBalanceProd_, uint256 virtualBalanceSum_)
        internal
        view
        returns (uint256, uint256, uint256[] memory, bool)
    {
        uint256[] memory _packedWeights = new uint256[](4);
        uint256 span = pool.rampLastTime();
        uint256 duration = pool.rampStopTime();

        if (
            span == 0 || span > block.timestamp
                || (block.timestamp - span < pool.rampStep() && duration > block.timestamp)
        ) {
            return (pool.amplification(), virtualBalanceProd_, _packedWeights, false);
        }

        if (block.timestamp < duration) {
            // ramp in progress
            duration -= span;
        } else {
            // ramp has finished
            duration = 0;
        }
        span = block.timestamp - span;

        // update amplification
        uint256 current = pool.amplification();
        uint256 target = pool.targetAmplification();

        if (duration == 0) {
            current = target;
        } else {
            if (current > target) {
                current = current - (current - target) * span / duration;
            } else {
                current = current + (target - current) * span / duration;
            }
        }
        uint256 amplification = current;

        // update weights
        uint256 numTokens = pool.numTokens();
        uint256 supply = pool.supply();
        uint256 virtualBalanceProd = 0;

        if (virtualBalanceSum_ > 0) {
            virtualBalanceProd = PRECISION;
        }
        uint256 lower;
        uint256 upper;
        for (uint256 t = 0; t <= MAX_NUM_TOKENS; t++) {
            if (t == numTokens) break;
            (current, target, lower, upper) = pool.weight(t);
            if (duration == 0) {
                current = target;
            } else {
                if (current > target) current -= (current - target) * span / duration;
                else current += (target - current) * span / duration;
            }
            _packedWeights[t] = _packWeight(current, target, lower, upper);
            if (virtualBalanceSum_ > 0) {
                virtualBalanceProd = FixedPointMathLib.rawDiv(
                    FixedPointMathLib.rawMul(
                        virtualBalanceProd,
                        _powDown(
                            FixedPointMathLib.rawDiv(FixedPointMathLib.rawMul(supply, current), pool.virtualBalance(t)),
                            FixedPointMathLib.rawMul(current, numTokens)
                        )
                    ),
                    PRECISION
                );
            }
        }

        return (amplification, virtualBalanceProd, _packedWeights, true);
    }

    function _checkBands(uint256 prevRatio_, uint256 ratio_, uint256 packedWeight_) internal pure {
        uint256 _weight = _mul(packedWeight_ & WEIGHT_MASK, WEIGHT_SCALE);

        // lower limit check
        uint256 limit = _mul((packedWeight_ >> LOWER_BAND_SHIFT) & WEIGHT_MASK, WEIGHT_SCALE);
        if (limit > _weight) {
            limit = 0;
        } else {
            limit = _sub(_weight, limit);
        }
        if (ratio_ < limit) {
            require(ratio_ > prevRatio_, "ratio below lower band");
        }

        // upper limit check
        limit = FixedPointMathLib.min(_add(_weight, _mul((packedWeight_ >> UPPER_BAND_SHIFT), WEIGHT_SCALE)), PRECISION);
        if (ratio_ > limit) {
            require(ratio_ < prevRatio_, "ratio above upper band");
        }
    }

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

    function _unpackWeightNumTokens(uint256 packed_, uint256 numTokens_) internal pure returns (uint256) {
        return FixedPointMathLib.rawMul(FixedPointMathLib.rawMul(packed_ & WEIGHT_MASK, WEIGHT_SCALE), numTokens_);
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

    function _add(uint256 x, uint256 y) internal pure returns (uint256) {
        return FixedPointMathLib.rawAdd(x, y);
    }

    function _sub(uint256 x, uint256 y) internal pure returns (uint256) {
        return FixedPointMathLib.rawSub(x, y);
    }

    function _mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return FixedPointMathLib.rawMul(x, y);
    }

    function _div(uint256 x, uint256 y) internal pure returns (uint256) {
        return FixedPointMathLib.rawDiv(x, y);
    }
}
