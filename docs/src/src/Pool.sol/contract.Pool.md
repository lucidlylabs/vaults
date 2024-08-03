# Pool
[Git Source](https://github.com/lucidlyfi/MasterVaultCode/blob/e89626c00c676e7b87a7121ad91042902a96f6d2/src/Pool.sol)

**Inherits:**
Ownable, ReentrancyGuard


## State Variables
### PRECISION

```solidity
uint256 constant PRECISION = 1_000_000_000_000_000_000;
```


### MAX_NUM_TOKENS

```solidity
uint256 constant MAX_NUM_TOKENS = 32;
```


### ALL_TOKENS_FLAG

```solidity
uint256 constant ALL_TOKENS_FLAG =
    14_528_991_250_861_404_666_834_535_435_384_615_765_856_667_510_756_806_797_353_855_100_662_256_435_713;
```


### POOL_VB_MASK

```solidity
uint256 constant POOL_VB_MASK = 2 ** 128 - 1;
```


### POOL_VB_SHIFT

```solidity
uint128 constant POOL_VB_SHIFT = 128;
```


### VB_MASK

```solidity
uint256 constant VB_MASK = 2 ** 96 - 1;
```


### RATE_MASK

```solidity
uint256 constant RATE_MASK = 2 ** 80 - 1;
```


### RATE_SHIFT

```solidity
uint128 constant RATE_SHIFT = 96;
```


### PACKED_WEIGHT_SHIFT

```solidity
uint128 constant PACKED_WEIGHT_SHIFT = 176;
```


### WEIGHT_SCALE

```solidity
uint256 constant WEIGHT_SCALE = 1_000_000_000_000;
```


### WEIGHT_MASK

```solidity
uint256 constant WEIGHT_MASK = 2 ** 20 - 1;
```


### TARGET_WEIGHT_SHIFT

```solidity
uint128 constant TARGET_WEIGHT_SHIFT = 20;
```


### LOWER_BAND_SHIFT

```solidity
uint128 constant LOWER_BAND_SHIFT = 40;
```


### UPPER_BAND_SHIFT

```solidity
uint128 constant UPPER_BAND_SHIFT = 60;
```


### MAX_POW_REL_ERR

```solidity
uint256 constant MAX_POW_REL_ERR = 100;
```


### amplification

```solidity
uint256 public amplification;
```


### numTokens

```solidity
uint256 public numTokens;
```


### supply

```solidity
uint256 public supply;
```


### tokenAddress

```solidity
address public tokenAddress;
```


### stakingAddress

```solidity
address public stakingAddress;
```


### tokens

```solidity
address[MAX_NUM_TOKENS] public tokens;
```


### rateProviders

```solidity
address[MAX_NUM_TOKENS] public rateProviders;
```


### packedVirtualBalances

```solidity
uint256[MAX_NUM_TOKENS] public packedVirtualBalances;
```


### paused

```solidity
bool public paused;
```


### killed

```solidity
bool public killed;
```


### swapFeeRate

```solidity
uint256 public swapFeeRate;
```


### rampStep

```solidity
uint256 public rampStep;
```


### rampLastTime

```solidity
uint256 public rampLastTime;
```


### rampStopTime

```solidity
uint256 public rampStopTime;
```


### targetAmplification

```solidity
uint256 public targetAmplification;
```


### packedPoolVirtualBalance

```solidity
uint256 packedPoolVirtualBalance;
```


## Functions
### constructor

constructor

*sum of all weights*

*rebasing tokens not supported*


```solidity
constructor(
    address tokenAddress_,
    uint256 amplification_,
    address[] memory tokens_,
    address[] memory rateProviders_,
    uint256[] memory weights_,
    address owner_
);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenAddress_`|`address`|address of the poolToken|
|`amplification_`|`uint256`|the pool amplification factor (in 18 decimals)|
|`tokens_`|`address[]`|array of addresses of tokens in the pool|
|`rateProviders_`|`address[]`|array of addresses of rate providers for the tokens in the pool|
|`weights_`|`uint256[]`|weight of each token (in 18 decimals)|
|`owner_`|`address`||


### swap

swap one pool token for another


```solidity
function swap(
    uint256 tokenIn_,
    uint256 tokenOut_,
    uint256 tokenInAmount_,
    uint256 minTokenOutAmount_,
    address receiver_
) external nonReentrant returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIn_`|`uint256`|index of the input token|
|`tokenOut_`|`uint256`|index of the output token|
|`tokenInAmount_`|`uint256`|amount of input token to take from the caller|
|`minTokenOutAmount_`|`uint256`|minimum amount of output token to send|
|`receiver_`|`address`|account to receive the output token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|the amount of output token|


### addLiquidity

deposit tokens into the pool


```solidity
function addLiquidity(uint256[] calldata amounts_, uint256 minLpAmount_, address receiver_)
    external
    nonReentrant
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amounts_`|`uint256[]`|array of the amount for each token to take from caller|
|`minLpAmount_`|`uint256`|minimum amount of lp tokens to mint|
|`receiver_`|`address`|account to receive the lp tokens|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|amount of LP tokens minted|


### removeLiquidity

withdraw tokens from the pool in a balanced manner


```solidity
function removeLiquidity(uint256 lpAmount_, uint256[] calldata minAmounts_, address receiver_) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`lpAmount_`|`uint256`|amount of lp tokens to burn|
|`minAmounts_`|`uint256[]`|array of minimum amount of each token to send|
|`receiver_`|`address`|account to receive the tokens|


### removeLiquiditySingle

withdraw a single token from the pool


```solidity
function removeLiquiditySingle(uint256 token_, uint256 lpAmount_, uint256 minTokenOutAmount_, address receiver_)
    external
    nonReentrant
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`uint256`|index of the token to withdraw|
|`lpAmount_`|`uint256`|amount of lp tokens to burn|
|`minTokenOutAmount_`|`uint256`|minimum amount of tokens to send|
|`receiver_`|`address`|account to receive the token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|the amount of the token sent|


### updateRates

update the stored rate of any of the pool's tokens

*if no assets are passed in, every asset will be updated*


```solidity
function updateRates(uint256[] calldata tokens_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokens_`|`uint256[]`|array of indices of tokens to update|


### updateWeights

update weights and amplification factor, if possible

*will only update the weights if a ramp is active and at least the minimum time step has been reached*


```solidity
function updateWeights() external returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|boolean to indicate whether the weights and amplification factor have been updated|


### virtualBalanceProdSum

get the pool's virtual balance product (pi) and sum (sigma)


```solidity
function virtualBalanceProdSum() external view returns (uint256, uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with product and sum|
|`<none>`|`uint256`||


### virtualBalance

get the virtual balance of a token


```solidity
function virtualBalance(uint256 token_) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`uint256`|index of the token in the pool|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|virtual balance of the token|


### rate

get the rate of an token


```solidity
function rate(uint256 token_) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`uint256`|index of the token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|rate of the token|


### weight

get the weight of a token

*does not take into account any active ramp*


```solidity
function weight(uint256 token_) external view returns (uint256, uint256, uint256, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`uint256`|index of the token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with weight, target weight, lower band width, upper weight band width|
|`<none>`|`uint256`||
|`<none>`|`uint256`||
|`<none>`|`uint256`||


### packedWeight

get the packed weight of a token in a packed format

*does not take into account any active ramp*


```solidity
function packedWeight(uint256 token_) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`uint256`|index of the token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|weight in packed format|


### pause

pause the pool


```solidity
function pause() external onlyOwner;
```

### unpause

unpause the pool


```solidity
function unpause() external onlyOwner;
```

### kill

kill the pool


```solidity
function kill() external onlyOwner;
```

### addToken

add a new token to the pool

*can only be called if no ramp is currently active*

*every other token will their weight reduced pro rata*

*caller should assure that amplification before and after the call are the same*


```solidity
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
) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`address`|address of the token to add|
|`rateProvider_`|`address`|rate provider for the token|
|`weight_`|`uint256`|weight of the new token|
|`lower_`|`uint256`|lower band width|
|`upper_`|`uint256`|upper band width|
|`amount_`|`uint256`|amount of tokens|
|`amplification_`|`uint256`|new pool amplification factor|
|`minLpAmount_`|`uint256`||
|`receiver_`|`address`|account to receive the lp tokens minted|


### rescue

rescue tokens from this contract

*cannot be used to rescue pool tokens*


```solidity
function rescue(address token_, address receiver_) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`address`|the token to be rescued|
|`receiver_`|`address`|receiver of the rescued tokens|


### skim

skim surplus of a pool token


```solidity
function skim(uint256 token_, address receiver_) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`uint256`|index of the token|
|`receiver_`|`address`|receiver of the skimmed tokens|


### setSwapFeeRate

set new swap fee rate


```solidity
function setSwapFeeRate(uint256 feeRate_) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`feeRate_`|`uint256`|new swap fee rate (in 18 decimals)|


### setWeightBands

set safeft weight bands, if any user operation puts the weight outside of the bands, the transaction will revert


```solidity
function setWeightBands(uint256[] calldata tokens_, uint256[] calldata lower_, uint256[] calldata upper_)
    external
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokens_`|`uint256[]`|array of indices of the tokens to set the bands for|
|`lower_`|`uint256[]`|array of widths of the lower band|
|`upper_`|`uint256[]`|array of widths of the upper band|


### setRateProvider

set a rate provider for a token


```solidity
function setRateProvider(uint256 token_, address rateProvider_) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token_`|`uint256`|index of the token|
|`rateProvider_`|`address`|new rate provider for the token|


### setRamp

schedule an amplification and/or weight change

*effective amplification at any time is `amplification/f^n`*


```solidity
function setRamp(uint256 amplification_, uint256[] calldata weights_, uint256 duration_, uint256 start_)
    external
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amplification_`|`uint256`|new amplification factor (in 18 decimals)|
|`weights_`|`uint256[]`|array of the new weight for each token (in 18 decimals)|
|`duration_`|`uint256`|duration of the ramp (in seconds)|
|`start_`|`uint256`|ramp start time|


### setRampStep

set the minimum time b/w ramp step


```solidity
function setRampStep(uint256 rampStep_) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`rampStep_`|`uint256`|minimum step time (in seconds)|


### stopRamp

stop an active ramp


```solidity
function stopRamp() external onlyOwner;
```

### setStaking

set the address that receives yield, slashings and swap fees


```solidity
function setStaking(address stakingAddress_) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`stakingAddress_`|`address`|new staking address|


### _updateRates

update rates of specific tokens

*loops through the bytes in `token_` until a zero or a number larger than the number of assets is encountered*

*update weights (if needed) prior to checking any rates*

*will recalculate supply and mint/burn to staking contract if any weight or rate has updated*

*will revert if any rate increases by more than 10%, unless called by management*


```solidity
function _updateRates(uint256 tokens_, uint256 virtualBalanceProd_, uint256 virtualBalanceSum_)
    internal
    returns (uint256, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokens_`|`uint256`|integer where each byte represents a token index offset by one|
|`virtualBalanceProd_`|`uint256`|product term (pi) before update|
|`virtualBalanceSum_`|`uint256`|sum term (sigma) before update|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with new product and sum term|
|`<none>`|`uint256`||


### _updateWeights

apply a step in amplitude and weight ramp, if applicable

*caller is reponsible for updating supply if a step has been taken*


```solidity
function _updateWeights(uint256 vbProd_) internal returns (uint256, bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vbProd_`|`uint256`|product term(pi) before update|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with new product term and flag indicating if a step has been taken|
|`<none>`|`bool`||


### _updateSupply

calculate supply and burn or mint difference from the staking contract


```solidity
function _updateSupply(uint256 supply_, uint256 vbProd_, uint256 vbSum_) internal returns (uint256, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`supply_`|`uint256`|previous supply|
|`vbProd_`|`uint256`|product term (pi)|
|`vbSum_`|`uint256`|sum term (sigma)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with new supply and product term|
|`<none>`|`uint256`||


### _checkBands

check whether asset is within safety band, or if previously outside, moves closer to it

*reverts if conditions are not met*


```solidity
function _checkBands(uint256 prevRatio_, uint256 ratio_, uint256 packedWeight_) internal pure;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`prevRatio_`|`uint256`|token ratio before user action|
|`ratio_`|`uint256`|token ratio after user action|
|`packedWeight_`|`uint256`|packed weight|


### _calculateVirtualBalanceProdSum

calculate product term (pi) and sum term (sigma)


```solidity
function _calculateVirtualBalanceProdSum() internal view returns (uint256, uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with product and sum term|
|`<none>`|`uint256`||


### _calculateVirtualBalanceProd

calculate product term (pi)


```solidity
function _calculateVirtualBalanceProd(uint256 supply_) internal view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`supply_`|`uint256`|supply to use in product term|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|product term|


### _calculateSupply

calculate supply iteratively


```solidity
function _calculateSupply(
    uint256 numTokens_,
    uint256 supply_,
    uint256 amplification_,
    uint256 virtualBalanceProd_,
    uint256 virtualBalanceSum_,
    bool up_
) internal pure returns (uint256, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`numTokens_`|`uint256`|number of tokens in the pool|
|`supply_`|`uint256`|supply as used in product term|
|`amplification_`|`uint256`|amplification factor (A f^n)|
|`virtualBalanceProd_`|`uint256`|product term (pi)|
|`virtualBalanceSum_`|`uint256`|sum term (sigma)|
|`up_`|`bool`|whether to round up|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with new supply and product term|
|`<none>`|`uint256`||


### _calculateVirtualBalance

calculate a single token's virtual balance iteratively using newton's method


```solidity
function _calculateVirtualBalance(
    uint256 wn_,
    uint256 y_,
    uint256 supply_,
    uint256 amplification_,
    uint256 vbProd_,
    uint256 vbSum_
) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`wn_`|`uint256`|token weight times number of tokens|
|`y_`|`uint256`|starting value|
|`supply_`|`uint256`|supply|
|`amplification_`|`uint256`|amplification factor `A f^n`|
|`vbProd_`|`uint256`|intermediary product term (pi~), pi with previous balances factored out and new balance factored in|
|`vbSum_`|`uint256`|intermediary sum term (sigma~), sigma with previous balances subtracted and new balance added|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|new token virtual balance|


### _packVirtualBalance

pack virtual balance of a token along with other related variables


```solidity
function _packVirtualBalance(uint256 virtualBalance_, uint256 rate_, uint256 packedWeight_)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`virtualBalance_`|`uint256`|virtual balance of a token|
|`rate_`|`uint256`|token rate|
|`packedWeight_`|`uint256`|packed weight of a token|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|packed variable|


### _unpackVirtualBalance

unpack variable to it's components


```solidity
function _unpackVirtualBalance(uint256 packed_) internal pure returns (uint256, uint256, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`packed_`|`uint256`|packed variable|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with virtual balance, rate and packed weight|
|`<none>`|`uint256`||
|`<none>`|`uint256`||


### _packWeight

pack weight with target and bands


```solidity
function _packWeight(uint256 weight_, uint256 target_, uint256 lower_, uint256 upper_)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`weight_`|`uint256`|weight with 18 decimals|
|`target_`|`uint256`|target weight with 18 decimals|
|`lower_`|`uint256`|lower band with 18 decimals, allowed distance from weight in negative direction|
|`upper_`|`uint256`|upper band with 18 decimal, allowed distance  from weight in positive direction|


### _unpackWeight

unpack weight to its components


```solidity
function _unpackWeight(uint256 packed_) internal pure returns (uint256, uint256, uint256, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`packed_`|`uint256`|packed weight|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with weight, target weight, lower band and upper band (all in 18 decimals)|
|`<none>`|`uint256`||
|`<none>`|`uint256`||
|`<none>`|`uint256`||


### _unpackWeightTimesN

unpack weight and multiply by number of tokens


```solidity
function _unpackWeightTimesN(uint256 packed_, uint256 numTokens_) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`packed_`|`uint256`|packed weight|
|`numTokens_`|`uint256`|number of tokens|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|weight multiplied by number of tokens (18 decimals)|


### _packPoolVirtualBalance

pack pool product and sum term


```solidity
function _packPoolVirtualBalance(uint256 prod_, uint256 sum_) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`prod_`|`uint256`|Product term (pi)|
|`sum_`|`uint256`|Sum term (sigma)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|packed term|


### _unpackPoolVirtualBalance

unpack pool product and sum term


```solidity
function _unpackPoolVirtualBalance(uint256 packed_) internal pure returns (uint256, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`packed_`|`uint256`|packed terms|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|tuple with pool product term (pi) and pool sum term (sigma)|
|`<none>`|`uint256`||


### _checkIfPaused


```solidity
function _checkIfPaused() internal view;
```

### _powUp


```solidity
function _powUp(uint256 x, uint256 y) internal pure returns (uint256);
```

### _powDown


```solidity
function _powDown(uint256 x, uint256 y) internal pure returns (uint256);
```

## Events
### Swap

```solidity
event Swap(
    address indexed caller, address receiver, uint256 tokenIn, uint256 tokenOut, uint256 amountIn, uint256 amountOut
);
```

### AddLiquidity

```solidity
event AddLiquidity(address indexed caller, address receiver, uint256[] amountsIn, uint256 lpAmount);
```

### RemoveLiquidity

```solidity
event RemoveLiquidity(address indexed caller, address receiver, uint256 lpAmount);
```

### RemoveLiquiditySingle

```solidity
event RemoveLiquiditySingle(
    address indexed caller, address receiver, uint256 token, uint256 amountOut, uint256 lpAmount
);
```

### RateUpdate

```solidity
event RateUpdate(uint256 indexed token, uint256 rate);
```

### Pause

```solidity
event Pause(address indexed caller);
```

### Unpause

```solidity
event Unpause(address indexed caller);
```

### Kill

```solidity
event Kill();
```

### AddToken

```solidity
event AddToken(uint256 index, address token, address rateProvider, uint256 rate, uint256 weight, uint256 amount);
```

### SetSwapFeeRate

```solidity
event SetSwapFeeRate(uint256 rate);
```

### SetWeightBand

```solidity
event SetWeightBand(uint256 indexed token, uint256 lower, uint256 upper);
```

### SetRateProvider

```solidity
event SetRateProvider(uint256 token, address rateProvider);
```

### SetRamp

```solidity
event SetRamp(uint256 amplification, uint256[] weights, uint256 duration, uint256 start);
```

### SetRampStep

```solidity
event SetRampStep(uint256 rampStep);
```

### StopRamp

```solidity
event StopRamp();
```

### SetStaking

```solidity
event SetStaking(address stakingAddress);
```

### SetGuardian

```solidity
event SetGuardian(address indexed caller, address guardian);
```

## Errors
### Pool__InputOutputTokensSame

```solidity
error Pool__InputOutputTokensSame();
```

### Pool__IndexOutOfBounds

```solidity
error Pool__IndexOutOfBounds();
```

### Pool__MaxLimitExceeded

```solidity
error Pool__MaxLimitExceeded();
```

### Pool__ZeroAmount

```solidity
error Pool__ZeroAmount();
```

### Pool__MustBeInitiatedWithMoreThanOneToken

```solidity
error Pool__MustBeInitiatedWithMoreThanOneToken();
```

### Pool__MustBeInitiatedWithAGreaterThanZero

```solidity
error Pool__MustBeInitiatedWithAGreaterThanZero();
```

### Pool__InvalidParams

```solidity
error Pool__InvalidParams();
```

### Pool__CannotBeZeroAddress

```solidity
error Pool__CannotBeZeroAddress();
```

### Pool__InvalidDecimals

```solidity
error Pool__InvalidDecimals();
```

### Pool__SumOfWeightsMustBeOne

```solidity
error Pool__SumOfWeightsMustBeOne();
```

### Pool__InvalidRateProvided

```solidity
error Pool__InvalidRateProvided();
```

### Pool__NoConvergence

```solidity
error Pool__NoConvergence();
```

### Pool__RatioBelowLowerBound

```solidity
error Pool__RatioBelowLowerBound();
```

### Pool__RatioAboveUpperBound

```solidity
error Pool__RatioAboveUpperBound();
```

### Pool__SlippageLimitExceeded

```solidity
error Pool__SlippageLimitExceeded();
```

### Pool__NeedToDepositAtleastOneToken

```solidity
error Pool__NeedToDepositAtleastOneToken();
```

### Pool__InitialDepositAmountMustBeNonZero

```solidity
error Pool__InitialDepositAmountMustBeNonZero();
```

### Pool__AmountsMustBeNonZero

```solidity
error Pool__AmountsMustBeNonZero();
```

### Pool__WeightOutOfBounds

```solidity
error Pool__WeightOutOfBounds();
```

### Pool__PoolIsFull

```solidity
error Pool__PoolIsFull();
```

### Pool__RampActive

```solidity
error Pool__RampActive();
```

### Pool__PoolIsEmpty

```solidity
error Pool__PoolIsEmpty();
```

### Pool__TokenAlreadyPartOfPool

```solidity
error Pool__TokenAlreadyPartOfPool();
```

### Pool__CannotRescuePoolToken

```solidity
error Pool__CannotRescuePoolToken();
```

### Pool__BandsOutOfBounds

```solidity
error Pool__BandsOutOfBounds();
```

### Pool__WeightsDoNotAddUp

```solidity
error Pool__WeightsDoNotAddUp();
```

### Pool__AlreadyPaused

```solidity
error Pool__AlreadyPaused();
```

### Pool__NotPaused

```solidity
error Pool__NotPaused();
```

### Pool__Killed

```solidity
error Pool__Killed();
```

### Pool__NoSurplus

```solidity
error Pool__NoSurplus();
```

### Pool__NoRate

```solidity
error Pool__NoRate();
```

### Pool__Paused

```solidity
error Pool__Paused();
```

