# MasterVault
[Git Source](https://github.com/lucidlyfi/MasterVaultCode/blob/e89626c00c676e7b87a7121ad91042902a96f6d2/src/Staking.sol)

**Inherits:**
ERC4626Fees, Ownable


## State Variables
### depositFeeInBps

```solidity
uint256 public depositFeeInBps;
```


### protocolFeeAddress

```solidity
address public protocolFeeAddress;
```


## Functions
### constructor


```solidity
constructor(
    address underlying_,
    string memory name_,
    string memory symbol_,
    uint256 depositFeeInBps_,
    address protocolFeeAddress_,
    address owner_
) ERC20(name_, symbol_) ERC4626(IERC20(underlying_));
```

### setProtocolFeeAddress


```solidity
function setProtocolFeeAddress(address address_) public onlyOwner;
```

### setDepositFeeInBps


```solidity
function setDepositFeeInBps(uint256 fee_) public onlyOwner;
```

### _entryFeeBasisPoints


```solidity
function _entryFeeBasisPoints() internal view virtual override returns (uint256);
```

### _entryFeeRecipient


```solidity
function _entryFeeRecipient() internal view virtual override returns (address);
```

## Events
### SetProtocolFeeAddress

```solidity
event SetProtocolFeeAddress(address indexed protocolFeeAddress);
```

### SetDepositFee

```solidity
event SetDepositFee(uint256 indexed depositFee);
```

## Errors
### Staking__ProtocolFeeAddressCannotBeZero

```solidity
error Staking__ProtocolFeeAddressCannotBeZero();
```

### Staking__ProtocolFeeCannotExceed500Bps

```solidity
error Staking__ProtocolFeeCannotExceed500Bps();
```

