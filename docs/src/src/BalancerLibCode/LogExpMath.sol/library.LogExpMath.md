# LogExpMath
[Git Source](https://github.com/lucidlyfi/MasterVaultCode/blob/e89626c00c676e7b87a7121ad91042902a96f6d2/src/BalancerLibCode/LogExpMath.sol)

**Authors:**
Fernando Martinelli - @fernandomartinelli, Sergio Yuhjtman - @sergioyuhjtman, Daniel Fernandez - @dmf7z

*Exponentiation and logarithm functions for 18 decimal fixed point numbers (both base and exponent/argument).*

*forked from https://github.com/balancer/balancer-v2-monorepo/blob/599b0cd8f744e1eabef3600d79a2c2b0aea3ddcb/pkg/solidity-utils/contracts/math/LogExpMath.sol
Exponentiation and logarithm with arbitrary bases (x^y and log_x(y)) are implemented by conversion to natural
exponentiation and logarithm (where the base is Euler's number).*


## State Variables
### ONE_18

```solidity
int256 constant ONE_18 = 1e18;
```


### ONE_20

```solidity
int256 constant ONE_20 = 1e20;
```


### ONE_36

```solidity
int256 constant ONE_36 = 1e36;
```


### MAX_NATURAL_EXPONENT

```solidity
int256 constant MAX_NATURAL_EXPONENT = 130e18;
```


### MIN_NATURAL_EXPONENT

```solidity
int256 constant MIN_NATURAL_EXPONENT = -41e18;
```


### LN_36_LOWER_BOUND

```solidity
int256 constant LN_36_LOWER_BOUND = ONE_18 - 1e17;
```


### LN_36_UPPER_BOUND

```solidity
int256 constant LN_36_UPPER_BOUND = ONE_18 + 1e17;
```


### MILD_EXPONENT_BOUND

```solidity
uint256 constant MILD_EXPONENT_BOUND = 2 ** 254 / uint256(ONE_20);
```


### x0

```solidity
int256 constant x0 = 128_000_000_000_000_000_000;
```


### a0

```solidity
int256 constant a0 = 38_877_084_059_945_950_922_200_000_000_000_000_000_000_000_000_000_000_000;
```


### x1

```solidity
int256 constant x1 = 64_000_000_000_000_000_000;
```


### a1

```solidity
int256 constant a1 = 6_235_149_080_811_616_882_910_000_000;
```


### x2

```solidity
int256 constant x2 = 3_200_000_000_000_000_000_000;
```


### a2

```solidity
int256 constant a2 = 7_896_296_018_268_069_516_100_000_000_000_000;
```


### x3

```solidity
int256 constant x3 = 1_600_000_000_000_000_000_000;
```


### a3

```solidity
int256 constant a3 = 888_611_052_050_787_263_676_000_000;
```


### x4

```solidity
int256 constant x4 = 800_000_000_000_000_000_000;
```


### a4

```solidity
int256 constant a4 = 298_095_798_704_172_827_474_000;
```


### x5

```solidity
int256 constant x5 = 400_000_000_000_000_000_000;
```


### a5

```solidity
int256 constant a5 = 5_459_815_003_314_423_907_810;
```


### x6

```solidity
int256 constant x6 = 200_000_000_000_000_000_000;
```


### a6

```solidity
int256 constant a6 = 738_905_609_893_065_022_723;
```


### x7

```solidity
int256 constant x7 = 100_000_000_000_000_000_000;
```


### a7

```solidity
int256 constant a7 = 271_828_182_845_904_523_536;
```


### x8

```solidity
int256 constant x8 = 50_000_000_000_000_000_000;
```


### a8

```solidity
int256 constant a8 = 164_872_127_070_012_814_685;
```


### x9

```solidity
int256 constant x9 = 25_000_000_000_000_000_000;
```


### a9

```solidity
int256 constant a9 = 128_402_541_668_774_148_407;
```


### x10

```solidity
int256 constant x10 = 12_500_000_000_000_000_000;
```


### a10

```solidity
int256 constant a10 = 113_314_845_306_682_631_683;
```


### x11

```solidity
int256 constant x11 = 6_250_000_000_000_000_000;
```


### a11

```solidity
int256 constant a11 = 106_449_445_891_785_942_956;
```


## Functions
### pow

*Exponentiation (x^y) with unsigned 18 decimal fixed point base and exponent.
Reverts if ln(x) * y is smaller than `MIN_NATURAL_EXPONENT`, or larger than `MAX_NATURAL_EXPONENT`.*


```solidity
function pow(uint256 x, uint256 y) internal pure returns (uint256);
```

### exp

*Natural exponentiation (e^x) with signed 18 decimal fixed point exponent.
Reverts if `x` is smaller than MIN_NATURAL_EXPONENT, or larger than `MAX_NATURAL_EXPONENT`.*


```solidity
function exp(int256 x) internal pure returns (int256);
```

### log

*Logarithm (log(arg, base), with signed 18 decimal fixed point base and argument.*


```solidity
function log(int256 arg, int256 base) internal pure returns (int256);
```

### ln

*Natural logarithm (ln(a)) with signed 18 decimal fixed point argument.*


```solidity
function ln(int256 a) internal pure returns (int256);
```

### _ln

*Internal natural logarithm (ln(a)) with signed 18 decimal fixed point argument.*


```solidity
function _ln(int256 a) private pure returns (int256);
```

### _ln_36

*Intrnal high precision (36 decimal places) natural logarithm (ln(x)) with signed 18 decimal fixed point argument,
for x close to one.
Should only be used if x is between LN_36_LOWER_BOUND and LN_36_UPPER_BOUND.*


```solidity
function _ln_36(int256 x) private pure returns (int256);
```

