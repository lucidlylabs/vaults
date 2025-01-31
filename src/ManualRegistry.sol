// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import {EnumerableSetLib} from "../lib/solady/src/utils/EnumerableSetLib.sol";
import {Pool} from "../src/Pool.sol";

contract ManualRegistry is Ownable {
    event PoolAdded(address indexed poolAddress, string assetType, string version);
    event PoolRemoved(address indexed poolAddress);
    event PoolInfoUpdated(address indexed poolAddress, string assetType, string version);

    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    struct PoolInfo {
        string assetType; // USD, ETH, BTC, S
        string version; // v1, v2, v3 ..
    }

    mapping(address => PoolInfo) public poolInfo;
    EnumerableSetLib.AddressSet private poolAddresses;

    constructor() {
        _setOwner(msg.sender);
    }

    function addPoolAddress(address poolAddress, string memory assetType, string memory version) external onlyOwner {
        require(poolAddresses.add(poolAddress), "This poolAddress already exists");
        poolInfo[poolAddress] = PoolInfo(assetType, version);

        emit PoolAdded(poolAddress, assetType, version);
    }

    function removePoolAddress(address poolAddress) external onlyOwner {
        require(poolAddresses.remove(poolAddress), "This poolAddress does not exist.");

        emit PoolRemoved(poolAddress);
    }

    function setPoolInfo(address poolAddress, string memory assetType, string memory version) external onlyOwner {
        require(poolAddresses.contains(poolAddress), "This poolAddress does not exist.");
        poolInfo[poolAddress] = PoolInfo(assetType, version);

        emit PoolInfoUpdated(poolAddress, assetType, version);
    }

    function getPoolAddresses() external view returns (address[] memory) {
        return poolAddresses.values();
    }

    function numPools() external view returns (uint256) {
        return poolAddresses.length();
    }
}
