// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Settler } from "src/settlers/Settler.sol";
import { SettlerTestHelper, MerkleTreeLib } from "./helpers/SettlerTestHelper.sol";

contract SettlerTest is SettlerTestHelper {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    function setUp() public override {
        super.setUp();

        localSettler = address(new Settler(address(local)));
        remoteSettler = address(new Settler(address(remote)));

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

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), liquidityRoot, mainIndex);
        bytes memory accountsData = _accountsData(indices, accounts);
        Settler(localSettler).settleLiquidity(
            address(localApp), EID_REMOTE, timestamp, mainIndex, mainProof, accountsData, liquidity
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

        uint256 mainIndex = 0;
        bytes32[] memory mainProof = _getMainProof(address(remoteApp), remoteStorage.appDataTree.root, mainIndex);
        bytes memory keysData = _keysData(indices, keys);
        Settler(localSettler).settleData(
            address(localApp), EID_REMOTE, timestamp, mainIndex, mainProof, keysData, values
        );

        (bytes32 _dataRoot, uint256 _timestamp) = local.getLastSettledDataRoot(localApp, EID_REMOTE);
        assertEq(_dataRoot, dataRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), true);
    }
}
