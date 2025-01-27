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

    uint32 constant TRAILING_MASK = uint32(0x80000000);
    uint32 constant INDEX_MASK = uint32(0x7fffffff);

    mapping(address => bool) accountUpdated;
    mapping(bytes32 => bool) keyUpdated;

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

        vm.deal(users[0], 10_000e18);
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

    function _accountsData(uint256[] memory indices, address[] memory accounts)
        private
        returns (bytes memory accountsData)
    {
        for (uint256 i; i < accounts.length; ++i) {
            address account = accounts[i];
            uint32 index = uint32(indices[i]);
            if (accountUpdated[account]) {
                accountsData = abi.encodePacked(accountsData, index);
            } else {
                accountsData = abi.encodePacked(accountsData, TRAILING_MASK | index & INDEX_MASK, accounts[i]);
            }
            accountUpdated[account] = true;
        }
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

    function _keysData(uint256[] memory indices, bytes32[] memory keys) private returns (bytes memory keysData) {
        for (uint256 i; i < keys.length; ++i) {
            bytes32 key = keys[i];
            uint32 index = uint32(indices[i]);
            if (keyUpdated[key]) {
                keysData = abi.encodePacked(keysData, index);
            } else {
                keysData = abi.encodePacked(keysData, TRAILING_MASK | index & INDEX_MASK, keys[i]);
            }
            keyUpdated[key] = true;
        }
    }
}
