# RateProvider
[Git Source](https://github.com/lucidlyfi/MasterVaultCode/blob/e89626c00c676e7b87a7121ad91042902a96f6d2/src/RateProvider/RateProvider.sol)

**Inherits:**
Ownable


## State Variables
### rates

```solidity
mapping(address => uint256) rates;
```


## Functions
### rate


```solidity
function rate(address token_) external view returns (uint256);
```

### setRate


```solidity
function setRate(address token_) external;
```

