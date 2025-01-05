// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Synchronizer } from "src/Synchronizer.sol";
import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { ArrayLib } from "src/libraries/ArrayLib.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { BaseSynchronizerTest } from "./BaseSynchronizerTest.sol";

contract SynchronizerRemoteTest is BaseSynchronizerTest {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    uint32 constant EID_LOCAL = 1;
    uint32 constant EID_REMOTE = 2;

    Synchronizer local;
    IAppMock localApp;
    Storage localStorage;

    Synchronizer remote;
    IAppMock remoteApp;
    Storage remoteStorage;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address[] users = [alice, bob, charlie];

    function setUp() public override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        local = new Synchronizer(endpoints[EID_LOCAL], owner);
        remote = new Synchronizer(endpoints[EID_REMOTE], owner);
        localApp = IAppMock(address(new AppMock(address(local))));
        remoteApp = IAppMock(address(new AppMock(address(remote))));

        local.setReadChannel(READ_CHANNEL, true);
        remote.setReadChannel(READ_CHANNEL, true);

        ISynchronizer.ChainConfig[] memory configs = new ISynchronizer.ChainConfig[](1);
        configs[0] = ISynchronizer.ChainConfig(EID_REMOTE, 0, address(remote));
        local.configChains(configs);
        configs[0] = ISynchronizer.ChainConfig(EID_LOCAL, 0, address(local));
        remote.configChains(configs);

        localApp.registerApp(false);
        remoteApp.registerApp(false);

        changePrank(address(localApp), address(localApp));
        local.updateRemoteApp(EID_REMOTE, address(remoteApp));
        changePrank(address(remoteApp), address(remoteApp));
        remote.updateRemoteApp(EID_LOCAL, address(localApp));

        initialize(localStorage);
        initialize(remoteStorage);

        changePrank(owner, owner);
    }

    function test_updateRemoteApp() public {
        changePrank(address(localApp), address(localApp));
        local.updateRemoteApp(EID_REMOTE, address(remoteApp));

        assertEq(local.getRemoteApp(address(localApp), EID_REMOTE), address(remoteApp));
    }

    function test_settleLiquidity_withEmptyData(bytes32 seed) public {
        assertEq(local.getSettledTotalLiquidity(address(localApp)), 0);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), 0);

        (address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);

        bytes32 liquidityRoot = remoteStorage.mainLiquidityTree.root;
        bytes32 dataRoot = remoteStorage.mainDataTree.root;
        uint256 timestamp = vm.getBlockTimestamp();
        _receiveRoots(local, EID_REMOTE, liquidityRoot, dataRoot, timestamp);

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), mainIndex);

        local.settleLiquidity(address(localApp), EID_REMOTE, mainIndex, mainProof, accounts, liquidity);

        for (uint256 i; i < accounts.length; ++i) {
            assertEq(localApp.remoteLiquidity(EID_REMOTE, accounts[i]), liquidity[i]);
        }
        assertEq(localApp.remoteTotalLiquidity(EID_REMOTE), totalLiquidity);

        (bytes32 _liquidityRoot, uint256 _timestamp) = local.getLastSettledLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.getSettledTotalLiquidity(address(localApp)), totalLiquidity);
        assertEq(local.isLiquidityRootSettled(address(localApp), EID_REMOTE, timestamp), true);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), true);

        (_liquidityRoot, _timestamp) = local.getLastFinalizedLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), totalLiquidity);
        assertEq(local.areRootsFinalized(address(localApp), EID_REMOTE, timestamp), true);
    }

    function test_settleLiquidity_withDataUpdated(bytes32 seed) public {
        assertEq(local.getSettledTotalLiquidity(address(localApp)), 0);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), 0);

        (address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        (bytes32[] memory keys, bytes[] memory values) = _updateLocalData(remote, remoteApp, remoteStorage, seed);

        bytes32 liquidityRoot = remoteStorage.mainLiquidityTree.root;
        bytes32 dataRoot = remoteStorage.mainDataTree.root;
        uint256 timestamp = vm.getBlockTimestamp();
        _receiveRoots(local, EID_REMOTE, liquidityRoot, dataRoot, timestamp);

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), mainIndex);

        local.settleLiquidity(address(localApp), EID_REMOTE, mainIndex, mainProof, accounts, liquidity);

        for (uint256 i; i < accounts.length; ++i) {
            assertEq(localApp.remoteLiquidity(EID_REMOTE, accounts[i]), liquidity[i]);
        }
        assertEq(localApp.remoteTotalLiquidity(EID_REMOTE), totalLiquidity);

        (bytes32 _liquidityRoot, uint256 _timestamp) = local.getLastSettledLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.getSettledTotalLiquidity(address(localApp)), totalLiquidity);
        assertEq(local.isLiquidityRootSettled(address(localApp), EID_REMOTE, timestamp), true);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), false);

        (_liquidityRoot, _timestamp) = local.getLastFinalizedLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, bytes32(0));
        assertEq(_timestamp, 0);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), 0);
        assertEq(local.areRootsFinalized(address(localApp), EID_REMOTE, timestamp), false);

        mainIndex = 0;
        mainProof = _getMainProof(address(remoteApp), mainIndex);
        local.settleData(address(localApp), EID_REMOTE, mainIndex, mainProof, keys, values);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), true);

        (_liquidityRoot, _timestamp) = local.getLastFinalizedLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), totalLiquidity);
        assertEq(local.areRootsFinalized(address(localApp), EID_REMOTE, timestamp), true);
    }

    function test_settleData(bytes32 seed) public {
        (bytes32[] memory keys, bytes[] memory values) = _updateLocalData(remote, remoteApp, remoteStorage, seed);

        uint256 timestamp = vm.getBlockTimestamp();
        _receiveRoots(
            local, EID_REMOTE, remoteStorage.mainLiquidityTree.root, remoteStorage.mainDataTree.root, timestamp
        );

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), mainIndex);
        local.settleData(address(localApp), EID_REMOTE, mainIndex, mainProof, keys, values);

        for (uint256 i; i < keys.length; ++i) {
            assertEq(localApp.remoteData(EID_REMOTE, keys[i]), values[i]);
        }
    }

    function _getMainProof(address app, uint256 mainIndex) internal view returns (bytes32[] memory) {
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = bytes32(uint256(uint160(app)));
        bytes32[] memory values = new bytes32[](1);
        values[0] = remoteStorage.appLiquidityTree.root;
        return MerkleTreeLib.getProof(keys, values, mainIndex);
    }
}
