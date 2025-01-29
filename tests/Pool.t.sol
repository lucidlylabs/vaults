// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {Pool} from "../src/Pool.sol";
import {PoolToken} from "../src/PoolToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockToken} from "../src/Mocks/MockToken.sol";
import {MockRateProvider} from "../src/Mocks/MockRateProvider.sol";
import {PoolEstimator} from "./PoolEstimator.sol";
import {LogExpMath} from "../src/BalancerLibCode/LogExpMath.sol";

contract PoolTest is Test {
    Pool pool;
    PoolToken poolToken;
    Vault staking;
    MockRateProvider mrp;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_NUM_TOKENS = 32;
    uint256 public amplification;

    address public poolOwner;

    ERC20 public token0;
    ERC20 public token1;
    ERC20 public token2;
    ERC20 public token3;
    ERC20 public token4;
    ERC20 public token5;
    ERC20 public token6;
    ERC20 public token7;

    address[] public tokens = new address[](4);
    uint256[] public weights = new uint256[](4);
    address[] rateProviders = new address[](4);

    address jake = makeAddr("jake"); // pool and staking owner
    address alice = makeAddr("alice"); // first LP
    address bob = makeAddr("bob"); // second LP

    function setUp() public {
        // 1. deploy tokens
        // 2. deploy pool
        // 3. configure pool
        // 4. deploy vault
        // 5. add liquidity to pool

        token0 = new MockToken("token0", "t0", 18);
        token1 = new MockToken("token1", "t1", 18);
        token2 = new MockToken("token2", "t2", 18);
        token3 = new MockToken("token3", "t3", 18);

        mrp = new MockRateProvider();

        mrp.setRate(address(token0), 2 ether);
        mrp.setRate(address(token1), 3 ether);
        mrp.setRate(address(token2), 4 ether);
        mrp.setRate(address(token3), 5 ether);

        // set tokens
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        // set weights
        weights[0] = 10 * PRECISION / 100;
        weights[1] = 20 * PRECISION / 100;
        weights[2] = 30 * PRECISION / 100;
        weights[3] = 40 * PRECISION / 100;

        // set rateProviders
        rateProviders[0] = address(mrp);
        rateProviders[1] = address(mrp);
        rateProviders[2] = address(mrp);
        rateProviders[3] = address(mrp);

        amplification = 167_237_825_366_714_712_064;
    }

    function testRateUpdate() public {
        uint256 numTokens = 4;

        uint256[] memory weights2 = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            weights2[i] = PRECISION / numTokens;
        }

        poolToken = new PoolToken("XYZ Pool Token", "XYZ-PT", 18, jake);
        pool = new Pool(address(poolToken), calculateWProd(weights2) * 10, tokens, rateProviders, weights2, jake);

        vm.startPrank(jake);
        pool.setVaultAddress(jake);
        poolToken.setPool(address(pool));
        vm.stopPrank();

        // add liquidity
        uint256 amount = numTokens * 100 * PRECISION;
        for (uint256 t = 0; t < numTokens; t++) {
            vm.startPrank(alice);
            MockToken(tokens[t]).approve(address(pool), type(uint256).max);
            vm.stopPrank();
            MockToken(tokens[t]).mint(alice, amount / numTokens);
        }

        // vm.startPrank(alice);
        // pool.addLiquidity(, 0, alice);
        // vm.stopPrank();
    }

    function testRampWeightEmpty() public {}

    function testAddToken() public {
        // compare a pool of 5 tokens with a pool with 4+1 tokens

        uint256 amount = 100 * PRECISION;
        uint256 n = 5;
        uint256[] memory weights1 = new uint256[](n);

        for (uint256 i = 0; i < n - 1; i++) {
            weights1[i] = (PRECISION * 99 / 100) / (n - 1);
        }

        weights1[n - 1] = PRECISION / 100;
        uint256 sum;
        uint256[] memory amounts = new uint256[](n);

        for (uint256 w = 0; w < n; w++) {
            amounts[w] = amount * weights1[w] / PRECISION;
            sum += weights1[w];
        }

        MockToken t0 = new MockToken("t0", "token0", 18);
        MockToken t1 = new MockToken("t1", "token1", 18);
        MockToken t2 = new MockToken("t2", "token2", 18);
        MockToken t3 = new MockToken("t3", "token3", 18);
        MockToken t4 = new MockToken("t4", "token4", 18);

        address[] memory tokens0 = new address[](n);
        address[] memory mockRateProviders = new address[](n);
        tokens0[0] = address(t0);
        tokens0[1] = address(t1);
        tokens0[2] = address(t2);
        tokens0[3] = address(t3);
        tokens0[4] = address(t4);

        MockRateProvider mrp0 = new MockRateProvider();
        mrp0.setRate(tokens0[0], PRECISION);
        mrp0.setRate(tokens0[1], PRECISION);
        mrp0.setRate(tokens0[2], PRECISION);
        mrp0.setRate(tokens0[3], PRECISION);
        mrp0.setRate(tokens0[4], PRECISION);

        mockRateProviders[0] = address(mrp0);
        mockRateProviders[1] = address(mrp0);
        mockRateProviders[2] = address(mrp0);
        mockRateProviders[3] = address(mrp0);
        mockRateProviders[4] = address(mrp0);

        // 5 tokens
        // uint256 amplification1 = calculateWProd(weights1) * 10;
        uint256 amplification1 = 1_264_162_035_733_190_410_240 * 10;

        vm.startPrank(jake);
        PoolToken poolToken1 = new PoolToken("PoolToken1", "XYZ-PT1", 18, jake);
        Pool pool1 = new Pool(address(poolToken1), amplification1, tokens0, mockRateProviders, weights1, jake);
        poolToken1.setPool(address(pool1));
        pool1.setVaultAddress(alice);
        vm.stopPrank();

        for (uint256 i = 0; i < 5; i++) {
            address _token = tokens0[i];
            vm.startPrank(alice);
            MockToken(_token).approve(address(pool1), type(uint256).max);
            MockToken(_token).mint(alice, amounts[i]);
            vm.stopPrank();
        }

        vm.startPrank(alice);
        pool1.addLiquidity(amounts, 0, jake);
        vm.stopPrank();

        (uint256 vbSum, uint256 vbProd) = pool1.virtualBalanceProdSum();
        uint256 supply = pool1.supply();

        uint256[] memory w1 = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            (w1[i],,,) = pool1.weight(i);
        }

        // 4 + 1 tokens
        n -= 1;
        uint256[] memory weights2 = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            weights2[i] = PRECISION / n;
        }

        address[] memory tokens1 = new address[](n);
        tokens1[0] = tokens0[0];
        tokens1[1] = tokens0[1];
        tokens1[2] = tokens0[2];
        tokens1[3] = tokens0[3];

        MockRateProvider mrp1 = new MockRateProvider();
        mrp1.setRate(tokens0[0], PRECISION);
        mrp1.setRate(tokens0[1], PRECISION);
        mrp1.setRate(tokens0[2], PRECISION);
        mrp1.setRate(tokens0[3], PRECISION);

        address[] memory mockRateProviders1 = new address[](n);
        mockRateProviders1[0] = address(mrp0);
        mockRateProviders1[1] = address(mrp0);
        mockRateProviders1[2] = address(mrp0);
        mockRateProviders1[3] = address(mrp0);

        vm.startPrank(jake);
        PoolToken poolToken2 = new PoolToken("PoolToken2", "XYZ-PT2", 18, jake);
        Pool pool2 =
            new Pool(address(poolToken2), calculateWProd(weights2) * 10, tokens1, mockRateProviders1, weights2, jake);
        poolToken2.setPool(address(pool2));
        pool2.setVaultAddress(alice);
        vm.stopPrank();

        uint256[] memory _amounts1 = new uint256[](n);
        _amounts1[0] = amounts[0];
        _amounts1[1] = amounts[1];
        _amounts1[2] = amounts[2];
        _amounts1[3] = amounts[3];

        for (uint256 i = 0; i < n + 1; i++) {
            address _token = tokens0[i];
            vm.startPrank(jake);
            MockToken(_token).approve(address(pool2), type(uint256).max);
            MockToken(_token).mint(jake, amounts[i]);
            vm.stopPrank();
        }

        vm.startPrank(jake);
        pool2.addLiquidity(_amounts1, 0, alice);
        pool2.addToken(
            tokens0[n], address(mrp0), PRECISION / 100, PRECISION, PRECISION, amounts[n], amplification, 0, alice
        );
        vm.stopPrank();

        assert(MockToken(tokens0[n]).balanceOf(address(pool2)) == amounts[n]);

        uint256 s = 0;
        for (uint256 i = 0; i < n + 1; i++) {
            (uint256 temp,,,) = pool2.weight(i);
            s += temp;
        }

        assert(s == PRECISION);

        (uint256 vbSum2, uint256 vbProd2) = pool2.virtualBalanceProdSum();
        uint256 supply2 = pool2.supply();

        uint256[] memory w2 = new uint256[](n + 1);
        for (uint256 i = 0; i < n + 1; i++) {
            (w2[i],,,) = pool2.weight(i);
        }

        for (uint256 i = 0; i < n + 1; i++) {
            assert(w1[i] == w2[i]);
        }
    }

    function testPause() public {}

    function testUnpause() public {}

    function testKill() public {}

    function testChangeRateProvider() public {}

    function testRateIncreaseCap() public {}

    function testRescue() public {}

    function testSkim() public {}

    function _abs(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x >= y) {
            return (x - y);
        } else {
            return (y - x);
        }
    }

    function calculateWProd(uint256[] memory _weights) public pure returns (uint256) {
        uint256 prod = uint256(PRECISION);
        uint256 n = _weights.length;
        for (uint256 i = 0; i < n; i++) {
            uint256 w = _weights[i];
            // prod = prod / (w / PRECISION) ^ (w * n / PRECISION)
            prod = prod * PRECISION / LogExpMath.pow((w * PRECISION / PRECISION), (w * n * PRECISION) / PRECISION);
        }

        return prod;
    }
}
