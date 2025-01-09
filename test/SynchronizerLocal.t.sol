// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Synchronizer } from "src/Synchronizer.sol";
import { SynchronizerLocal } from "src/mixins/SynchronizerLocal.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { BaseSynchronizerTest } from "./BaseSynchronizerTest.sol";

contract SynchronizerLocalTest is BaseSynchronizerTest {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address[] users = [alice, bob, charlie];

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        local = new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[1], owner);
        localApp = address(new AppMock(address(local)));
        initialize(localStorage);

        vm.deal(localApp, 10_000e18);
    }

    function test_registerApp() public {
        changePrank(localApp, localApp);
        local.registerApp(true, true);

        (bool registered, bool syncMappedAccountsOnly, bool useCallbacks) = local.getAppSetting(localApp);
        assertTrue(registered);
        assertTrue(syncMappedAccountsOnly);
        assertTrue(useCallbacks);
    }

    function test_updateMappedAccountsOnly() public {
        changePrank(localApp, localApp);
        local.registerApp(false, false);
        local.updateSyncMappedAccountsOnly(true);

        (, bool syncMappedAccountsOnly,) = local.getAppSetting(address(localApp));
        assertTrue(syncMappedAccountsOnly);
    }

    function test_updateUseCallbacks() public {
        changePrank(localApp, localApp);
        local.registerApp(false, false);
        local.updateUseCallbacks(true);

        (,, bool useCallbacks) = local.getAppSetting(address(localApp));
        assertTrue(useCallbacks);
    }

    function test_updateLocalLiquidity(bytes32 seed) public {
        changePrank(localApp, localApp);
        local.registerApp(false, false);

        _updateLocalLiquidity(local, localApp, localStorage, users, seed);
    }

    function test_updateLocalData(bytes32 seed) public {
        changePrank(localApp, localApp);
        local.registerApp(false, false);

        _updateLocalData(local, localApp, localStorage, seed);
    }
}
