// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { LibString } from "solmate/utils/LibString.sol";
import { Synchronizer } from "src/Synchronizer.sol";
import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { ArrayLib } from "src/libraries/ArrayLib.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Settler } from "src/settlers/Settler.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { BaseSynchronizerTest } from "./BaseSynchronizerTest.sol";

contract SettlerTest is BaseSynchronizerTest {
    using MerkleTreeLib for MerkleTreeLib.Tree;

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
        local = new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[EID_LOCAL], owner);
        remote = new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[EID_REMOTE], owner);
        localApp = address(new AppMock(address(local)));
        remoteApp = address(new AppMock(address(remote)));
        localSettler = address(new Settler(address(local)));
        remoteSettler = address(new Settler(address(remote)));

        address[] memory oapps = new address[](2);
        oapps[0] = address(local);
        oapps[1] = address(remote);
        wireOApps(oapps);

        vm.deal(localApp, 10_000e18);
        vm.deal(remoteApp, 10_000e18);

        local.updateSettlerWhitelisted(localSettler, true);
        remote.updateSettlerWhitelisted(remoteSettler, true);

        ISynchronizer.ChainConfig[] memory configs = new ISynchronizer.ChainConfig[](1);
        configs[0] = ISynchronizer.ChainConfig(EID_REMOTE, 0);
        local.configChains(configs);
        configs[0] = ISynchronizer.ChainConfig(EID_LOCAL, 0);
        remote.configChains(configs);

        changePrank(localApp, localApp);
        local.registerApp(false, true, localSettler);
        local.updateRemoteApp(EID_REMOTE, address(remoteApp));

        changePrank(remoteApp, remoteApp);
        remote.registerApp(false, true, remoteSettler);
        remote.updateRemoteApp(EID_LOCAL, address(localApp));

        initialize(localStorage);
        initialize(remoteStorage);

        for (uint256 i; i < 256; ++i) {
            users.push(makeAddr(string(abi.encodePacked("account", LibString.toString(i)))));
        }
        delete accAccounts;
        delete accLiquidity;
        delete accKeys;
        delete accValues;

        vm.deal(users[0], 10_000e18);
        changePrank(users[0], users[0]);
    }

    function test_settleLiquidity(bytes32 seed) public {
        // settlement 1
        (address[] memory accounts, int256[] memory liquidity,) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        (bytes32 liquidityRoot,, uint256 timestamp) = _sync(local);

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), remoteStorage.appLiquidityTree.root, mainIndex);
        Settler(localSettler).settleLiquidity(
            address(localApp), EID_REMOTE, timestamp, mainIndex, mainProof, new uint256[](0), accounts, liquidity
        );

        (bytes32 _liquidityRoot, uint256 _timestamp) = local.getLastSettledLiquidityRoot(localApp, EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.isLiquidityRootSettled(localApp, EID_REMOTE, timestamp), true);

        // settlement 2
        changePrank(remoteApp, remoteApp);

        uint256 newUserCount;
        address[] memory _newUsers = new address[](100);
        uint256 indexCount;
        uint256[] memory _indices = new uint256[](100);
        int256[] memory newLiquidity = new int256[](100);
        for (uint256 i; i < 100; ++i) {
            address user = users[uint256(seed) % users.length];
            // check if the user was updated before
            uint256 index = type(uint256).max;
            for (uint256 j; j < accounts.length; ++j) {
                if (accounts[j] == user) {
                    index = j;
                    break;
                }
            }
            if (index == type(uint256).max) {
                _newUsers[newUserCount++] = user;
            } else {
                _indices[indexCount++] = index;
            }
            newLiquidity[i] = (int256(uint256(seed)) / 1000);
            remote.updateLocalLiquidity(user, newLiquidity[i]);
            seed = keccak256(abi.encodePacked(seed, i));
        }
        address[] memory newUsers = new address[](newUserCount);
        for (uint256 i; i < newUserCount; ++i) {
            newUsers[i] = _newUsers[i];
        }
        uint256[] memory indices = new uint256[](indexCount);
        for (uint256 i; i < indexCount; ++i) {
            indices[i] = _indices[i];
        }

        (liquidityRoot,, timestamp) = _sync(local);

        mainProof = _getMainProof(address(remoteApp), remoteStorage.appLiquidityTree.root, mainIndex);
        Settler(localSettler).settleLiquidity(
            address(localApp), EID_REMOTE, timestamp, mainIndex, mainProof, indices, newUsers, newLiquidity
        );
    }

    function test_settleData(bytes32 seed) public {
        // settlement 1
        (bytes32[] memory keys, bytes[] memory values) = _updateLocalData(remote, remoteApp, remoteStorage, seed);
        (, bytes32 dataRoot, uint256 timestamp) = _sync(local);

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), remoteStorage.appDataTree.root, mainIndex);

        Settler(localSettler).settleData(
            address(localApp), EID_REMOTE, timestamp, mainIndex, mainProof, new uint256[](0), keys, values
        );

        (bytes32 _dataRoot, uint256 _timestamp) = local.getLastSettledDataRoot(localApp, EID_REMOTE);
        assertEq(_dataRoot, dataRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), true);

        // settlement 2
        changePrank(remoteApp, remoteApp);

        uint256 newKeyCount;
        bytes32[] memory _newKeys = new bytes32[](100);
        uint256 indexCount;
        uint256[] memory _indices = new uint256[](100);
        bytes[] memory newValues = new bytes[](100);
        for (uint256 i; i < 100; ++i) {
            bytes32 key = keys[uint256(seed) % keys.length];
            // check if the key was updated before
            uint256 index = type(uint256).max;
            for (uint256 j; j < keys.length; ++j) {
                if (keys[j] == key) {
                    index = j;
                    break;
                }
            }
            if (index == type(uint256).max) {
                _newKeys[newKeyCount++] = key;
            } else {
                _indices[indexCount++] = index;
            }
            newValues[i] = abi.encodePacked(keccak256(abi.encodePacked(index, i)));
            remote.updateLocalData(key, newValues[i]);
            seed = keccak256(abi.encodePacked(seed, i));
        }
        bytes32[] memory newKeys = new bytes32[](newKeyCount);
        for (uint256 i; i < newKeyCount; ++i) {
            newKeys[i] = _newKeys[i];
        }
        uint256[] memory indices = new uint256[](indexCount);
        for (uint256 i; i < indexCount; ++i) {
            indices[i] = _indices[i];
        }
        (, dataRoot, timestamp) = _sync(local);

        mainProof = _getMainProof(address(remoteApp), remoteStorage.appDataTree.root, mainIndex);
        Settler(localSettler).settleData(
            address(localApp), EID_REMOTE, timestamp, mainIndex, mainProof, indices, newKeys, newValues
        );
    }
}
