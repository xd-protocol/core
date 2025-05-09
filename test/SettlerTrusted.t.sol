// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { SettlerTrusted } from "src/settlers/SettlerTrusted.sol";
import { SettlerTestHelper, MerkleTreeLib } from "./helpers/SettlerTestHelper.sol";

contract SettlerTrustedTest is SettlerTestHelper {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    function setUp() public override {
        super.setUp();

        localSettler = address(new SettlerTrusted(address(local)));
        SettlerTrusted(localSettler).updateTrusted(users[0], true);
        remoteSettler = address(new SettlerTrusted(address(remote)));
        SettlerTrusted(remoteSettler).updateTrusted(users[0], true);

        local.updateSettlerWhitelisted(localSettler, true);
        remote.updateSettlerWhitelisted(remoteSettler, true);

        changePrank(localApp, localApp);
        local.registerApp(false, true, localSettler);
        local.updateRemoteApp(EID_REMOTE, address(remoteApp));

        changePrank(remoteApp, remoteApp);
        remote.registerApp(false, true, remoteSettler);
        remote.updateRemoteApp(EID_LOCAL, address(localApp));

        changePrank(users[0], users[0]);
    }

    function test_settleLiquidity(bytes32 seed) public {
        (uint256[] memory indices, address[] memory accounts, int256[] memory liquidity,) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        (bytes32 liquidityRoot,, uint256 timestamp) = _sync(local);

        changePrank(users[0], users[0]);

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), liquidityRoot, mainIndex);
        bytes memory accountsData = _accountsData(indices, accounts);
        SettlerTrusted(localSettler).settleLiquidity(
            address(localApp),
            EID_REMOTE,
            timestamp,
            mainIndex,
            mainProof,
            accountsData,
            liquidity,
            remoteStorage.appLiquidityTree.root
        );

        (bytes32 _liquidityRoot, uint256 _timestamp) = local.getLastSettledLiquidityRoot(localApp, EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.isLiquidityRootSettled(localApp, EID_REMOTE, timestamp), true);
    }

    function test_settleData(bytes32 seed) public {
        (uint256[] memory indices, bytes32[] memory keys, bytes[] memory values) =
            _updateLocalData(remote, remoteApp, remoteStorage, seed);
        (, bytes32 dataRoot, uint256 timestamp) = _sync(local);

        changePrank(users[0], users[0]);

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), remoteStorage.appDataTree.root, mainIndex);
        bytes memory keysData = _keysData(indices, keys);
        SettlerTrusted(localSettler).settleData(
            address(localApp),
            EID_REMOTE,
            timestamp,
            mainIndex,
            mainProof,
            keysData,
            values,
            remoteStorage.appDataTree.root
        );

        (bytes32 _dataRoot, uint256 _timestamp) = local.getLastSettledDataRoot(localApp, EID_REMOTE);
        assertEq(_dataRoot, dataRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), true);
    }
}
