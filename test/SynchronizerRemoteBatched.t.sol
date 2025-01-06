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

contract SynchronizerRemoteBatchedTest is BaseSynchronizerTest {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    uint32 constant EID_LOCAL = 1;
    uint32 constant EID_REMOTE = 2;

    Synchronizer local;
    IAppMock localApp;
    Storage localStorage;

    Synchronizer remote;
    IAppMock remoteApp;
    Storage remoteStorage;

    address[] accAccounts;
    int256[] accLiquidity;
    bytes32[] accKeys;
    bytes[] accValues;

    address owner = makeAddr("owner");
    address[] users;

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

        for (uint256 i; i < 256; ++i) {
            users.push(makeAddr(string(abi.encodePacked("account", i))));
        }
        delete accAccounts;
        delete accLiquidity;
        delete accKeys;
        delete accValues;

        changePrank(owner, owner);
    }

    function test_createLiquidityBatch_submitLiquidity_settleLiquidityBatched(bytes32 seed) public {
        assertEq(local.lastLiquidityBatchId(address(localApp), EID_REMOTE), 0);

        (address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);

        bytes32 liquidityRoot = remoteStorage.mainLiquidityTree.root;
        bytes32 dataRoot = remoteStorage.mainDataTree.root;
        uint256 timestamp = vm.getBlockTimestamp();
        _receiveRoots(local, EID_REMOTE, liquidityRoot, dataRoot, timestamp);

        uint256 offset;
        uint256 count = uint256(seed) % 100;

        (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(EID_REMOTE);
        (address[] memory accountsBatch, int256[] memory liquidityBatch) =
            _batchLiquidity(accounts, liquidity, offset, count);
        local.createLiquidityBatch(address(localApp), EID_REMOTE, rootTimestamp, accountsBatch, liquidityBatch);
        assertEq(local.lastLiquidityBatchId(address(localApp), EID_REMOTE), 1);

        bytes32 root =
            MerkleTreeLib.computeRoot(ArrayLib.convertToBytes32(accAccounts), ArrayLib.convertToBytes32(accLiquidity));
        assertEq(local.liquidityBatchRoot(address(localApp), EID_REMOTE, 0), root);

        for (offset = count; offset < accounts.length;) {
            seed = keccak256(abi.encodePacked(seed, count));
            count = uint256(seed) % 100;
            if (offset + count > accounts.length) {
                count = accounts.length - offset;
            }

            (accountsBatch, liquidityBatch) = _batchLiquidity(accounts, liquidity, offset, count);
            local.submitLiquidity(address(localApp), EID_REMOTE, 0, accountsBatch, liquidityBatch);

            root = MerkleTreeLib.computeRoot(
                ArrayLib.convertToBytes32(accAccounts), ArrayLib.convertToBytes32(accLiquidity)
            );
            assertEq(local.liquidityBatchRoot(address(localApp), EID_REMOTE, 0), root);

            offset += count;
        }

        assertEq(
            MerkleTreeLib.computeRoot(ArrayLib.convertToBytes32(accounts), ArrayLib.convertToBytes32(liquidity)), root
        );
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = bytes32(uint256(uint160(address(remoteApp))));
        bytes32[] memory values = new bytes32[](1);
        values[0] = root;
        assertEq(local.getLiquidityRootAt(EID_REMOTE, rootTimestamp), MerkleTreeLib.computeRoot(keys, values));

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), root, mainIndex);
        local.settleLiquidityBatched(address(localApp), EID_REMOTE, 0, mainIndex, mainProof);

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

    function _batchLiquidity(address[] memory accounts, int256[] memory liquidity, uint256 offset, uint256 count)
        internal
        returns (address[] memory _accounts, int256[] memory _liquidity)
    {
        _accounts = new address[](count);
        _liquidity = new int256[](count);

        for (uint256 i; i < count; ++i) {
            address account = accounts[offset + i];
            int256 l = liquidity[offset + i];
            _accounts[i] = account;
            _liquidity[i] = l;
            bool found;
            for (uint256 j; j < accAccounts.length; ++j) {
                if (accAccounts[j] == account) {
                    accLiquidity[j] = l;
                    found = true;
                    break;
                }
            }
            if (!found) {
                accAccounts.push(account);
                accLiquidity.push(l);
            }
        }
    }

    function test_createDataBatch_submitData_settleDataBatched(bytes32 seed) public {
        assertEq(local.lastDataBatchId(address(localApp), EID_REMOTE), 0);

        (bytes32[] memory keys, bytes[] memory values) = _updateLocalData(remote, remoteApp, remoteStorage, seed);

        bytes32 liquidityRoot = remoteStorage.mainLiquidityTree.root;
        bytes32 dataRoot = remoteStorage.mainDataTree.root;
        uint256 timestamp = vm.getBlockTimestamp();
        _receiveRoots(local, EID_REMOTE, liquidityRoot, dataRoot, timestamp);

        uint256 offset;
        uint256 count = uint256(seed) % 100;

        (, uint256 rootTimestamp) = local.getLastSyncedDataRoot(EID_REMOTE);
        (bytes32[] memory keysBatch, bytes[] memory valuesBatch) = _batchData(keys, values, offset, count);
        local.createDataBatch(address(localApp), EID_REMOTE, rootTimestamp, keysBatch, valuesBatch);
        assertEq(local.lastDataBatchId(address(localApp), EID_REMOTE), 1);

        bytes32 root = MerkleTreeLib.computeRoot(accKeys, _convertToBytes32(accValues));
        assertEq(local.dataBatchRoot(address(localApp), EID_REMOTE, 0), root);

        for (offset = count; offset < keys.length;) {
            seed = keccak256(abi.encodePacked(seed, count));
            count = uint256(seed) % 100;
            if (offset + count > keys.length) {
                count = keys.length - offset;
            }

            (keysBatch, valuesBatch) = _batchData(keys, values, offset, count);
            local.submitData(address(localApp), EID_REMOTE, 0, keysBatch, valuesBatch);

            root = MerkleTreeLib.computeRoot(accKeys, _convertToBytes32(accValues));
            assertEq(local.dataBatchRoot(address(localApp), EID_REMOTE, 0), root);

            offset += count;
        }

        assertEq(MerkleTreeLib.computeRoot(keys, _convertToBytes32(values)), root);
        bytes32[] memory _keys = new bytes32[](1);
        _keys[0] = bytes32(uint256(uint160(address(remoteApp))));
        bytes32[] memory _values = new bytes32[](1);
        _values[0] = root;
        assertEq(local.getDataRootAt(EID_REMOTE, rootTimestamp), MerkleTreeLib.computeRoot(_keys, _values));

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), root, mainIndex);
        local.settleDataBatched(address(localApp), EID_REMOTE, 0, mainIndex, mainProof);

        for (uint256 i; i < keys.length; ++i) {
            assertEq(localApp.remoteData(EID_REMOTE, keys[i]), values[i]);
        }

        (bytes32 _dataRoot, uint256 _timestamp) = local.getLastSettledDataRoot(address(localApp), EID_REMOTE);
        assertEq(_dataRoot, dataRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.isLiquidityRootSettled(address(localApp), EID_REMOTE, timestamp), true);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), true);

        (_dataRoot, _timestamp) = local.getLastFinalizedDataRoot(address(localApp), EID_REMOTE);
        assertEq(_dataRoot, dataRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.areRootsFinalized(address(localApp), EID_REMOTE, timestamp), true);
    }

    function _batchData(bytes32[] memory keys, bytes[] memory values, uint256 offset, uint256 count)
        internal
        returns (bytes32[] memory _keys, bytes[] memory _values)
    {
        _keys = new bytes32[](count);
        _values = new bytes[](count);

        for (uint256 i; i < count; ++i) {
            bytes32 key = keys[offset + i];
            bytes memory value = values[offset + i];
            _keys[i] = key;
            _values[i] = value;
            accKeys.push(key);
            accValues.push(value);
        }
    }

    function _convertToBytes32(bytes[] memory values) internal pure returns (bytes32[] memory array) {
        array = new bytes32[](values.length);
        for (uint256 i; i < values.length; ++i) {
            array[i] = keccak256(values[i]);
        }
    }
}
