// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { Synchronizer } from "src/Synchronizer.sol";
import { SynchronizerLocal } from "src/mixins/SynchronizerLocal.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract AppMock {
    address immutable synchronizer;

    constructor(address _synchronizer) {
        synchronizer = _synchronizer;
    }

    fallback() external {
        (bool ok,) = synchronizer.call(msg.data);
        require(ok);
    }
}

contract SynchronizerLocalTest is TestHelperOz5 {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    SynchronizerLocal public synchronizer;
    ISynchronizer public app;
    MerkleTreeLib.Tree public appLiquidityTree;
    MerkleTreeLib.Tree public appDataTree;
    MerkleTreeLib.Tree public mainLiquidityTree;
    MerkleTreeLib.Tree public mainDataTree;
    mapping(address account => int256) public liquidityCache;
    mapping(address account => mapping(uint256 timestamp => int256)) public liquidityAt;
    mapping(address account => uint256[]) public liquidityTimestamps;
    mapping(uint256 timestamp => int256) public totalLiquidityAt;
    uint256[] public totalLiquidityTimestamps;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address[3] public users = [alice, bob, charlie];

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        synchronizer = new Synchronizer(endpoints[1], owner);
        app = ISynchronizer(address(new AppMock(address(synchronizer))));
        appLiquidityTree.initialize();
        appLiquidityTree.size = 0;
        appDataTree.initialize();
        appDataTree.size = 0;
        mainLiquidityTree.initialize();
        mainLiquidityTree.size = 0;
        mainDataTree.initialize();
        mainDataTree.size = 0;
    }

    function test_registerApp() public {
        app.registerApp(false);

        (bool registered,) = synchronizer.getAppSetting(address(app));
        assertTrue(registered);
    }

    function test_updateSyncContracts() public {
        app.registerApp(false);
        app.updateSyncContracts(true);

        (, bool syncContracts) = synchronizer.getAppSetting(address(app));
        assertTrue(syncContracts);
    }

    function test_updateLocalLiquidity(bytes32 seed) public {
        app.registerApp(false);

        int256 total;
        for (uint256 i; i < 256; ++i) {
            address user = users[uint256(seed) % 3];
            int256 liquidity = int256(uint256(seed)) / 1000;
            total -= liquidityCache[user];
            total += liquidity;
            liquidityCache[user] = liquidity;

            app.updateLocalLiquidity(user, liquidity);
            assertEq(synchronizer.getLocalLiquidity(address(app), user), liquidity);
            assertEq(synchronizer.getLocalTotalLiquidity(address(app)), total);
            _assertLiquidityRootsCorrect(user, liquidity);

            uint256 timestamp = vm.getBlockTimestamp();
            liquidityAt[user][timestamp] = liquidity;
            liquidityTimestamps[user].push(timestamp);
            totalLiquidityAt[timestamp] = total;
            totalLiquidityTimestamps.push(timestamp);

            skip(uint256(seed) % 1000);
            seed = keccak256(abi.encodePacked(seed, i));
        }

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];
            for (uint256 j; j < liquidityTimestamps[user].length; ++j) {
                uint256 timestamp = liquidityTimestamps[user][j];
                assertEq(synchronizer.getLocalLiquidityAt(address(app), user, timestamp), liquidityAt[user][timestamp]);
            }
        }
        for (uint256 i; i < totalLiquidityTimestamps.length; ++i) {
            uint256 timestamp = totalLiquidityTimestamps[i];
            assertEq(synchronizer.getLocalTotalLiquidityAt(address(app), timestamp), totalLiquidityAt[timestamp]);
        }
    }

    function _assertLiquidityRootsCorrect(address account, int256 liquidity) internal {
        appLiquidityTree.update(bytes32(uint256(uint160(account))), bytes32(uint256(liquidity)));
        assertEq(synchronizer.getLocalLiquidityRoot(address(app)), appLiquidityTree.root);
        mainLiquidityTree.update(bytes32(uint256(uint160(address(app)))), appLiquidityTree.root);
        assertEq(synchronizer.getMainLiquidityRoot(), mainLiquidityTree.root);
    }

    function test_updateLocalData(bytes32 seed) public {
        app.registerApp(false);

        for (uint256 i; i < 256; ++i) {
            bytes32 key = seed;
            bytes memory data = abi.encodePacked(keccak256(abi.encodePacked(key, i)));

            app.updateLocalData(key, data);
            assertEq(synchronizer.getLocalDataHash(address(app), key), keccak256(data));
            _assertDataRootsCorrect(key, data);

            seed = keccak256(abi.encodePacked(data, i));
        }
    }

    function _assertDataRootsCorrect(bytes32 key, bytes memory data) internal {
        appDataTree.update(key, keccak256(data));
        assertEq(synchronizer.getLocalDataRoot(address(app)), appDataTree.root);
        mainDataTree.update(bytes32(uint256(uint160(address(app)))), appDataTree.root);
        assertEq(synchronizer.getMainDataRoot(), mainDataTree.root);
    }
}
