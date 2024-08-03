# PufMVTRateProvider
[Git Source](https://github.com/lucidlyfi/MasterVaultCode/blob/e89626c00c676e7b87a7121ad91042902a96f6d2/src/RateProvider/PufMVTRateProvider.sol)

**Inherits:**
[IRateProvider](/src/RateProvider/IRateProvider.sol/interface.IRateProvider.md)


## State Variables
### PRECISION

```solidity
uint256 private constant PRECISION = 1e18;
```


### PUFETH

```solidity
address private constant PUFETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
```


### STETH

```solidity
address private constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
```


### WSTETH

```solidity
address private constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
```


### PUFETH_WSTETH_CURVE

```solidity
address private constant PUFETH_WSTETH_CURVE = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
```


### WETH_PUFETH_CURVE

```solidity
address private constant WETH_PUFETH_CURVE = 0x39F5b252dE249790fAEd0C2F05aBead56D2088e1;
```


## Functions
### rate


```solidity
function rate(address token_) external view returns (uint256);
```

### _curveLpTokenClFeed


```solidity
function _curveLpTokenClFeed(address token_) internal view returns (uint256);
```

## Errors
### RateProvider__InvalidParam

```solidity
error RateProvider__InvalidParam();
```

