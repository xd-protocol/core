// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { LiquidityMatrixLocal } from "src/mixins/LiquidityMatrixLocal.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { LiquidityMatrixTestHelper } from "./helpers/LiquidityMatrixTestHelper.sol";

contract LiquidityMatrixLocalTest is LiquidityMatrixTestHelper {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address[] users = [alice, bob, charlie];

    function setUp() public override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        local = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[1], owner);
        localApp = address(new AppMock(address(local)));
        initialize(localStorage);

        vm.deal(localApp, 10_000e18);
    }

    function test_registerApp() public {
        changePrank(localApp, localApp);
        local.registerApp(true, true, address(1));

        (bool registered, bool syncMappedAccountsOnly, bool useCallbacks, address settler) =
            local.getAppSetting(localApp);
        assertTrue(registered);
        assertTrue(syncMappedAccountsOnly);
        assertTrue(useCallbacks);
        assertEq(settler, address(1));
    }

    function test_updateMappedAccountsOnly() public {
        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));
        local.updateSyncMappedAccountsOnly(true);

        (, bool syncMappedAccountsOnly,,) = local.getAppSetting(address(localApp));
        assertTrue(syncMappedAccountsOnly);
    }

    function test_updateUseCallbacks() public {
        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));
        local.updateUseCallbacks(true);

        (,, bool useCallbacks,) = local.getAppSetting(address(localApp));
        assertTrue(useCallbacks);
    }

    function test_updateSettler() public {
        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));
        local.updateSettler(address(1));

        (,,, address settler) = local.getAppSetting(address(localApp));
        assertEq(settler, address(1));
    }

    function test_updateLocalLiquidity(bytes32 seed) public {
        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        _updateLocalLiquidity(local, localApp, localStorage, users, seed);
    }

    function test_updateLocalData(bytes32 seed) public {
        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        _updateLocalData(local, localApp, localStorage, seed);
    }
}
