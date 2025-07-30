// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { Synchronizer } from "src/Synchronizer.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { ArrayLib } from "src/libraries/ArrayLib.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { SettlerMock } from "./mocks/SettlerMock.sol";
import { LiquidityMatrixTestHelper } from "./helpers/LiquidityMatrixTestHelper.sol";

contract LiquidityMatrixTest is LiquidityMatrixTestHelper {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    uint8 public constant CHAINS = 3;

    uint32[CHAINS] eids;
    address[CHAINS] syncers;
    ILiquidityMatrix[CHAINS] liquidityMatrices;
    Synchronizer[CHAINS] synchronizers;
    address[CHAINS] apps;
    Storage[CHAINS] storages;

    address owner = makeAddr("owner");
    address[] users;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(CHAINS, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        address[] memory oapps = new address[](CHAINS);
        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            syncers[i] = makeAddr(string.concat("syncer", vm.toString(i)));
            // Create LiquidityMatrix (only takes owner)
            liquidityMatrices[i] = new LiquidityMatrix(owner);

            // Create Synchronizer with LayerZero integration
            // Note: endpoints array is 1-indexed, so we use eids[i] which starts at 1
            synchronizers[i] = new Synchronizer(
                DEFAULT_CHANNEL_ID, endpoints[eids[i]], address(liquidityMatrices[i]), syncers[i], owner
            );

            // Set synchronizer in LiquidityMatrix
            liquidityMatrices[i].setSynchronizer(address(synchronizers[i]));

            oapps[i] = address(synchronizers[i]);
            apps[i] = address(new AppMock(address(liquidityMatrices[i])));
        }

        wireOApps(oapps);

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(apps[i], 1000e18);
            changePrank(apps[i], apps[i]);
            liquidityMatrices[i].registerApp(false, false, address(0));

            uint32[] memory configEids = new uint32[](CHAINS - 1);
            uint16[] memory configConfirmations = new uint16[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configEids[count] = eids[j];
                configConfirmations[count] = 0;
                count++;
                liquidityMatrices[i].updateRemoteApp(eids[j], address(apps[j]));
            }

            changePrank(owner, owner);
            synchronizers[i].configChains(configEids, configConfirmations);
            initialize(storages[i]);
        }

        // Set local and remote for compatibility with test helper
        local = liquidityMatrices[0];
        remote = liquidityMatrices[1];
        localApp = apps[0];
        remoteApp = apps[1];
        localSettler = makeAddr("localSettler");
        remoteSettler = makeAddr("remoteSettler");

        // Initialize localStorage and remoteStorage separately
        initialize(localStorage);
        initialize(remoteStorage);

        for (uint256 i; i < 100; ++i) {
            users.push(makeAddr(string.concat("account", vm.toString(i))));
        }
        for (uint256 i; i < syncers.length; ++i) {
            vm.deal(syncers[i], 10_000e18);
        }
        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }

        changePrank(users[0], users[0]);
    }

    /*//////////////////////////////////////////////////////////////
                    getLocalLiquidityAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalLiquidityAt_multipleTimestamps() public {
        changePrank(apps[0], apps[0]);

        // Update liquidity at different timestamps
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        uint256 t1 = block.timestamp;

        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[0], 200e18);
        uint256 t2 = block.timestamp;

        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[0], 300e18);
        uint256 t3 = block.timestamp;

        // Check historical values
        assertEq(liquidityMatrices[0].getLocalLiquidityAt(apps[0], users[0], t1), 100e18);
        assertEq(liquidityMatrices[0].getLocalLiquidityAt(apps[0], users[0], t2), 200e18);
        assertEq(liquidityMatrices[0].getLocalLiquidityAt(apps[0], users[0], t3), 300e18);
    }

    /*//////////////////////////////////////////////////////////////
                getLocalTotalLiquidityAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalTotalLiquidityAt_multipleTimestamps() public {
        changePrank(apps[0], apps[0]);

        // Update total liquidity at different timestamps
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        uint256 t1 = block.timestamp;

        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[1], 200e18);
        uint256 t2 = block.timestamp;

        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[2], 300e18);
        uint256 t3 = block.timestamp;

        // Check historical total values
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], t1), 100e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], t2), 300e18); // 100 + 200
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], t3), 600e18); // 100 + 200 + 300
    }

    /*//////////////////////////////////////////////////////////////
                    getLocalDataHashAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalDataHashAt_futureTimestamp() public {
        changePrank(apps[0], apps[0]);

        bytes32 key = keccak256("testKey");
        liquidityMatrices[0].updateLocalData(key, abi.encode("value1"));

        // Query with future timestamp should return current value
        uint256 futureTime = block.timestamp + 1000;
        bytes32 hash = liquidityMatrices[0].getLocalDataHashAt(apps[0], key, futureTime);
        assertEq(hash, keccak256(abi.encode("value1")));
    }

    /*//////////////////////////////////////////////////////////////
                    getSettledRemoteLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getSettledRemoteLiquidity() public {
        // Setup settler
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);

        // Update remote liquidity
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 100e18);
        liquidityMatrices[1].updateLocalLiquidity(users[1], 200e18);

        // Sync and settle
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedLiquidityRoot(eids[1]);

        changePrank(settler, settler);
        address[] memory accounts = new address[](2);
        accounts[0] = users[0];
        accounts[1] = users[1];
        int256[] memory liquidity = new int256[](2);
        liquidity[0] = 100e18;
        liquidity[1] = 200e18;

        liquidityMatrices[0].settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(apps[0], eids[1], rootTimestamp, accounts, liquidity)
        );

        // Check settled values
        assertEq(liquidityMatrices[0].getSettledRemoteLiquidity(apps[0], eids[1], users[0]), 100e18);
        assertEq(liquidityMatrices[0].getSettledRemoteLiquidity(apps[0], eids[1], users[1]), 200e18);
        assertEq(liquidityMatrices[0].getSettledRemoteTotalLiquidity(apps[0], eids[1]), 300e18);
    }

    /*//////////////////////////////////////////////////////////////
                        areRootsFinalized() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_areRootsFinalized(bytes32 seed) public {
        // Setup settler
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);

        // Update remote liquidity and data
        changePrank(apps[1], apps[1]);
        (, address[] memory accounts, int256[] memory liquidity,) =
            _updateLocalLiquidity(liquidityMatrices[1], apps[1], storages[1], users, seed);
        (, bytes32[] memory keys, bytes[] memory values) =
            _updateLocalData(liquidityMatrices[1], apps[1], storages[1], seed);

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        uint32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedLiquidityRoot(remoteEid);

        // Initially not finalized
        assertFalse(liquidityMatrices[0].areRootsFinalized(apps[0], remoteEid, rootTimestamp));

        // Settle liquidity
        changePrank(settler, settler);
        liquidityMatrices[0].settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(apps[0], remoteEid, rootTimestamp, accounts, liquidity)
        );

        // Still not finalized (only liquidity settled)
        assertFalse(liquidityMatrices[0].areRootsFinalized(apps[0], remoteEid, rootTimestamp));

        // Settle data
        liquidityMatrices[0].settleData(
            ILiquidityMatrix.SettleDataParams(apps[0], remoteEid, rootTimestamp, keys, values)
        );

        // Now finalized
        assertTrue(liquidityMatrices[0].areRootsFinalized(apps[0], remoteEid, rootTimestamp));
    }

    /*//////////////////////////////////////////////////////////////
                        registerApp() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerApp() public {
        address newApp = address(new AppMock(address(liquidityMatrices[0])));
        changePrank(newApp, newApp);
        liquidityMatrices[0].registerApp(true, true, address(1));

        (bool registered, bool syncMappedAccountsOnly, bool useCallbacks, address settler) =
            liquidityMatrices[0].getAppSetting(newApp);
        assertTrue(registered);
        assertTrue(syncMappedAccountsOnly);
        assertTrue(useCallbacks);
        assertEq(settler, address(1));
    }

    function test_registerApp_alreadyRegistered() public {
        address newApp = makeAddr("newApp");
        changePrank(newApp, newApp);
        liquidityMatrices[0].registerApp(false, false, address(0));

        vm.expectRevert(ILiquidityMatrix.AppAlreadyRegistered.selector);
        liquidityMatrices[0].registerApp(false, false, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                updateSyncMappedAccountsOnly() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSyncMappedAccountsOnly() public {
        // Use the already registered app
        changePrank(apps[0], apps[0]);

        // Update setting
        liquidityMatrices[0].updateSyncMappedAccountsOnly(true);

        (, bool syncMappedAccountsOnly,,) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertTrue(syncMappedAccountsOnly);
    }

    /*//////////////////////////////////////////////////////////////
                    updateUseCallbacks() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateUseCallbacks() public {
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateUseCallbacks(true);

        (,, bool useCallbacks,) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertTrue(useCallbacks);
    }

    /*//////////////////////////////////////////////////////////////
                        updateSettler() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSettler() public {
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateSettler(address(1));

        (,,, address settler) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertEq(settler, address(1));
    }

    /*//////////////////////////////////////////////////////////////
                        updateMaxLoop() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateMaxLoop() public {
        changePrank(owner, owner);
        liquidityMatrices[0].updateMaxLoop(20);
        assertEq(liquidityMatrices[0].maxLoop(), 20);

        // Cannot set to 0
        vm.expectRevert(ILiquidityMatrix.InvalidAmount.selector);
        liquidityMatrices[0].updateMaxLoop(0);
    }

    function test_updateMaxLoop_onlyOwner() public {
        address notOwner = makeAddr("notOwner");
        changePrank(notOwner, notOwner);

        vm.expectRevert(abi.encodeWithSelector(0x118cdaa7, notOwner));
        liquidityMatrices[0].updateMaxLoop(20);
    }

    /*//////////////////////////////////////////////////////////////
                    updateLocalLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateLocalLiquidity(bytes32 seed) public {
        changePrank(apps[0], apps[0]);
        _updateLocalLiquidity(liquidityMatrices[0], apps[0], storages[0], users, seed);
    }

    function test_updateLocalLiquidity_notRegistered() public {
        address unregisteredApp = makeAddr("unregisteredApp");
        changePrank(unregisteredApp, unregisteredApp);

        vm.expectRevert(ILiquidityMatrix.AppNotRegistered.selector);
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
    }

    function test_updateLocalLiquidity_negativeValues() public {
        changePrank(apps[0], apps[0]);

        // Test negative liquidity
        liquidityMatrices[0].updateLocalLiquidity(users[0], -100e18);
        assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], users[0]), -100e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), -100e18);

        // Update to positive
        liquidityMatrices[0].updateLocalLiquidity(users[0], 50e18);
        assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], users[0]), 50e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), 50e18);

        // Add another negative account
        liquidityMatrices[0].updateLocalLiquidity(users[1], -200e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), -150e18);
    }

    function test_updateLocalLiquidity_multipleAppsAndAccounts() public {
        // Register multiple apps
        address[] memory testApps = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            testApps[i] = makeAddr(string.concat("testApp", vm.toString(i)));
            changePrank(testApps[i], testApps[i]);
            liquidityMatrices[0].registerApp(false, false, address(0));
        }

        // Update liquidity for multiple accounts in each app
        for (uint256 i = 0; i < testApps.length; i++) {
            changePrank(testApps[i], testApps[i]);
            for (uint256 j = 0; j < 5; j++) {
                liquidityMatrices[0].updateLocalLiquidity(users[j], int256((i + 1) * (j + 1) * 1e18));
            }
        }

        // Verify each app's liquidity
        for (uint256 i = 0; i < testApps.length; i++) {
            int256 expectedTotal = 0;
            for (uint256 j = 0; j < 5; j++) {
                int256 expectedLiquidity = int256((i + 1) * (j + 1) * 1e18);
                assertEq(liquidityMatrices[0].getLocalLiquidity(testApps[i], users[j]), expectedLiquidity);
                expectedTotal += expectedLiquidity;
            }
            assertEq(liquidityMatrices[0].getLocalTotalLiquidity(testApps[i]), expectedTotal);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        updateLocalData() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateLocalData(bytes32 seed) public {
        changePrank(apps[0], apps[0]);
        _updateLocalData(liquidityMatrices[0], apps[0], storages[0], seed);
    }

    function test_updateLocalData_notRegistered() public {
        address unregisteredApp = makeAddr("unregisteredApp");
        changePrank(unregisteredApp, unregisteredApp);

        vm.expectRevert(ILiquidityMatrix.AppNotRegistered.selector);
        liquidityMatrices[0].updateLocalData(keccak256("key"), abi.encode("value"));
    }

    // Data storage edge cases
    function test_updateLocalData_largeData() public {
        changePrank(apps[0], apps[0]);

        // Create large data (1KB)
        bytes memory largeData = new bytes(1024);
        for (uint256 i = 0; i < largeData.length; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }

        bytes32 key = keccak256("largeDataKey");
        liquidityMatrices[0].updateLocalData(key, largeData);

        bytes32 storedHash = liquidityMatrices[0].getLocalDataHash(apps[0], key);
        assertEq(storedHash, keccak256(largeData));
    }

    function test_updateLocalData_emptyData() public {
        changePrank(apps[0], apps[0]);

        bytes32 key = keccak256("emptyDataKey");
        bytes memory emptyData = "";

        liquidityMatrices[0].updateLocalData(key, emptyData);

        bytes32 storedHash = liquidityMatrices[0].getLocalDataHash(apps[0], key);
        assertEq(storedHash, keccak256(emptyData));
    }

    /*//////////////////////////////////////////////////////////////
                        updateRemoteApp() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateRemoteApp() public {
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateRemoteApp(eids[1], address(0xdead));

        assertEq(liquidityMatrices[0].getRemoteApp(apps[0], eids[1]), address(0xdead));
    }

    function test_updateRemoteApp_zeroAddress() public {
        changePrank(apps[0], apps[0]);

        // Should allow setting to zero address (unset)
        liquidityMatrices[0].updateRemoteApp(eids[1], address(0));
        assertEq(liquidityMatrices[0].getRemoteApp(apps[0], eids[1]), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    updateSettlerWhitelisted() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSettlerWhitelisted_onlyOwner() public {
        address notOwner = makeAddr("notOwner");
        changePrank(notOwner, notOwner);

        vm.expectRevert(abi.encodeWithSelector(0x118cdaa7, notOwner));
        liquidityMatrices[0].updateSettlerWhitelisted(address(0x123), true);
    }

    /*//////////////////////////////////////////////////////////////
                    setSynchronizer() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setSynchronizer_onlyOwner() public {
        address notOwner = makeAddr("notOwner");
        changePrank(notOwner, notOwner);

        vm.expectRevert(abi.encodeWithSelector(0x118cdaa7, notOwner));
        liquidityMatrices[0].setSynchronizer(address(0x123));
    }

    /*//////////////////////////////////////////////////////////////
                        settleLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleLiquidity_basic(bytes32 seed) public {
        // Setup settler
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);

        // Update remote liquidity
        changePrank(apps[1], apps[1]);
        (, address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(liquidityMatrices[1], apps[1], storages[1], users, seed);

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settle liquidity
        changePrank(settler, settler);
        uint32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedLiquidityRoot(remoteEid);
        liquidityMatrices[0].settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(apps[0], remoteEid, rootTimestamp, accounts, liquidity)
        );

        // Verify settlement - check unique accounts only since same account can appear multiple times
        // The settled liquidity should match the final liquidity on the remote chain
        for (uint256 i; i < users.length; ++i) {
            int256 remoteLiquidity = liquidityMatrices[1].getLocalLiquidity(apps[1], users[i]);
            if (remoteLiquidity != 0) {
                assertEq(liquidityMatrices[0].getSettledRemoteLiquidity(apps[0], remoteEid, users[i]), remoteLiquidity);
            }
        }
        assertEq(liquidityMatrices[0].getSettledRemoteTotalLiquidity(apps[0], remoteEid), totalLiquidity);
        assertTrue(liquidityMatrices[0].isLiquiditySettled(apps[0], remoteEid, rootTimestamp));
    }

    function test_settleLiquidity_withCallbacks(bytes32 seed) public {
        // Setup settler and enable callbacks
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateUseCallbacks(true);

        // Update remote liquidity
        changePrank(apps[1], apps[1]);
        (, address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(liquidityMatrices[1], apps[1], storages[1], users, seed);

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settle liquidity
        changePrank(settler, settler);
        uint32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedLiquidityRoot(remoteEid);
        liquidityMatrices[0].settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(apps[0], remoteEid, rootTimestamp, accounts, liquidity)
        );

        // Verify callbacks were called with final liquidity values
        assertEq(IAppMock(apps[0]).remoteTotalLiquidity(remoteEid), totalLiquidity);
        for (uint256 i; i < users.length; ++i) {
            int256 remoteLiquidity = liquidityMatrices[1].getLocalLiquidity(apps[1], users[i]);
            if (remoteLiquidity != 0) {
                assertEq(IAppMock(apps[0]).remoteLiquidity(remoteEid, users[i]), remoteLiquidity);
            }
        }
    }

    function test_settleLiquidity_alreadySettled(bytes32 seed) public {
        // Setup settler
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);

        // Update remote liquidity
        changePrank(apps[1], apps[1]);
        (, address[] memory accounts, int256[] memory liquidity,) =
            _updateLocalLiquidity(liquidityMatrices[1], apps[1], storages[1], users, seed);

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // First settlement
        changePrank(settler, settler);
        uint32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedLiquidityRoot(remoteEid);
        liquidityMatrices[0].settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(apps[0], remoteEid, rootTimestamp, accounts, liquidity)
        );

        // Second settlement should revert
        vm.expectRevert(ILiquidityMatrix.LiquidityAlreadySettled.selector);
        liquidityMatrices[0].settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(apps[0], remoteEid, rootTimestamp, accounts, liquidity)
        );
    }

    function test_settleLiquidity_notWhitelisted() public {
        address notWhitelisted = makeAddr("notWhitelisted");
        changePrank(notWhitelisted, notWhitelisted);

        address[] memory accounts = new address[](1);
        accounts[0] = users[0];
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 100e18;

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(apps[0], eids[1], block.timestamp, accounts, liquidity)
        );
    }

    function test_settleLiquidity_mixedResults() public {
        // Setup settler
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);

        // Update remote liquidity with various amounts
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 100e18);
        liquidityMatrices[1].updateLocalLiquidity(users[1], -50e18); // negative
        liquidityMatrices[1].updateLocalLiquidity(users[2], 0); // zero
        liquidityMatrices[1].updateLocalLiquidity(users[3], 200e18);

        // Sync and settle
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedLiquidityRoot(eids[1]);

        changePrank(settler, settler);
        address[] memory accounts = new address[](4);
        int256[] memory liquidity = new int256[](4);
        for (uint256 i = 0; i < 4; i++) {
            accounts[i] = users[i];
        }
        liquidity[0] = 100e18;
        liquidity[1] = -50e18;
        liquidity[2] = 0;
        liquidity[3] = 200e18;

        liquidityMatrices[0].settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(apps[0], eids[1], rootTimestamp, accounts, liquidity)
        );

        // Verify settled values
        assertEq(liquidityMatrices[0].getSettledRemoteLiquidity(apps[0], eids[1], users[0]), 100e18);
        assertEq(liquidityMatrices[0].getSettledRemoteLiquidity(apps[0], eids[1], users[1]), -50e18);
        assertEq(liquidityMatrices[0].getSettledRemoteLiquidity(apps[0], eids[1], users[2]), 0);
        assertEq(liquidityMatrices[0].getSettledRemoteLiquidity(apps[0], eids[1], users[3]), 200e18);
        assertEq(liquidityMatrices[0].getSettledRemoteTotalLiquidity(apps[0], eids[1]), 250e18);
    }

    function test_settleLiquidity_complexScenario() public {
        // Setup settler
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        for (uint256 i = 0; i < CHAINS; i++) {
            liquidityMatrices[i].updateSettlerWhitelisted(settler, true);
        }

        // Each chain updates liquidity for different accounts
        for (uint256 i = 0; i < CHAINS; i++) {
            changePrank(apps[i], apps[i]);
            for (uint256 j = 0; j < 3; j++) {
                liquidityMatrices[i].updateLocalLiquidity(users[j], int256((i + 1) * (j + 1) * 1e18));
            }
        }

        // Sync all chains to chain 0
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint256 i = 1; i < CHAINS; i++) {
            remotes[i - 1] = liquidityMatrices[i];
        }
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settle from each remote chain
        changePrank(settler, settler);
        for (uint256 i = 1; i < CHAINS; i++) {
            (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedLiquidityRoot(eids[i]);

            address[] memory accounts = new address[](3);
            int256[] memory liquidity = new int256[](3);
            for (uint256 j = 0; j < 3; j++) {
                accounts[j] = users[j];
                liquidity[j] = int256((i + 1) * (j + 1) * 1e18);
            }

            liquidityMatrices[0].settleLiquidity(
                ILiquidityMatrix.SettleLiquidityParams(apps[0], eids[i], rootTimestamp, accounts, liquidity)
            );
        }

        // Verify total settled liquidity
        // getSettledTotalLiquidity includes both local liquidity and settled remote liquidity
        int256 totalSettled = liquidityMatrices[0].getSettledTotalLiquidity(apps[0]);

        // Calculate expected total including local chain (i=0) and remote chains (i=1 to CHAINS-1)
        int256 expectedTotal = 0;
        for (uint256 i = 0; i < CHAINS; i++) {
            for (uint256 j = 0; j < 3; j++) {
                expectedTotal += int256((i + 1) * (j + 1) * 1e18);
            }
        }
        assertEq(totalSettled, expectedTotal);
    }

    /*//////////////////////////////////////////////////////////////
                        settleData() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleData(bytes32 seed) public {
        // Setup settler
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);

        // Update remote data
        changePrank(apps[1], apps[1]);
        (, bytes32[] memory keys, bytes[] memory values) =
            _updateLocalData(liquidityMatrices[1], apps[1], storages[1], seed);

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settle data
        changePrank(settler, settler);
        uint32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedDataRoot(remoteEid);
        liquidityMatrices[0].settleData(
            ILiquidityMatrix.SettleDataParams(apps[0], remoteEid, rootTimestamp, keys, values)
        );

        // Verify settlement
        for (uint256 i; i < keys.length; ++i) {
            assertEq(liquidityMatrices[0].getSettledRemoteDataHash(apps[0], remoteEid, keys[i]), keccak256(values[i]));
        }
        assertTrue(liquidityMatrices[0].isDataSettled(apps[0], remoteEid, rootTimestamp));
    }

    function test_settleData_alreadySettled() public {
        // Setup settler
        address settler = makeAddr("settler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);

        // Update remote data
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalData(keccak256("key"), abi.encode("value"));

        // Sync
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Get root timestamp
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastSyncedDataRoot(eids[1]);

        // First settlement
        changePrank(settler, settler);
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("key");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("value");

        liquidityMatrices[0].settleData(
            ILiquidityMatrix.SettleDataParams(apps[0], eids[1], rootTimestamp, keys, values)
        );

        // Try to settle again
        vm.expectRevert(ILiquidityMatrix.DataAlreadySettled.selector);
        liquidityMatrices[0].settleData(
            ILiquidityMatrix.SettleDataParams(apps[0], eids[1], rootTimestamp, keys, values)
        );
    }

    function test_settleData_notWhitelisted() public {
        address notWhitelisted = makeAddr("notWhitelisted");
        changePrank(notWhitelisted, notWhitelisted);

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("key");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("value");

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].settleData(
            ILiquidityMatrix.SettleDataParams(apps[0], eids[1], block.timestamp, keys, values)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        onReceiveRoots() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onReceiveRoots_onlySynchronizer() public {
        address notSynchronizer = makeAddr("notSynchronizer");
        changePrank(notSynchronizer, notSynchronizer);

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].onReceiveRoots(eids[1], bytes32(0), bytes32(0), block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                onReceiveMapRemoteAccountRequests() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onReceiveMapRemoteAccountRequests_onlySynchronizer() public {
        address notSynchronizer = makeAddr("notSynchronizer");
        changePrank(notSynchronizer, notSynchronizer);

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(eids[1], apps[0], "");
    }

    function test_onReceiveMapRemoteAccountRequests_remoteAlreadyMapped() public {
        // App is already registered and remote app is already set up in setup()

        // Set up the app mock to allow mapping
        AppMock(apps[0]).setShouldMapAccounts(eids[1], users[0], users[1], true);
        AppMock(apps[0]).setShouldMapAccounts(eids[1], users[0], users[2], true);

        // Simulate receiving a map request from remote chain
        // First mapping succeeds
        changePrank(address(synchronizers[0]), address(synchronizers[0]));
        address[] memory remotes1 = new address[](1);
        address[] memory locals1 = new address[](1);
        remotes1[0] = users[0];
        locals1[0] = users[1];
        bytes memory message1 = abi.encode(remotes1, locals1);
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(eids[1], apps[0], message1);

        // Try to map same remote account to different local
        address[] memory remotes2 = new address[](1);
        address[] memory locals2 = new address[](1);
        remotes2[0] = users[0];
        locals2[0] = users[2];
        bytes memory message2 = abi.encode(remotes2, locals2);
        vm.expectRevert(abi.encodeWithSelector(ILiquidityMatrix.RemoteAccountAlreadyMapped.selector, eids[1], users[0]));
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(eids[1], apps[0], message2);
    }

    function test_onReceiveMapRemoteAccountRequests_localAlreadyMapped() public {
        // App is already registered and remote app is already set up in setup()

        // Set up the app mock to allow mapping
        AppMock(apps[0]).setShouldMapAccounts(eids[1], users[0], users[1], true);
        AppMock(apps[0]).setShouldMapAccounts(eids[1], users[2], users[1], true);

        // Simulate receiving a map request from remote chain
        // First mapping succeeds
        changePrank(address(synchronizers[0]), address(synchronizers[0]));
        address[] memory remotes1 = new address[](1);
        address[] memory locals1 = new address[](1);
        remotes1[0] = users[0];
        locals1[0] = users[1];
        bytes memory message1 = abi.encode(remotes1, locals1);
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(eids[1], apps[0], message1);

        // Try to map different remote account to same local
        address[] memory remotes2 = new address[](1);
        address[] memory locals2 = new address[](1);
        remotes2[0] = users[2];
        locals2[0] = users[1];
        bytes memory message2 = abi.encode(remotes2, locals2);
        vm.expectRevert(abi.encodeWithSelector(ILiquidityMatrix.LocalAccountAlreadyMapped.selector, eids[1], users[1]));
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(eids[1], apps[0], message2);
    }

    /*//////////////////////////////////////////////////////////////
                  requestMapRemoteAccounts() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_requestMapRemoteAccounts() public {
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        address[] memory remoteApps = new address[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            remotes[i - 1] = liquidityMatrices[i];
            remoteApps[i - 1] = apps[i];
        }
        _requestMapRemoteAccounts(liquidityMatrices[0], apps[0], remotes, remoteApps, users);
    }

    function test_requestMapRemoteAccounts_invalidLengths() public {
        changePrank(apps[0], apps[0]);

        address[] memory remotes = new address[](2);
        address[] memory locals = new address[](3); // Different length

        vm.expectRevert(ILiquidityMatrix.InvalidLengths.selector);
        liquidityMatrices[0].requestMapRemoteAccounts{ value: 1 ether }(eids[1], apps[1], remotes, locals, 100_000);
    }

    function test_requestMapRemoteAccounts_invalidAddress() public {
        changePrank(apps[0], apps[0]);

        address[] memory remotes = new address[](1);
        address[] memory locals = new address[](1);
        locals[0] = address(0); // Invalid address

        vm.expectRevert(ILiquidityMatrix.InvalidAddress.selector);
        liquidityMatrices[0].requestMapRemoteAccounts{ value: 1 ether }(eids[1], apps[1], remotes, locals, 100_000);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Override _eid functions to handle array-based structure
    function _eid(ILiquidityMatrix liquidityMatrix) internal view override returns (uint32) {
        for (uint32 i = 0; i < CHAINS; ++i) {
            if (address(liquidityMatrix) == address(liquidityMatrices[i])) {
                return eids[i];
            }
        }
        revert("Unknown LiquidityMatrix");
    }

    function _eid(address addr) internal view override returns (uint32) {
        // For synchronizer addresses, check which endpoint they're associated with
        for (uint32 i = 0; i < CHAINS; ++i) {
            if (address(liquidityMatrices[i]) != address(0) && addr == address(synchronizers[i])) {
                return eids[i];
            }
        }
        revert("Unknown address");
    }
}
