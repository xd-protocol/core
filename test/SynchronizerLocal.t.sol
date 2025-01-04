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

    SynchronizerLocal synchronizer;
    IAppMock app;
    Storage s;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address[] users = [alice, bob, charlie];

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        synchronizer = new Synchronizer(endpoints[1], owner);
        app = IAppMock(address(new AppMock(address(synchronizer))));
        initialize(s);
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

        _updateLocalLiquidity(synchronizer, app, s, users, seed);
    }

    function test_updateLocalData(bytes32 seed) public {
        app.registerApp(false);

        _updateLocalData(synchronizer, app, s, seed);
    }
}
