# PoolToken
[Git Source](https://github.com/lucidlyfi/MasterVaultCode/blob/e89626c00c676e7b87a7121ad91042902a96f6d2/src/PoolToken.sol)

**Inherits:**
ERC20, Ownable


## State Variables
### _name

```solidity
string internal _name;
```


### _symbol

```solidity
string internal _symbol;
```


### _decimals

```solidity
uint8 internal _decimals;
```


### poolAddress

```solidity
address poolAddress;
```


## Functions
### _checkCallerIsPool


```solidity
function _checkCallerIsPool() internal view;
```

### constructor


```solidity
constructor(string memory name_, string memory symbol_, uint8 decimals_, address owner_);
```

### name


```solidity
function name() public view virtual override returns (string memory);
```

### symbol


```solidity
function symbol() public view virtual override returns (string memory);
```

### decimals


```solidity
function decimals() public view virtual override returns (uint8);
```

### mint


```solidity
function mint(address to_, uint256 amount_) public;
```

### burn


```solidity
function burn(address from_, uint256 amount_) public;
```

### setPool


```solidity
function setPool(address poolAddress_) public onlyOwner;
```

## Events
### PoolAddressSet

```solidity
event PoolAddressSet(address newPoolAddress);
```

## Errors
### Token__CallerIsNotPool

```solidity
error Token__CallerIsNotPool();
```

### Token__PoolAddressCannotBeZero

```solidity
error Token__PoolAddressCannotBeZero();
```

