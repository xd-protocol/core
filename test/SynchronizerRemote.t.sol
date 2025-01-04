// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Synchronizer } from "src/Synchronizer.sol";
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

    function test_settleLiquidity(bytes32 seed) public {
        address[] memory accounts = _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);

        _receiveRoots(local, EID_REMOTE, remoteStorage.mainLiquidityTree.root, remoteStorage.mainDataTree.root);

        int256[] memory liquidity = new int256[](3);
        liquidity[0] = remoteStorage.liquidity[accounts[0]];
        liquidity[1] = remoteStorage.liquidity[accounts[1]];
        liquidity[2] = remoteStorage.liquidity[accounts[2]];

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), mainIndex);

        local.settleLiquidity(EID_REMOTE, address(localApp), mainIndex, mainProof, accounts, liquidity);

        int256 total;
        for (uint256 i; i < accounts.length; ++i) {
            assertEq(localApp.remoteLiquidity(EID_REMOTE, accounts[i]), liquidity[i]);
            total += liquidity[i];
        }
        assertEq(localApp.remoteTotalLiquidity(EID_REMOTE), total);
    }

    function test_settleData(bytes32 seed) public {
        (bytes32[] memory keys, bytes[] memory values) = _updateLocalData(remote, remoteApp, remoteStorage, seed);

        _receiveRoots(local, EID_REMOTE, remoteStorage.mainLiquidityTree.root, remoteStorage.mainDataTree.root);

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), mainIndex);
        local.settleData(EID_REMOTE, address(localApp), mainIndex, mainProof, keys, values);

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
