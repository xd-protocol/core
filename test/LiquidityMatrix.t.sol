// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { LayerZeroGateway } from "src/gateways/LayerZeroGateway.sol";
import { IRemoteAppChronicle } from "src/interfaces/IRemoteAppChronicle.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
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
    LiquidityMatrix[CHAINS] liquidityMatrices;
    LayerZeroGateway[CHAINS] gateways;
    address[CHAINS] apps;
    Storage[CHAINS] storages;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address[] users;
    address[CHAINS] settlers;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(CHAINS, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        address[] memory oapps = new address[](CHAINS);
        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            syncers[i] = makeAddr(string.concat("syncer", vm.toString(i)));
            // Create LiquidityMatrix with owner and timestamp
            liquidityMatrices[i] = new LiquidityMatrix(owner, 1);

            // Create Gateway first
            gateways[i] =
                new LayerZeroGateway(DEFAULT_CHANNEL_ID, endpoints[eids[i]], address(liquidityMatrices[i]), owner);

            // Set gateway and syncer in LiquidityMatrix
            liquidityMatrices[i].updateGateway(address(gateways[i]));
            liquidityMatrices[i].updateSyncer(syncers[i]);

            // Register LiquidityMatrix as an app with the gateway
            gateways[i].registerApp(address(liquidityMatrices[i]));

            oapps[i] = address(gateways[i]);
            apps[i] = address(new AppMock(address(liquidityMatrices[i])));
            settlers[i] = address(new SettlerMock(address(liquidityMatrices[i])));
            liquidityMatrices[i].updateSettlerWhitelisted(settlers[i], true);
        }

        wireOApps(oapps);

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(apps[i], 1000e18);
            changePrank(apps[i], apps[i]);
            liquidityMatrices[i].registerApp(false, false, settlers[i]);

            uint32[] memory configEids = new uint32[](CHAINS - 1);
            uint16[] memory configConfirmations = new uint16[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configEids[count] = eids[j];
                configConfirmations[count] = 0;
                count++;
            }

            changePrank(owner, owner);
            bytes32[] memory chainUIDs = new bytes32[](configEids.length);
            for (uint256 k; k < configEids.length; k++) {
                chainUIDs[k] = bytes32(uint256(configEids[k]));
            }
            gateways[i].configChains(chainUIDs, configConfirmations);

            // Set read targets for LiquidityMatrix to read each other
            for (uint32 j; j < CHAINS; ++j) {
                if (i != j) {
                    liquidityMatrices[i].updateReadTarget(
                        bytes32(uint256(eids[j])), bytes32(uint256(uint160(address(liquidityMatrices[j]))))
                    );
                }
            }
            initialize(storages[i]);
        }

        // Create RemoteAppChronicles for each app to track remote chains
        for (uint32 i; i < CHAINS; ++i) {
            changePrank(settlers[i], settlers[i]);
            for (uint32 j; j < CHAINS; ++j) {
                if (i != j) {
                    // Create RemoteAppChronicle for app[i] to track chain j
                    liquidityMatrices[i].addRemoteAppChronicle(apps[i], bytes32(uint256(eids[j])), 1);
                }
            }
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
        for (uint256 i; i < settlers.length; ++i) {
            vm.deal(settlers[i], 10_000e18);
        }
        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }

        changePrank(users[0], users[0]);
    }

    /*//////////////////////////////////////////////////////////////
                        getAppSetting() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getAppSetting() public {
        // Test with existing app
        (bool registered, bool syncMappedAccountsOnly, bool useCallbacks, address settler) =
            liquidityMatrices[0].getAppSetting(apps[0]);
        assertTrue(registered);
        assertFalse(syncMappedAccountsOnly);
        assertFalse(useCallbacks);
        assertEq(settler, settlers[0]);

        // Test with unregistered app
        address unregisteredApp = makeAddr("unregisteredApp");
        (registered, syncMappedAccountsOnly, useCallbacks, settler) =
            liquidityMatrices[0].getAppSetting(unregisteredApp);
        assertFalse(registered);
        assertFalse(syncMappedAccountsOnly);
        assertFalse(useCallbacks);
        assertEq(settler, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        getLocalLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalLiquidity() public {
        changePrank(apps[0], apps[0]);

        // Initially zero
        assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], users[0]), 0);

        // Update liquidity
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], users[0]), 100e18);

        // Update again
        liquidityMatrices[0].updateLocalLiquidity(users[0], -50e18);
        assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], users[0]), -50e18);
    }

    /*//////////////////////////////////////////////////////////////
                    getLocalLiquidityAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalLiquidityAt() public {
        changePrank(apps[0], apps[0]);

        // Create a series of liquidity updates at different timestamps
        uint256[] memory timestamps = new uint256[](4);
        int256[] memory liquidityValues = new int256[](4);

        // T0: Initial state (should be 0)
        timestamps[0] = block.timestamp;
        liquidityValues[0] = 0;

        // T1: First update
        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        timestamps[1] = block.timestamp;
        liquidityValues[1] = 100e18;

        // T2: Update to negative
        skip(200);
        liquidityMatrices[0].updateLocalLiquidity(users[0], -50e18);
        timestamps[2] = block.timestamp;
        liquidityValues[2] = -50e18;

        // T3: Large positive update
        skip(300);
        liquidityMatrices[0].updateLocalLiquidity(users[0], 1000e18);
        timestamps[3] = block.timestamp;
        liquidityValues[3] = 1000e18;

        // Test historical queries
        for (uint256 i = 0; i < timestamps.length; i++) {
            // Query at exact timestamp
            assertEq(
                liquidityMatrices[0].getLocalLiquidityAt(apps[0], users[0], uint64(timestamps[i])),
                liquidityValues[i],
                "Failed at exact timestamp"
            );

            // Query slightly after timestamp (should return same value)
            if (i < timestamps.length - 1) {
                assertEq(
                    liquidityMatrices[0].getLocalLiquidityAt(apps[0], users[0], uint64(timestamps[i] + 50)),
                    liquidityValues[i],
                    "Failed at timestamp + 50"
                );
            }
        }

        // Query before any updates (should return 0)
        if (timestamps[0] > 100) {
            assertEq(liquidityMatrices[0].getLocalLiquidityAt(apps[0], users[0], uint64(timestamps[0] - 100)), 0);
        } else {
            assertEq(liquidityMatrices[0].getLocalLiquidityAt(apps[0], users[0], 0), 0);
        }

        // Query far in the future (should return last value)
        assertEq(liquidityMatrices[0].getLocalLiquidityAt(apps[0], users[0], uint64(block.timestamp + 10_000)), 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                    getLocalTotalLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalTotalLiquidity() public {
        changePrank(apps[0], apps[0]);

        // Initially zero
        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), 0);

        // Update liquidity for multiple accounts
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), 100e18);

        liquidityMatrices[0].updateLocalLiquidity(users[1], 200e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), 300e18);

        liquidityMatrices[0].updateLocalLiquidity(users[2], -50e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), 250e18);
    }

    /*//////////////////////////////////////////////////////////////
                getLocalTotalLiquidityAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalTotalLiquidityAt() public {
        changePrank(apps[0], apps[0]);

        // Create multiple accounts with updates at different times
        uint256[] memory timestamps = new uint256[](4);
        int256[] memory expectedTotals = new int256[](4);

        // T0: Initial state
        timestamps[0] = block.timestamp;
        expectedTotals[0] = 0;

        // T1: Add liquidity to account 0
        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        timestamps[1] = block.timestamp;
        expectedTotals[1] = 100e18;

        // T2: Add liquidity to account 1
        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[1], 200e18);
        timestamps[2] = block.timestamp;
        expectedTotals[2] = 300e18;

        // T3: Update account 0 to negative
        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[0], -50e18);
        timestamps[3] = block.timestamp;
        expectedTotals[3] = 150e18; // -50 + 200

        // Test all historical points
        for (uint256 i = 0; i < timestamps.length; i++) {
            assertEq(
                liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[i])),
                expectedTotals[i],
                "Failed at timestamp index"
            );

            // Test between timestamps
            if (i > 0) {
                uint256 midpoint = timestamps[i - 1] + (timestamps[i] - timestamps[i - 1]) / 2;
                assertEq(
                    liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(midpoint)),
                    expectedTotals[i - 1],
                    "Failed at midpoint"
                );
            }
        }

        // Query before any updates (should return 0)
        if (timestamps[0] > 100) {
            assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[0] - 100)), 0);
        } else {
            assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], 0), 0);
        }

        // Query far in the future (should return last value)
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(block.timestamp + 10_000)), 150e18);
    }

    /*//////////////////////////////////////////////////////////////
                        getLocalData() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalData() public {
        changePrank(apps[0], apps[0]);
        bytes32 key = keccak256("testKey");

        // Initially empty
        assertEq(liquidityMatrices[0].getLocalData(apps[0], key), "");

        // Update data
        bytes memory value = abi.encode("testValue");
        liquidityMatrices[0].updateLocalData(key, value);
        assertEq(liquidityMatrices[0].getLocalData(apps[0], key), value);

        // Update again
        bytes memory newValue = abi.encode("newValue");
        liquidityMatrices[0].updateLocalData(key, newValue);
        assertEq(liquidityMatrices[0].getLocalData(apps[0], key), newValue);
    }

    /*//////////////////////////////////////////////////////////////
                    getLocalDataAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalDataAt() public {
        changePrank(apps[0], apps[0]);

        bytes32 key = keccak256("config");
        uint256[] memory timestamps = new uint256[](5);
        bytes[] memory dataValues = new bytes[](5);

        // T0: Initial state (no data)
        timestamps[0] = block.timestamp;
        dataValues[0] = "";
        assertEq(liquidityMatrices[0].getLocalDataAt(apps[0], key, uint64(timestamps[0])), dataValues[0]);

        // T1: First data update
        skip(100);
        bytes memory data1 = abi.encode("version1", 100);
        liquidityMatrices[0].updateLocalData(key, data1);
        timestamps[1] = block.timestamp;
        dataValues[1] = data1;

        // T2: Update data with more complex structure
        skip(200);
        bytes memory data2 = abi.encode("version2", 200, true, address(0x123));
        liquidityMatrices[0].updateLocalData(key, data2);
        timestamps[2] = block.timestamp;
        dataValues[2] = data2;

        // T3: Clear data (empty bytes)
        skip(300);
        bytes memory emptyData = "";
        liquidityMatrices[0].updateLocalData(key, emptyData);
        timestamps[3] = block.timestamp;
        dataValues[3] = emptyData;

        // T4: Large data update
        skip(400);
        bytes memory largeData = abi.encode(
            "version3", block.timestamp, users[0], users[1], users[2], keccak256("metadata"), uint256(999_999)
        );
        liquidityMatrices[0].updateLocalData(key, largeData);
        timestamps[4] = block.timestamp;
        dataValues[4] = largeData;

        // Verify all historical values at exact timestamps
        for (uint256 i = 0; i < timestamps.length; i++) {
            assertEq(
                liquidityMatrices[0].getLocalDataAt(apps[0], key, uint64(timestamps[i])),
                dataValues[i],
                string.concat("Failed at timestamp index ", vm.toString(i))
            );
        }

        // Test queries between updates (should return the value at or before the timestamp)
        assertEq(
            liquidityMatrices[0].getLocalDataAt(apps[0], key, uint64(timestamps[1] + 50)),
            dataValues[1],
            "Between T1 and T2"
        );
        assertEq(
            liquidityMatrices[0].getLocalDataAt(apps[0], key, uint64(timestamps[2] + 100)),
            dataValues[2],
            "Between T2 and T3"
        );
        assertEq(
            liquidityMatrices[0].getLocalDataAt(apps[0], key, uint64(timestamps[3] + 150)),
            dataValues[3],
            "Between T3 and T4"
        );

        // Test before any data (should return empty)
        if (timestamps[0] > 100) {
            assertEq(
                liquidityMatrices[0].getLocalDataAt(apps[0], key, uint64(timestamps[0] - 100)), "", "Before any data"
            );
        }

        // Test future timestamp (should return latest value)
        assertEq(
            liquidityMatrices[0].getLocalDataAt(apps[0], key, uint64(block.timestamp + 10_000)),
            dataValues[4],
            "Future timestamp"
        );

        // Test with different key (should always return empty)
        bytes32 differentKey = keccak256("different");
        for (uint256 i = 0; i < timestamps.length; i++) {
            assertEq(
                liquidityMatrices[0].getLocalDataAt(apps[0], differentKey, uint64(timestamps[i])),
                "",
                "Different key should return empty"
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    getLocalLiquidityRoot() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalLiquidityRoot() public {
        changePrank(apps[0], apps[0]);

        // Get initial root
        bytes32 initialRoot = liquidityMatrices[0].getLocalLiquidityRoot(apps[0]);

        // Update liquidity changes the root
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        bytes32 newRoot = liquidityMatrices[0].getLocalLiquidityRoot(apps[0]);
        assertTrue(newRoot != initialRoot);
        assertTrue(newRoot != bytes32(0));

        // Another update changes root again
        liquidityMatrices[0].updateLocalLiquidity(users[1], 200e18);
        bytes32 newerRoot = liquidityMatrices[0].getLocalLiquidityRoot(apps[0]);
        assertTrue(newerRoot != newRoot);
        assertTrue(newerRoot != bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                        getLocalDataRoot() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalDataRoot() public {
        changePrank(apps[0], apps[0]);

        // Get initial root
        bytes32 initialRoot = liquidityMatrices[0].getLocalDataRoot(apps[0]);

        // Update data changes the root
        liquidityMatrices[0].updateLocalData(keccak256("key1"), abi.encode("value1"));
        bytes32 newRoot = liquidityMatrices[0].getLocalDataRoot(apps[0]);
        assertTrue(newRoot != initialRoot);
        assertTrue(newRoot != bytes32(0));

        // Another update changes root again
        liquidityMatrices[0].updateLocalData(keccak256("key2"), abi.encode("value2"));
        bytes32 newerRoot = liquidityMatrices[0].getLocalDataRoot(apps[0]);
        assertTrue(newerRoot != newRoot);
        assertTrue(newerRoot != bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                        getTopRoots() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getTopRoots() public {
        changePrank(apps[0], apps[0]);

        // Get initial roots
        (uint256 version1, bytes32 liquidityRoot1, bytes32 dataRoot1, uint256 timestamp1) =
            liquidityMatrices[0].getTopRoots();
        assertEq(version1, 1); // Initial version should be 1 (set in constructor)
        assertEq(timestamp1, block.timestamp);

        // Update liquidity changes main liquidity root
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        (uint256 version2, bytes32 liquidityRoot2, bytes32 dataRoot2, uint256 timestamp2) =
            liquidityMatrices[0].getTopRoots();
        assertEq(version2, 1); // Version should remain 1 (no reorg)
        assertTrue(liquidityRoot2 != liquidityRoot1);
        assertEq(dataRoot2, dataRoot1); // Data root unchanged
        assertEq(timestamp2, block.timestamp);

        // Update data changes main data root
        liquidityMatrices[0].updateLocalData(keccak256("key"), abi.encode("value"));
        (uint256 version3, bytes32 liquidityRoot3, bytes32 dataRoot3, uint256 timestamp3) =
            liquidityMatrices[0].getTopRoots();
        assertEq(version3, 1); // Version should still be 1 (no reorg)
        assertEq(liquidityRoot3, liquidityRoot2); // Liquidity root unchanged
        assertTrue(dataRoot3 != dataRoot2);
        assertEq(timestamp3, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        getMappedAccount() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getMappedAccount() public {
        // Initially no mapping
        assertEq(
            liquidityMatrices[0].getMappedAccount(apps[0], bytes32(uint256(bytes32(uint256(eids[1])))), users[0]),
            address(0)
        );

        // Setup mapping via onReceiveMapRemoteAccountRequests
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(bytes32(uint256(eids[1])))), users[0], users[1], true);

        address[] memory remotes = new address[](1);
        address[] memory locals = new address[](1);
        remotes[0] = users[0];
        locals[0] = users[1];
        bytes memory message = abi.encode(remotes, locals);

        changePrank(address(gateways[0]), address(gateways[0]));
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(
            bytes32(uint256(bytes32(uint256(eids[1])))), apps[0], message
        );

        // Now mapping exists
        assertEq(
            liquidityMatrices[0].getMappedAccount(apps[0], bytes32(uint256(bytes32(uint256(eids[1])))), users[0]),
            users[1]
        );
    }

    /*//////////////////////////////////////////////////////////////
                    isLocalAccountMapped() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_isLocalAccountMapped() public {
        // Initially not mapped
        assertFalse(
            liquidityMatrices[0].isLocalAccountMapped(apps[0], bytes32(uint256(bytes32(uint256(eids[1])))), users[1])
        );

        // Setup mapping
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(bytes32(uint256(eids[1])))), users[0], users[1], true);

        address[] memory remotes = new address[](1);
        address[] memory locals = new address[](1);
        remotes[0] = users[0];
        locals[0] = users[1];
        bytes memory message = abi.encode(remotes, locals);

        changePrank(address(gateways[0]), address(gateways[0]));
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(
            bytes32(uint256(bytes32(uint256(eids[1])))), apps[0], message
        );

        // Now local account is mapped
        assertTrue(
            liquidityMatrices[0].isLocalAccountMapped(apps[0], bytes32(uint256(bytes32(uint256(eids[1])))), users[1])
        );

        // Other accounts still not mapped
        assertFalse(
            liquidityMatrices[0].isLocalAccountMapped(apps[0], bytes32(uint256(bytes32(uint256(eids[1])))), users[2])
        );
    }

    /*//////////////////////////////////////////////////////////////
                  getLastReceivedLiquidityRoot() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLastReceivedLiquidityRoot() public {
        // Initially no root
        (bytes32 root, uint256 timestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);

        // Update remote liquidity and sync
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 100e18);

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Now has received root
        (root, timestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(bytes32(uint256(eids[1])));
        assertTrue(root != bytes32(0));
        assertTrue(timestamp > 0);

        // Sync again with updated liquidity
        skip(100);
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 200e18);
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Should return the latest root
        (bytes32 newRoot, uint256 newTimestamp) =
            liquidityMatrices[0].getLastReceivedLiquidityRoot(bytes32(uint256(eids[1])));
        assertTrue(newRoot != root);
        assertTrue(newTimestamp > timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                    getLastReceivedDataRoot() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLastReceivedDataRoot() public {
        // Initially no root
        (bytes32 root, uint256 timestamp) = liquidityMatrices[0].getLastReceivedDataRoot(bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);

        // Update remote data and sync
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalData(keccak256("key"), abi.encode("value"));

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Now has received root
        (root, timestamp) = liquidityMatrices[0].getLastReceivedDataRoot(bytes32(uint256(eids[1])));
        assertTrue(root != bytes32(0));
        assertTrue(timestamp > 0);
    }

    /*//////////////////////////////////////////////////////////////
                    isSettlerWhitelisted() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_isSettlerWhitelisted() public {
        address settler = settlers[0];

        // Settler was already whitelisted during setup
        assertTrue(liquidityMatrices[0].isSettlerWhitelisted(settler));

        // Remove from whitelist
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler, false);
        assertFalse(liquidityMatrices[0].isSettlerWhitelisted(settler));

        // Whitelist again
        liquidityMatrices[0].updateSettlerWhitelisted(settler, true);
        assertTrue(liquidityMatrices[0].isSettlerWhitelisted(settler));
    }

    /*//////////////////////////////////////////////////////////////
                      getLiquidityRootAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLiquidityRootAt() public {
        // Setup: Create liquidity updates on remote chain
        changePrank(apps[1], apps[1]);

        // T0: Initial liquidity state
        liquidityMatrices[1].updateLocalLiquidity(users[0], 100e18);
        liquidityMatrices[1].updateLocalLiquidity(users[1], 200e18);
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        (bytes32[] memory liquidityRoots0,, uint256[] memory timestamps0) =
            _sync(syncers[0], liquidityMatrices[0], remotes);
        bytes32 liquidityRoot0 = liquidityRoots0[0];
        uint256 timestamp0 = timestamps0[0];

        // T1: Update liquidity
        skip(1000);
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 150e18);
        liquidityMatrices[1].updateLocalLiquidity(users[2], 300e18);
        (bytes32[] memory liquidityRoots1,, uint256[] memory timestamps1) =
            _sync(syncers[0], liquidityMatrices[0], remotes);
        bytes32 liquidityRoot1 = liquidityRoots1[0];
        uint256 timestamp1 = timestamps1[0];

        // T2: Clear some liquidity
        skip(1000);
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 0);
        liquidityMatrices[1].updateLocalLiquidity(users[1], 0);
        (bytes32[] memory liquidityRoots2,, uint256[] memory timestamps2) =
            _sync(syncers[0], liquidityMatrices[0], remotes);
        bytes32 liquidityRoot2 = liquidityRoots2[0];
        uint256 timestamp2 = timestamps2[0];

        bytes32 remoteEid = _eid(liquidityMatrices[1]);

        // Verify exact timestamps return the received roots
        assertEq(
            liquidityMatrices[0].getLiquidityRootAt(remoteEid, uint64(timestamp0)),
            liquidityRoot0,
            "Root at T0 mismatch"
        );
        assertEq(
            liquidityMatrices[0].getLiquidityRootAt(remoteEid, uint64(timestamp1)),
            liquidityRoot1,
            "Root at T1 mismatch"
        );
        assertEq(
            liquidityMatrices[0].getLiquidityRootAt(remoteEid, uint64(timestamp2)),
            liquidityRoot2,
            "Root at T2 mismatch"
        );

        // Verify roots changed between syncs
        assertTrue(liquidityRoot0 != liquidityRoot1, "Root should change after update");
        assertTrue(liquidityRoot1 != liquidityRoot2, "Root should change after clearing");

        // Test between timestamps (should return 0 as no root at exact timestamp)
        assertEq(liquidityMatrices[0].getLiquidityRootAt(remoteEid, uint64(timestamp0 + 100)), bytes32(0));
        assertEq(liquidityMatrices[0].getLiquidityRootAt(remoteEid, uint64(timestamp1 + 100)), bytes32(0));

        // Test before first root
        if (timestamp0 > 100) {
            assertEq(liquidityMatrices[0].getLiquidityRootAt(remoteEid, uint64(timestamp0 - 100)), bytes32(0));
        }

        // Test far future
        assertEq(liquidityMatrices[0].getLiquidityRootAt(remoteEid, uint64(block.timestamp + 10_000)), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                        getDataRootAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getDataRootAt_historicalValues() public {
        // Setup: Create data updates on remote chain
        changePrank(apps[1], apps[1]);

        // T0: Initial data state
        bytes32 key1 = keccak256("config");
        bytes32 key2 = keccak256("settings");
        bytes memory data1 = abi.encode("version1", 100);
        bytes memory data2 = abi.encode("enabled", true);

        liquidityMatrices[1].updateLocalData(key1, data1);
        liquidityMatrices[1].updateLocalData(key2, data2);
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        (, bytes32[] memory dataRoots0, uint256[] memory timestamps0) = _sync(syncers[0], liquidityMatrices[0], remotes);
        bytes32 dataRoot0 = dataRoots0[0];
        uint256 timestamp0 = timestamps0[0];

        // T1: Update data
        skip(1000);
        changePrank(apps[1], apps[1]);
        bytes memory data1_v2 = abi.encode("version2", 200);
        bytes memory data3 = abi.encode("newFeature", 42);
        liquidityMatrices[1].updateLocalData(key1, data1_v2);
        liquidityMatrices[1].updateLocalData(keccak256("feature"), data3);
        (, bytes32[] memory dataRoots1, uint256[] memory timestamps1) = _sync(syncers[0], liquidityMatrices[0], remotes);
        bytes32 dataRoot1 = dataRoots1[0];
        uint256 timestamp1 = timestamps1[0];

        // T2: Clear some data (set to empty)
        skip(1000);
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalData(key1, "");
        liquidityMatrices[1].updateLocalData(key2, "");
        (, bytes32[] memory dataRoots2, uint256[] memory timestamps2) = _sync(syncers[0], liquidityMatrices[0], remotes);
        bytes32 dataRoot2 = dataRoots2[0];
        uint256 timestamp2 = timestamps2[0];

        bytes32 remoteEid = _eid(liquidityMatrices[1]);

        // Verify exact timestamps return the received roots
        assertEq(
            liquidityMatrices[0].getDataRootAt(remoteEid, uint64(timestamp0)), dataRoot0, "Data root at T0 mismatch"
        );
        assertEq(
            liquidityMatrices[0].getDataRootAt(remoteEid, uint64(timestamp1)), dataRoot1, "Data root at T1 mismatch"
        );
        assertEq(
            liquidityMatrices[0].getDataRootAt(remoteEid, uint64(timestamp2)), dataRoot2, "Data root at T2 mismatch"
        );

        // Verify roots changed between syncs
        assertTrue(dataRoot0 != dataRoot1, "Data root should change after update");
        assertTrue(dataRoot1 != dataRoot2, "Data root should change after clearing");

        // Test between timestamps (should return 0 as no root at exact timestamp)
        assertEq(liquidityMatrices[0].getDataRootAt(remoteEid, uint64(timestamp0 + 100)), bytes32(0));
        assertEq(liquidityMatrices[0].getDataRootAt(remoteEid, uint64(timestamp1 + 100)), bytes32(0));

        // Test before first root
        if (timestamp0 > 100) {
            assertEq(liquidityMatrices[0].getDataRootAt(remoteEid, uint64(timestamp0 - 100)), bytes32(0));
        }

        // Test far future
        assertEq(liquidityMatrices[0].getDataRootAt(remoteEid, uint64(block.timestamp + 10_000)), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
              getLocalTotalLiquidityAt() with Remote TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLocalTotalLiquidityAt_withRemote() public {
        // Setup settler
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup

        // Create a series of local liquidity updates at different timestamps
        uint256[] memory timestamps = new uint256[](4);

        // T0: Initial state (should be 0)
        timestamps[0] = block.timestamp;
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[0])), 0);

        // T1: First update
        skip(100);
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateLocalLiquidity(users[0], 100e18);
        timestamps[1] = block.timestamp;

        // T2: Second update
        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[1], 200e18);
        timestamps[2] = block.timestamp;

        // T3: Third update
        skip(100);
        liquidityMatrices[0].updateLocalLiquidity(users[0], 150e18);
        timestamps[3] = block.timestamp;

        // Test queries at exact timestamps for LOCAL total liquidity
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[0])), 0);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[1])), 100e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[2])), 300e18); // 100 + 200
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[3])), 350e18); // 150 + 200

        // Test queries between timestamps (should return value at or before query time)
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[1] + 50)), 100e18);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[2] + 50)), 300e18);

        // Test query far in the future (should return latest value)
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(block.timestamp + 10_000)), 350e18);

        // Add remote liquidity
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 400e18);
        liquidityMatrices[1].updateLocalLiquidity(users[2], 100e18);

        // Sync remote roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settle remote liquidity
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(bytes32(uint256(eids[1])));
        changePrank(settler, settler);
        address[] memory accounts = new address[](2);
        accounts[0] = users[0];
        accounts[1] = users[2];
        int256[] memory liquidity = new int256[](2);
        liquidity[0] = 400e18;
        liquidity[1] = 100e18;

        // Get the RemoteAppChronicle and settle liquidity there
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), accounts, liquidity)
        );

        // Test REMOTE total liquidity after settling (for the specific remote chain)
        // Remote chain total: 500e18 (400 + 100)
        assertEq(
            liquidityMatrices[0].getTotalLiquidityAt(apps[0], bytes32(uint256(eids[1])), uint64(block.timestamp)),
            500e18
        );

        // Test historical query for LOCAL total liquidity still returns correct value
        assertEq(liquidityMatrices[0].getLocalTotalLiquidityAt(apps[0], uint64(timestamps[3])), 350e18);
    }

    /*//////////////////////////////////////////////////////////////
                        registerApp() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerApp() public {
        address newSettler = makeAddr("newSettler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(newSettler, true);

        address newApp = address(new AppMock(address(liquidityMatrices[0])));
        changePrank(newApp, newApp);
        liquidityMatrices[0].registerApp(true, true, newSettler);

        (bool registered, bool syncMappedAccountsOnly, bool useCallbacks, address settler) =
            liquidityMatrices[0].getAppSetting(newApp);
        assertTrue(registered);
        assertTrue(syncMappedAccountsOnly);
        assertTrue(useCallbacks);
        assertEq(settler, newSettler);
    }

    function test_registerApp_alreadyRegistered() public {
        address newSettler = makeAddr("newSettler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(newSettler, true);

        address newApp = makeAddr("newApp");
        changePrank(newApp, newApp);
        liquidityMatrices[0].registerApp(false, false, newSettler);

        vm.expectRevert(ILiquidityMatrix.AppAlreadyRegistered.selector);
        liquidityMatrices[0].registerApp(false, false, newSettler);
    }

    function test_registerApp_multipleAppsWithDifferentSettings() public {
        // Register multiple apps with different settings
        address app1 = makeAddr("app1");
        address app2 = makeAddr("app2");
        address app3 = makeAddr("app3");
        address settler1 = settlers[0];
        address settler2 = settlers[1];

        // Whitelist settlers
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(settler1, true);
        liquidityMatrices[0].updateSettlerWhitelisted(settler2, true);

        // App1: sync all accounts, no callbacks, with settler1
        changePrank(app1, app1);
        liquidityMatrices[0].registerApp(false, false, settler1);

        // App2: sync mapped only, with callbacks, with settler1
        changePrank(app2, app2);
        liquidityMatrices[0].registerApp(true, true, settler1);

        // App3: no sync mapped only, with callbacks, different settler
        changePrank(app3, app3);
        liquidityMatrices[0].registerApp(false, true, settler2);

        // Verify all settings
        (bool registered1, bool syncMapped1, bool callbacks1, address settlerAddr1) =
            liquidityMatrices[0].getAppSetting(app1);
        assertTrue(registered1);
        assertFalse(syncMapped1);
        assertFalse(callbacks1);
        assertEq(settlerAddr1, settler1);

        (bool registered2, bool syncMapped2, bool callbacks2, address settlerAddr2) =
            liquidityMatrices[0].getAppSetting(app2);
        assertTrue(registered2);
        assertTrue(syncMapped2);
        assertTrue(callbacks2);
        assertEq(settlerAddr2, settler1);
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
                    updateUseHook() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateUseHook() public {
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateUseHook(true);

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
                    updateLocalLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateLocalLiquidity(bytes32 seed) public {
        changePrank(apps[0], apps[0]);
        _updateLocalLiquidity(liquidityMatrices[0], apps[0], storages[0], users, seed);
    }

    function test_updateLocalLiquidity_forbidden() public {
        address unregisteredApp = makeAddr("unregisteredApp");
        changePrank(unregisteredApp, unregisteredApp);

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
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
        // Whitelist a settler
        address testSettler = makeAddr("testSettler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(testSettler, true);

        // Register multiple apps
        address[] memory testApps = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            testApps[i] = makeAddr(string.concat("testApp", vm.toString(i)));
            changePrank(testApps[i], testApps[i]);
            liquidityMatrices[0].registerApp(false, false, testSettler);
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

    function test_updateLocalLiquidity_highFrequencyUpdates() public {
        // Simulate high-frequency trading scenario
        changePrank(apps[0], apps[0]);

        uint256 numUpdates = 50;
        int256 currentLiquidity = 0;

        for (uint256 i = 0; i < numUpdates; i++) {
            // Simulate various trading patterns
            int256 newLiquidity;
            if (i % 3 == 0) {
                newLiquidity = int256(i * 1e18); // Positive positions
            } else if (i % 3 == 1) {
                newLiquidity = -int256(i * 1e18 / 2); // Negative positions
            } else {
                newLiquidity = currentLiquidity + int256((i % 10) * 1e18) - int256(5e18); // Small adjustments
            }

            liquidityMatrices[0].updateLocalLiquidity(users[0], newLiquidity);
            currentLiquidity = newLiquidity;

            // Verify intermediate state
            if (i % 10 == 0) {
                assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], users[0]), currentLiquidity);
            }
        }

        // Final verification
        assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], users[0]), currentLiquidity);
        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), currentLiquidity);
    }

    function test_updateLocalLiquidity_multipleAccountsParallel() public {
        // Simulate multiple accounts updating in parallel
        changePrank(apps[0], apps[0]);

        uint256 numAccounts = 20;
        address[] memory accounts = new address[](numAccounts);
        int256[] memory currentLiquidity = new int256[](numAccounts);

        // Initialize accounts
        for (uint256 i = 0; i < numAccounts; i++) {
            accounts[i] = makeAddr(string(abi.encodePacked("trader", i)));
        }

        // Simulate trading activity with multiple rounds
        for (uint256 round = 0; round < 5; round++) {
            for (uint256 i = 0; i < numAccounts; i++) {
                // Create diverse liquidity patterns
                int256 newLiquidity = int256((i + 1) * (round + 1) * 1e18);
                if ((i + round) % 3 == 0) newLiquidity = -newLiquidity;

                liquidityMatrices[0].updateLocalLiquidity(accounts[i], newLiquidity);
                currentLiquidity[i] = newLiquidity;
            }
        }

        // Verify all account balances
        int256 totalLiquidity = 0;
        for (uint256 i = 0; i < numAccounts; i++) {
            assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], accounts[i]), currentLiquidity[i]);
            totalLiquidity += currentLiquidity[i];
        }

        assertEq(liquidityMatrices[0].getLocalTotalLiquidity(apps[0]), totalLiquidity);
    }

    /*//////////////////////////////////////////////////////////////
                        updateLocalData() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateLocalData(bytes32 seed) public {
        changePrank(apps[0], apps[0]);
        _updateLocalData(liquidityMatrices[0], apps[0], storages[0], seed);
    }

    function test_updateLocalData_forbidden() public {
        address unregisteredApp = makeAddr("unregisteredApp");
        changePrank(unregisteredApp, unregisteredApp);

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
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

        bytes memory storedData = liquidityMatrices[0].getLocalData(apps[0], key);
        assertEq(keccak256(storedData), keccak256(largeData));
    }

    function test_updateLocalData_largeDataSets() public {
        changePrank(apps[0], apps[0]);

        // Test with various data sizes
        bytes32[] memory keys = new bytes32[](10);
        bytes[] memory values = new bytes[](10);

        for (uint256 i = 0; i < 10; i++) {
            keys[i] = keccak256(abi.encodePacked("key", i));

            // Create progressively larger data
            uint256 dataSize = (i + 1) * 100;
            bytes memory data = new bytes(dataSize);
            for (uint256 j = 0; j < dataSize; j++) {
                data[j] = bytes1(uint8(j % 256));
            }
            values[i] = data;

            liquidityMatrices[0].updateLocalData(keys[i], values[i]);

            // Verify storage
            assertEq(keccak256(liquidityMatrices[0].getLocalData(apps[0], keys[i])), keccak256(values[i]));
        }
    }

    function test_updateLocalData_emptyData() public {
        changePrank(apps[0], apps[0]);

        bytes32 key = keccak256("emptyDataKey");
        bytes memory emptyData = "";

        liquidityMatrices[0].updateLocalData(key, emptyData);

        bytes memory storedData = liquidityMatrices[0].getLocalData(apps[0], key);
        assertEq(keccak256(storedData), keccak256(emptyData));
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
                        settleLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleLiquidity_basic(bytes32 /* seed */ ) public {
        // Use the settler that was configured during app registration
        address settler = settlers[0];

        // Create a smaller set of accounts for this test (the helper creates 256 which is too many)
        changePrank(apps[1], apps[1]);
        address[] memory testAccounts = new address[](3);
        int256[] memory testLiquidity = new int256[](3);
        int256 totalLiquidity;

        // Create test accounts with liquidity
        testAccounts[0] = users[0];
        testAccounts[1] = users[1];
        testAccounts[2] = users[2];

        testLiquidity[0] = 100e18;
        testLiquidity[1] = -50e18;
        testLiquidity[2] = 200e18;

        // Update liquidity for test accounts
        for (uint256 i = 0; i < testAccounts.length; i++) {
            liquidityMatrices[1].updateLocalLiquidity(testAccounts[i], testLiquidity[i]);
            totalLiquidity += testLiquidity[i];
        }

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settle liquidity through RemoteAppChronicle
        changePrank(settler, settler);
        bytes32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(remoteEid);

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), testAccounts, testLiquidity)
        );

        // Verify settlement - check liquidity through LiquidityMatrix wrapper functions
        for (uint256 i = 0; i < testAccounts.length; i++) {
            int256 remoteLiquidity = liquidityMatrices[1].getLocalLiquidity(apps[1], testAccounts[i]);
            assertEq(
                liquidityMatrices[0].getLiquidityAt(apps[0], remoteEid, testAccounts[i], uint64(rootTimestamp)),
                remoteLiquidity
            );
        }
        assertEq(liquidityMatrices[0].getTotalLiquidityAt(apps[0], remoteEid, uint64(rootTimestamp)), totalLiquidity);
        // Check if liquidity is settled through the chronicle
        assertTrue(IRemoteAppChronicle(chronicle).isLiquiditySettled(uint64(rootTimestamp)));
    }

    function test_settleLiquidity_withCallbacks(bytes32 /* seed */ ) public {
        // Use the settler that was configured during app registration
        address settler = settlers[0];

        // Enable callbacks (hooks)
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateUseHook(true);

        // Create a smaller set of accounts for this test
        changePrank(apps[1], apps[1]);
        address[] memory testAccounts = new address[](3);
        int256[] memory testLiquidity = new int256[](3);
        int256 totalLiquidity;

        // Create test accounts with liquidity
        testAccounts[0] = users[0];
        testAccounts[1] = users[1];
        testAccounts[2] = users[2];

        testLiquidity[0] = 100e18;
        testLiquidity[1] = -50e18;
        testLiquidity[2] = 200e18;

        // Update liquidity for test accounts
        for (uint256 i = 0; i < testAccounts.length; i++) {
            liquidityMatrices[1].updateLocalLiquidity(testAccounts[i], testLiquidity[i]);
            totalLiquidity += testLiquidity[i];
        }

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settle liquidity through RemoteAppChronicle
        changePrank(settler, settler);
        bytes32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(remoteEid);

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), testAccounts, testLiquidity)
        );

        // Verify hooks were called with final liquidity values
        assertEq(IAppMock(apps[0]).remoteTotalLiquidity(remoteEid), totalLiquidity);
        for (uint256 i = 0; i < testAccounts.length; i++) {
            int256 remoteLiquidity = liquidityMatrices[1].getLocalLiquidity(apps[1], testAccounts[i]);
            assertEq(IAppMock(apps[0]).remoteLiquidity(remoteEid, testAccounts[i]), remoteLiquidity);
        }
    }

    function test_settleLiquidity_alreadySettled(bytes32 /* seed */ ) public {
        // Setup settler
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup

        // Create a smaller set of accounts for this test
        changePrank(apps[1], apps[1]);
        address[] memory accounts = new address[](3);
        int256[] memory liquidity = new int256[](3);

        // Create test accounts with liquidity
        accounts[0] = users[0];
        accounts[1] = users[1];
        accounts[2] = users[2];

        liquidity[0] = 100e18;
        liquidity[1] = -50e18;
        liquidity[2] = 200e18;

        // Update liquidity for test accounts
        for (uint256 i = 0; i < accounts.length; i++) {
            liquidityMatrices[1].updateLocalLiquidity(accounts[i], liquidity[i]);
        }

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // First settlement through RemoteAppChronicle
        changePrank(settler, settler);
        bytes32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(remoteEid);

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), accounts, liquidity)
        );

        // Second settlement should revert
        vm.expectRevert(IRemoteAppChronicle.LiquidityAlreadySettled.selector);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), accounts, liquidity)
        );
    }

    function test_settleLiquidity_notWhitelisted() public {
        address notWhitelisted = makeAddr("notWhitelisted");
        changePrank(notWhitelisted, notWhitelisted);

        address[] memory accounts = new address[](1);
        accounts[0] = users[0];
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 100e18;

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        vm.expectRevert(IRemoteAppChronicle.Forbidden.selector);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(block.timestamp), accounts, liquidity)
        );
    }

    function test_settleLiquidity_mixedResults() public {
        // Setup settler
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup

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

        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(bytes32(uint256(eids[1])));

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

        // Get the RemoteAppChronicle and settle liquidity there
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), accounts, liquidity)
        );

        // Verify settled values through LiquidityMatrix wrapper functions
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], bytes32(uint256(eids[1])), users[0], uint64(rootTimestamp)),
            100e18
        );
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], bytes32(uint256(eids[1])), users[1], uint64(rootTimestamp)),
            -50e18
        );
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], bytes32(uint256(eids[1])), users[2], uint64(rootTimestamp)), 0
        );
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], bytes32(uint256(eids[1])), users[3], uint64(rootTimestamp)),
            200e18
        );
        assertEq(
            liquidityMatrices[0].getTotalLiquidityAt(apps[0], bytes32(uint256(eids[1])), uint64(rootTimestamp)), 250e18
        );
    }

    function test_settleLiquidity_complexScenario() public {
        // Use the settlers that were configured during app registration
        // Each chain has its own settler: settlers[i] for chain i

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

        // Settle from each remote chain through RemoteAppChronicle
        changePrank(settlers[0], settlers[0]);
        // uint256 currentVersion = liquidityMatrices[0].currentVersion();
        for (uint256 i = 1; i < CHAINS; i++) {
            (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(bytes32(uint256(eids[i])));

            address[] memory accounts = new address[](3);
            int256[] memory liquidity = new int256[](3);
            for (uint256 j = 0; j < 3; j++) {
                accounts[j] = users[j];
                liquidity[j] = int256((i + 1) * (j + 1) * 1e18);
            }

            address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[i])));
            IRemoteAppChronicle(chronicle).settleLiquidity(
                IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), accounts, liquidity)
            );
        }

        // Verify total liquidity - calculate from local and remote
        int256 totalLocal = liquidityMatrices[0].getLocalTotalLiquidity(apps[0]);
        int256 totalRemote = 0;
        for (uint256 i = 1; i < CHAINS; i++) {
            (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(bytes32(uint256(eids[i])));
            totalRemote +=
                liquidityMatrices[0].getTotalLiquidityAt(apps[0], bytes32(uint256(eids[i])), uint64(rootTimestamp));
        }
        int256 totalSettled = totalLocal + totalRemote;

        // Calculate expected total including local chain (i=0) and remote chains (i=1 to CHAINS-1)
        int256 expectedTotal = 0;
        for (uint256 i = 0; i < CHAINS; i++) {
            for (uint256 j = 0; j < 3; j++) {
                expectedTotal += int256((i + 1) * (j + 1) * 1e18);
            }
        }
        assertEq(totalSettled, expectedTotal);
    }

    function test_settleLiquidity_partialSettlement() public {
        // Setup
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup

        // Create remote liquidity updates on multiple chains
        uint256 numAccounts = 100;
        address[] memory accounts = new address[](numAccounts);
        int256[] memory liquidity = new int256[](numAccounts);

        for (uint256 i = 0; i < numAccounts; i++) {
            accounts[i] = makeAddr(string(abi.encodePacked("account", i)));
            liquidity[i] = int256((i + 1) * 1e18);

            changePrank(apps[1], apps[1]);
            liquidityMatrices[1].updateLocalLiquidity(accounts[i], liquidity[i]);
        }

        // Sync roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        bytes32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(remoteEid);

        // Settle all accounts at once through RemoteAppChronicle
        changePrank(settler, settler);
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), accounts, liquidity)
        );

        // Verify all settlements using LiquidityMatrix wrapper
        for (uint256 i = 0; i < numAccounts; i++) {
            assertEq(
                liquidityMatrices[0].getLiquidityAt(apps[0], remoteEid, accounts[i], uint64(rootTimestamp)),
                liquidity[i]
            );
        }
    }

    function test_settleLiquidity_conflictingSettlements() public {
        // Use the settler that was configured during app registration
        address settler = settlers[0];

        // Create remote liquidity
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 100e18);
        liquidityMatrices[1].updateLocalLiquidity(users[1], 200e18);

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        bytes32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(remoteEid);

        // Settler settles both accounts through RemoteAppChronicle
        changePrank(settler, settler);
        address[] memory accounts = new address[](2);
        accounts[0] = users[0];
        accounts[1] = users[1];
        int256[] memory liquidity = new int256[](2);
        liquidity[0] = 100e18;
        liquidity[1] = 200e18;

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), accounts, liquidity)
        );

        // Try to settle again (should revert due to LiquidityAlreadySettled)
        vm.expectRevert(IRemoteAppChronicle.LiquidityAlreadySettled.selector);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(rootTimestamp), accounts, liquidity)
        );

        // Verify the first settlement succeeded using LiquidityMatrix wrapper
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], remoteEid, users[0], uint64(rootTimestamp)), 100e18);
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], remoteEid, users[1], uint64(rootTimestamp)), 200e18);

        // Test settlement at different timestamp works
        skip(100);
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 150e18);
        _sync(syncers[0], liquidityMatrices[0], remotes);

        (, uint256 newTimestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(remoteEid);
        changePrank(settler, settler);
        address[] memory newAccounts = new address[](1);
        newAccounts[0] = users[0];
        int256[] memory newLiquidity = new int256[](1);
        newLiquidity[0] = 150e18;

        // This should work as it's a different timestamp
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(newTimestamp), newAccounts, newLiquidity)
        );

        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], remoteEid, users[0], uint64(newTimestamp)), 150e18);
    }

    /*//////////////////////////////////////////////////////////////
                        settleData() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleData(bytes32 seed) public {
        // Setup settler
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup

        // Update remote data
        changePrank(apps[1], apps[1]);
        (, bytes32[] memory keys, bytes[] memory values) =
            _updateLocalData(liquidityMatrices[1], apps[1], storages[1], seed);

        // Sync to get roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settle data through RemoteAppChronicle
        changePrank(settler, settler);
        bytes32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedDataRoot(remoteEid);

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
        IRemoteAppChronicle(chronicle).settleData(
            IRemoteAppChronicle.SettleDataParams(uint64(rootTimestamp), keys, values)
        );

        // Verify settlement using RemoteAppChronicle
        IRemoteAppChronicle remoteChronicle = IRemoteAppChronicle(chronicle);
        for (uint256 i; i < keys.length; ++i) {
            bytes memory storedValue = remoteChronicle.getDataAt(keys[i], uint64(rootTimestamp));
            assertEq(keccak256(storedValue), keccak256(values[i]));
        }
        assertTrue(remoteChronicle.isDataSettled(uint64(rootTimestamp)));
    }

    function test_settleData_alreadySettled() public {
        // Setup settler
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup

        // Update remote data
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalData(keccak256("key"), abi.encode("value"));

        // Sync
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Get root timestamp
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedDataRoot(bytes32(uint256(eids[1])));

        // First settlement
        changePrank(settler, settler);
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("key");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("value");

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        IRemoteAppChronicle(chronicle).settleData(
            IRemoteAppChronicle.SettleDataParams(uint64(rootTimestamp), keys, values)
        );

        // Try to settle again
        vm.expectRevert(IRemoteAppChronicle.DataAlreadySettled.selector);
        IRemoteAppChronicle(chronicle).settleData(
            IRemoteAppChronicle.SettleDataParams(uint64(rootTimestamp), keys, values)
        );
    }

    function test_settleData_notWhitelisted() public {
        address notWhitelisted = makeAddr("notWhitelisted");
        changePrank(notWhitelisted, notWhitelisted);

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("key");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("value");

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        vm.expectRevert(IRemoteAppChronicle.Forbidden.selector);
        IRemoteAppChronicle(chronicle).settleData(
            IRemoteAppChronicle.SettleDataParams(uint64(block.timestamp), keys, values)
        );
    }

    function test_settleData_complexDataStructures() public {
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup

        // Create complex data structures on remote
        changePrank(apps[1], apps[1]);

        // Store different types of encoded data
        bytes32 configKey = keccak256("config");
        bytes32 pricesKey = keccak256("prices");
        bytes32 metadataKey = keccak256("metadata");

        // Config struct
        bytes memory configData = abi.encode(
            uint256(1e18), // fee
            uint256(86_400), // period
            address(0x1234567890123456789012345678901234567890), // treasury
            true // active
        );

        // Price array
        uint256[] memory prices = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            prices[i] = (i + 1) * 1000e18;
        }
        bytes memory pricesData = abi.encode(prices);

        // Metadata string
        bytes memory metadataData = abi.encode("Production deployment v2.1.0");

        liquidityMatrices[1].updateLocalData(configKey, configData);
        liquidityMatrices[1].updateLocalData(pricesKey, pricesData);
        liquidityMatrices[1].updateLocalData(metadataKey, metadataData);

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        bytes32 remoteEid = _eid(liquidityMatrices[1]);
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedDataRoot(remoteEid);

        // Settle data
        changePrank(settler, settler);
        bytes32[] memory keys = new bytes32[](3);
        keys[0] = configKey;
        keys[1] = pricesKey;
        keys[2] = metadataKey;

        bytes[] memory values = new bytes[](3);
        values[0] = configData;
        values[1] = pricesData;
        values[2] = metadataData;

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
        IRemoteAppChronicle(chronicle).settleData(
            IRemoteAppChronicle.SettleDataParams(uint64(rootTimestamp), keys, values)
        );

        // Verify all data through RemoteAppChronicle
        IRemoteAppChronicle remoteChronicle = IRemoteAppChronicle(chronicle);
        assertEq(keccak256(remoteChronicle.getDataAt(configKey, uint64(rootTimestamp))), keccak256(configData));
        assertEq(keccak256(remoteChronicle.getDataAt(pricesKey, uint64(rootTimestamp))), keccak256(pricesData));
        assertEq(keccak256(remoteChronicle.getDataAt(metadataKey, uint64(rootTimestamp))), keccak256(metadataData));
    }

    /*//////////////////////////////////////////////////////////////
                        onReceiveRoots() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onReceiveRoots_onlySynchronizer() public {
        address notSynchronizer = makeAddr("notSynchronizer");
        changePrank(notSynchronizer, notSynchronizer);

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].onReceiveRoots(
            bytes32(uint256(eids[1])), 1, bytes32(0), bytes32(0), uint64(block.timestamp)
        );
    }

    function test_onReceiveRoots_outOfOrderRoots() public {
        changePrank(address(gateways[0]), address(gateways[0]));

        bytes32 chainUID = bytes32(uint256(30_001));

        // Send roots with timestamps out of order (using version 1)
        liquidityMatrices[0].onReceiveRoots(chainUID, 1, keccak256("liquidity_root_1"), keccak256("data_root_1"), 1000);

        // Send earlier timestamp (should be ignored for latest)
        liquidityMatrices[0].onReceiveRoots(chainUID, 1, keccak256("liquidity_root_2"), keccak256("data_root_2"), 500);

        // Send later timestamp (should update latest)
        liquidityMatrices[0].onReceiveRoots(chainUID, 1, keccak256("liquidity_root_3"), keccak256("data_root_3"), 1500);

        // Verify latest roots
        (bytes32 latestLiqRoot, uint256 latestLiqTime) = liquidityMatrices[0].getLastReceivedLiquidityRoot(chainUID);
        (bytes32 latestDataRoot, uint256 latestDataTime) = liquidityMatrices[0].getLastReceivedDataRoot(chainUID);

        assertEq(latestLiqRoot, keccak256("liquidity_root_3"));
        assertEq(latestLiqTime, 1500);
        assertEq(latestDataRoot, keccak256("data_root_3"));
        assertEq(latestDataTime, 1500);

        // Verify historical roots are preserved
        assertEq(liquidityMatrices[0].getLiquidityRootAt(chainUID, 1000), keccak256("liquidity_root_1"));
        assertEq(liquidityMatrices[0].getLiquidityRootAt(chainUID, 500), keccak256("liquidity_root_2"));
    }

    /*//////////////////////////////////////////////////////////////
                onReceiveMapRemoteAccountRequests() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onReceiveMapRemoteAccountRequests_onlySynchronizer() public {
        address notSynchronizer = makeAddr("notSynchronizer");
        changePrank(notSynchronizer, notSynchronizer);

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], "");
    }

    function test_onReceiveMapRemoteAccountRequests_remoteAlreadyMapped() public {
        // App is already registered and remote app is already set up in setup()

        // Set up the app mock to allow mapping
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(bytes32(uint256(eids[1])))), users[0], users[1], true);
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(eids[1])), users[0], users[2], true);

        // Simulate receiving a map request from remote chain
        // First mapping succeeds
        changePrank(address(gateways[0]), address(gateways[0]));
        address[] memory remotes1 = new address[](1);
        address[] memory locals1 = new address[](1);
        remotes1[0] = users[0];
        locals1[0] = users[1];
        bytes memory message1 = abi.encode(remotes1, locals1);
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], message1);

        // Try to map same remote account to different local
        address[] memory remotes2 = new address[](1);
        address[] memory locals2 = new address[](1);
        remotes2[0] = users[0];
        locals2[0] = users[2];
        bytes memory message2 = abi.encode(remotes2, locals2);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidityMatrix.RemoteAccountAlreadyMapped.selector, bytes32(uint256(eids[1])), users[0]
            )
        );
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], message2);
    }

    function test_onReceiveMapRemoteAccountRequests_localAlreadyMapped() public {
        // App is already registered and remote app is already set up in setup()

        // Set up the app mock to allow mapping
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(bytes32(uint256(eids[1])))), users[0], users[1], true);
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(eids[1])), users[2], users[1], true);

        // Simulate receiving a map request from remote chain
        // First mapping succeeds
        changePrank(address(gateways[0]), address(gateways[0]));
        address[] memory remotes1 = new address[](1);
        address[] memory locals1 = new address[](1);
        remotes1[0] = users[0];
        locals1[0] = users[1];
        bytes memory message1 = abi.encode(remotes1, locals1);
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], message1);

        // Try to map different remote account to same local
        address[] memory remotes2 = new address[](1);
        address[] memory locals2 = new address[](1);
        remotes2[0] = users[2];
        locals2[0] = users[1];
        bytes memory message2 = abi.encode(remotes2, locals2);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidityMatrix.LocalAccountAlreadyMapped.selector, bytes32(uint256(eids[1])), users[1]
            )
        );
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], message2);
    }

    function test_onReceiveMapRemoteAccountRequests_bulkMapping() public {
        // Register app with callbacks
        address callbackApp = address(new AppMock(address(liquidityMatrices[0])));
        changePrank(callbackApp, callbackApp);
        liquidityMatrices[0].registerApp(false, true, settlers[0]);

        // Setup bulk mappings
        uint256 numMappings = 50;
        address[] memory remotes = new address[](numMappings);
        address[] memory locals = new address[](numMappings);

        for (uint256 i = 0; i < numMappings; i++) {
            remotes[i] = makeAddr(string(abi.encodePacked("remote", i)));
            locals[i] = makeAddr(string(abi.encodePacked("local", i)));

            // Set approval for half the mappings
            if (i % 2 == 0) {
                AppMock(callbackApp).setShouldMapAccounts(bytes32(uint256(eids[1])), remotes[i], locals[i], true);
            }
        }

        // Send bulk mapping request
        changePrank(address(gateways[0]), address(gateways[0]));
        bytes memory message = abi.encode(remotes, locals);

        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), callbackApp, message);

        // Verify only approved mappings were created
        for (uint256 i = 0; i < numMappings; i++) {
            if (i % 2 == 0) {
                assertEq(
                    liquidityMatrices[0].getMappedAccount(callbackApp, bytes32(uint256(eids[1])), remotes[i]), locals[i]
                );
                assertTrue(liquidityMatrices[0].isLocalAccountMapped(callbackApp, bytes32(uint256(eids[1])), locals[i]));
            } else {
                assertEq(
                    liquidityMatrices[0].getMappedAccount(callbackApp, bytes32(uint256(eids[1])), remotes[i]),
                    address(0)
                );
                assertFalse(
                    liquidityMatrices[0].isLocalAccountMapped(callbackApp, bytes32(uint256(eids[1])), locals[i])
                );
            }
        }
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
        liquidityMatrices[0].requestMapRemoteAccounts{ value: 1 ether }(
            bytes32(uint256(eids[1])), apps[1], locals, remotes, abi.encode(uint128(100_000), apps[0])
        );
    }

    function test_requestMapRemoteAccounts_invalidAddress() public {
        changePrank(apps[0], apps[0]);

        address[] memory remotes = new address[](1);
        address[] memory locals = new address[](1);
        locals[0] = address(0); // Invalid address

        vm.expectRevert(ILiquidityMatrix.InvalidAddress.selector);
        liquidityMatrices[0].requestMapRemoteAccounts{ value: 1 ether }(
            bytes32(uint256(eids[1])), apps[1], locals, remotes, abi.encode(uint128(100_000), apps[0])
        );
    }

    /*//////////////////////////////////////////////////////////////
              ADDITIONAL PRODUCTION SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_production_multiChainSettlement() public {
        // Simulate a production scenario with 3 chains
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup
        liquidityMatrices[1].updateSettlerWhitelisted(settler, true);

        // Create activity on all chains
        address[] memory traders = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            traders[i] = makeAddr(string(abi.encodePacked("trader", i)));
        }

        // Chain 0 activity
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateLocalLiquidity(traders[0], 1000e18);
        liquidityMatrices[0].updateLocalLiquidity(traders[1], -500e18);

        // Chain 1 activity
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(traders[0], 2000e18);
        liquidityMatrices[1].updateLocalLiquidity(traders[2], 1500e18);

        // Sync all roots
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Settlement on chain 0
        bytes32 chain1Eid = _eid(liquidityMatrices[1]);
        (, uint256 chain1Timestamp) = liquidityMatrices[0].getLastReceivedLiquidityRoot(chain1Eid);

        changePrank(settler, settler);
        address[] memory chain1Accounts = new address[](2);
        chain1Accounts[0] = traders[0];
        chain1Accounts[1] = traders[2];
        int256[] memory chain1Liquidity = new int256[](2);
        chain1Liquidity[0] = 2000e18;
        chain1Liquidity[1] = 1500e18;

        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chain1Eid);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(chain1Timestamp), chain1Accounts, chain1Liquidity)
        );

        // Verify cross-chain view - need to check both local and remote
        // trader[0]: local 1000e18 + remote 2000e18 = 3000e18
        assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], traders[0]), 1000e18);
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chain1Eid, traders[0], uint64(chain1Timestamp)), 2000e18);
        // trader[1]: local -500e18, no remote
        assertEq(liquidityMatrices[0].getLocalLiquidity(apps[0], traders[1]), -500e18);
        // trader[2]: local 0, remote 1500e18
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chain1Eid, traders[2], uint64(chain1Timestamp)), 1500e18);
    }

    function test_outOfOrderSettlement_comprehensiveChecks() public {
        // Test all getter functions after each settlement in random order
        address settler = settlers[0];
        changePrank(owner, owner);
        // Settler already configured during setup

        // Receive three sets of roots sequentially
        changePrank(address(gateways[0]), address(gateways[0]));

        // Root 1 at timestamp T1
        uint256 t1 = block.timestamp;
        bytes32 liqRoot1 = keccak256("liquidity_root_1");
        bytes32 dataRoot1 = keccak256("data_root_1");
        liquidityMatrices[0].onReceiveRoots(bytes32(uint256(eids[1])), 1, liqRoot1, dataRoot1, uint64(t1));

        // Root 2 at timestamp T2
        skip(100);
        uint256 t2 = block.timestamp;
        bytes32 liqRoot2 = keccak256("liquidity_root_2");
        bytes32 dataRoot2 = keccak256("data_root_2");
        liquidityMatrices[0].onReceiveRoots(bytes32(uint256(eids[1])), 1, liqRoot2, dataRoot2, uint64(t2));

        // Root 3 at timestamp T3
        skip(100);
        uint256 t3 = block.timestamp;
        bytes32 liqRoot3 = keccak256("liquidity_root_3");
        bytes32 dataRoot3 = keccak256("data_root_3");
        liquidityMatrices[0].onReceiveRoots(bytes32(uint256(eids[1])), 1, liqRoot3, dataRoot3, uint64(t3));

        // Initial state - nothing settled
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        IRemoteAppChronicle remoteChronicle = IRemoteAppChronicle(chronicle);
        assertFalse(remoteChronicle.isLiquiditySettled(uint64(t1)));
        assertFalse(remoteChronicle.isLiquiditySettled(uint64(t2)));
        assertFalse(remoteChronicle.isLiquiditySettled(uint64(t3)));
        assertFalse(remoteChronicle.isDataSettled(uint64(t1)));
        assertFalse(remoteChronicle.isDataSettled(uint64(t2)));
        assertFalse(remoteChronicle.isDataSettled(uint64(t3)));
        assertFalse(remoteChronicle.isFinalized(uint64(t1)));
        assertFalse(remoteChronicle.isFinalized(uint64(t2)));
        assertFalse(remoteChronicle.isFinalized(uint64(t3)));

        // Check getters return zero/empty
        (bytes32 root, uint256 timestamp) =
            liquidityMatrices[0].getLastSettledLiquidityRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);
        (root, timestamp) = liquidityMatrices[0].getLastSettledDataRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);
        (root, timestamp) = liquidityMatrices[0].getLastFinalizedLiquidityRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);
        (root, timestamp) = liquidityMatrices[0].getLastFinalizedDataRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);

        // Step 1: Settle liquidity for root2
        changePrank(settler, settler);
        address[] memory accounts = new address[](1);
        accounts[0] = users[0];
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 200e18;

        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(t2), accounts, liquidity)
        );

        // Check states after first settlement using RemoteAppChronicle
        assertFalse(remoteChronicle.isLiquiditySettled(uint64(t1)));
        assertTrue(remoteChronicle.isLiquiditySettled(uint64(t2)));
        assertFalse(remoteChronicle.isLiquiditySettled(uint64(t3)));
        assertFalse(remoteChronicle.isDataSettled(uint64(t1)));
        assertFalse(remoteChronicle.isDataSettled(uint64(t2)));
        assertFalse(remoteChronicle.isDataSettled(uint64(t3)));
        assertFalse(remoteChronicle.isFinalized(uint64(t1)));
        assertFalse(remoteChronicle.isFinalized(uint64(t2))); // Not finalized without data
        assertFalse(remoteChronicle.isFinalized(uint64(t3)));

        // Check getters using RemoteAppChronicle
        // Note: getLastSettledLiquidityRoot, getLastSettledDataRoot, getLastFinalizedLiquidityRoot were removed
        // Using RemoteAppChronicle methods instead
        uint64 lastSettledLiqTime = remoteChronicle.getLastSettledLiquidityTimestamp();
        assertEq(lastSettledLiqTime, t2);
        uint64 lastSettledDataTime = remoteChronicle.getLastSettledDataTimestamp();
        assertEq(lastSettledDataTime, 0); // No data settled yet
        uint64 lastFinalizedTime = remoteChronicle.getLastFinalizedTimestamp();
        assertEq(lastFinalizedTime, 0); // Nothing finalized yet

        // Step 2: Settle data for root3
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("key3");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("value3");

        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(uint64(t3), keys, values));

        // Check states after second settlement
        assertFalse(remoteChronicle.isLiquiditySettled(uint64(t1)));
        assertTrue(remoteChronicle.isLiquiditySettled(uint64(t2)));
        assertFalse(remoteChronicle.isLiquiditySettled(uint64(t3)));
        assertFalse(remoteChronicle.isDataSettled(uint64(t1)));
        assertFalse(remoteChronicle.isDataSettled(uint64(t2)));
        assertTrue(remoteChronicle.isDataSettled(uint64(t3)));
        assertFalse(remoteChronicle.isFinalized(uint64(t1)));
        assertFalse(remoteChronicle.isFinalized(uint64(t2)));
        assertFalse(remoteChronicle.isFinalized(uint64(t3))); // Not finalized without liquidity

        // Check getters using RemoteAppChronicle
        lastSettledLiqTime = remoteChronicle.getLastSettledLiquidityTimestamp();
        assertEq(lastSettledLiqTime, t2);
        lastSettledDataTime = remoteChronicle.getLastSettledDataTimestamp();
        assertEq(lastSettledDataTime, t3);
        lastFinalizedTime = remoteChronicle.getLastFinalizedTimestamp();
        assertEq(lastFinalizedTime, 0); // Still not finalized

        // Step 3: Settle liquidity for root1
        liquidity[0] = 100e18;
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(t1), accounts, liquidity)
        );

        // Check states
        assertTrue(remoteChronicle.isLiquiditySettled(uint64(t1)));
        assertTrue(remoteChronicle.isLiquiditySettled(uint64(t2)));
        assertFalse(remoteChronicle.isLiquiditySettled(uint64(t3)));

        // Last settled should still be t2 (not t1 because t1 < t2)
        (root, timestamp) = liquidityMatrices[0].getLastSettledLiquidityRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, liqRoot2);
        assertEq(timestamp, t2);

        // Still no finalized roots (t1 has no data, t2 has no data, t3 has data but no liquidity)
        (root, timestamp) = liquidityMatrices[0].getLastFinalizedLiquidityRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);

        // Step 4: Settle data for root2
        keys[0] = keccak256("key2");
        values[0] = abi.encode("value2");
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(uint64(t2), keys, values));

        // Now root2 should be finalized (both liquidity and data settled for t2)
        assertFalse(remoteChronicle.isFinalized(uint64(t1))); // Missing data
        assertTrue(remoteChronicle.isFinalized(uint64(t2))); // Both settled
        assertFalse(remoteChronicle.isFinalized(uint64(t3))); // Missing liquidity

        // Due to the current implementation, finalization only updates when settling
        // a timestamp that is greater than the last settled timestamp.
        // Since we settled data for t3 before t2, the finalization check is skipped.
        // This is a limitation of the current design.
        (root, timestamp) = liquidityMatrices[0].getLastFinalizedLiquidityRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);
        (root, timestamp) = liquidityMatrices[0].getLastFinalizedDataRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);

        // Step 5: Settle liquidity for root3
        liquidity[0] = 300e18;
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(uint64(t3), accounts, liquidity)
        );

        // Now root3 should be finalized and be the latest
        assertTrue(remoteChronicle.isFinalized(uint64(t3)));

        // Check getters - last settled/finalized should be t3
        (root, timestamp) = liquidityMatrices[0].getLastSettledLiquidityRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, liqRoot3);
        assertEq(timestamp, t3);
        (root, timestamp) = liquidityMatrices[0].getLastFinalizedLiquidityRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, liqRoot3);
        assertEq(timestamp, t3);

        // Step 6: Settle data for root1 (complete all settlements)
        keys[0] = keccak256("key1");
        values[0] = abi.encode("value1");
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])));
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(uint64(t1), keys, values));

        // All should be finalized now
        assertTrue(remoteChronicle.isFinalized(uint64(t1)));
        assertTrue(remoteChronicle.isFinalized(uint64(t2)));
        assertTrue(remoteChronicle.isFinalized(uint64(t3)));

        // Last settled data should still be t3 (not t1)
        (root, timestamp) = liquidityMatrices[0].getLastSettledDataRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, dataRoot3);
        assertEq(timestamp, t3);

        // Last finalized should still be t3
        (root, timestamp) = liquidityMatrices[0].getLastFinalizedLiquidityRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, liqRoot3);
        assertEq(timestamp, t3);
        (root, timestamp) = liquidityMatrices[0].getLastFinalizedDataRoot(apps[0], bytes32(uint256(eids[1])));
        assertEq(root, dataRoot3);
        assertEq(timestamp, t3);

        // Verify roots at specific timestamps
        assertEq(liquidityMatrices[0].getLiquidityRootAt(bytes32(uint256(eids[1])), uint64(t1)), liqRoot1);
        assertEq(liquidityMatrices[0].getLiquidityRootAt(bytes32(uint256(eids[1])), uint64(t2)), liqRoot2);
        assertEq(liquidityMatrices[0].getLiquidityRootAt(bytes32(uint256(eids[1])), uint64(t3)), liqRoot3);
        assertEq(liquidityMatrices[0].getDataRootAt(bytes32(uint256(eids[1])), uint64(t1)), dataRoot1);
        assertEq(liquidityMatrices[0].getDataRootAt(bytes32(uint256(eids[1])), uint64(t2)), dataRoot2);
        assertEq(liquidityMatrices[0].getDataRootAt(bytes32(uint256(eids[1])), uint64(t3)), dataRoot3);
    }

    /*//////////////////////////////////////////////////////////////
                        REORG PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addReorg_basic() public {
        uint64 reorgTimestamp = uint64(block.timestamp + 1000);

        // Initially version should be 1
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp - 1), 1);
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp), 1);
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp + 1), 1);

        // Add a reorg (need to use a whitelisted settler)
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(reorgTimestamp);

        // After reorg, timestamps before should be version 1, after should be version 2
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp - 1), 1);
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp), 2);
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp + 1), 2);
    }

    function test_addReorg_multipleReorgs() public {
        uint64 reorg1 = uint64(block.timestamp + 1000);
        uint64 reorg2 = reorg1 + 1000;
        uint64 reorg3 = reorg2 + 1000;

        changePrank(settlers[0], settlers[0]);

        // Add multiple reorgs
        liquidityMatrices[0].addReorg(reorg1);
        liquidityMatrices[0].addReorg(reorg2);
        liquidityMatrices[0].addReorg(reorg3);

        // Check versions at different timestamps
        assertEq(liquidityMatrices[0].getVersion(reorg1 - 1), 1);
        assertEq(liquidityMatrices[0].getVersion(reorg1), 2);
        assertEq(liquidityMatrices[0].getVersion(reorg1 + 1), 2);
        assertEq(liquidityMatrices[0].getVersion(reorg2 - 1), 2);
        assertEq(liquidityMatrices[0].getVersion(reorg2), 3);
        assertEq(liquidityMatrices[0].getVersion(reorg2 + 1), 3);
        assertEq(liquidityMatrices[0].getVersion(reorg3 - 1), 3);
        assertEq(liquidityMatrices[0].getVersion(reorg3), 4);
        assertEq(liquidityMatrices[0].getVersion(reorg3 + 1), 4);
    }

    function test_addReorg_revertNonOwner() public {
        uint64 reorgTimestamp = uint64(block.timestamp);

        changePrank(alice, alice);
        vm.expectRevert();
        liquidityMatrices[0].addReorg(reorgTimestamp);
    }

    function test_addReorg_revertInvalidTimestamp() public {
        changePrank(settlers[0], settlers[0]);

        // Add a reorg at timestamp 1000
        liquidityMatrices[0].addReorg(1000);

        // Try to add a reorg at an earlier timestamp (should revert)
        vm.expectRevert(ILiquidityMatrix.InvalidTimestamp.selector);
        liquidityMatrices[0].addReorg(999);

        // Try to add a reorg at the same timestamp (should revert)
        vm.expectRevert(ILiquidityMatrix.InvalidTimestamp.selector);
        liquidityMatrices[0].addReorg(1000);
    }

    function test_getVersion_noReorgs() public view {
        // Without any reorgs, all timestamps should return version 1
        assertEq(liquidityMatrices[0].getVersion(0), 1);
        assertEq(liquidityMatrices[0].getVersion(1000), 1);
        assertEq(liquidityMatrices[0].getVersion(type(uint64).max), 1);
    }

    function testFuzz_getVersion(uint64 timestamp) public {
        changePrank(settlers[0], settlers[0]);

        // Add some reorgs at known timestamps (after initial version)
        uint64[] memory reorgTimestamps = new uint64[](5);
        reorgTimestamps[0] = uint64(block.timestamp + 1000);
        reorgTimestamps[1] = uint64(block.timestamp + 2000);
        reorgTimestamps[2] = uint64(block.timestamp + 3000);
        reorgTimestamps[3] = uint64(block.timestamp + 4000);
        reorgTimestamps[4] = uint64(block.timestamp + 5000);

        for (uint256 i = 0; i < reorgTimestamps.length; i++) {
            liquidityMatrices[0].addReorg(reorgTimestamps[i]);
        }

        uint256 version = liquidityMatrices[0].getVersion(timestamp);

        // Verify version is correct based on timestamp
        if (timestamp < reorgTimestamps[0]) {
            assertEq(version, 1);
        } else if (timestamp < reorgTimestamps[1]) {
            assertEq(version, 2);
        } else if (timestamp < reorgTimestamps[2]) {
            assertEq(version, 3);
        } else if (timestamp < reorgTimestamps[3]) {
            assertEq(version, 4);
        } else if (timestamp < reorgTimestamps[4]) {
            assertEq(version, 5);
        } else {
            assertEq(version, 6);
        }
    }

    function test_settleLiquidity_withVersion() public {
        changePrank(apps[0], apps[0]);

        // Update local liquidity before reorg
        liquidityMatrices[0].updateLocalLiquidity(alice, 100e18);

        // Settle for version 1
        changePrank(settlers[0], settlers[0]);
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 50e18;

        uint64 timestamp1 = uint64(block.timestamp);
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(timestamp1, accounts, liquidity)
        );

        // Verify settlement for version 1
        assertEq(IRemoteAppChronicle(chronicle).getLiquidityAt(alice, timestamp1), 50e18);

        // Add a reorg
        skip(100);
        uint64 reorgTimestamp = uint64(block.timestamp);
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(reorgTimestamp);

        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Settle for version 2 (after reorg)
        skip(100);
        uint64 timestamp2 = uint64(block.timestamp);
        liquidity[0] = 75e18;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(timestamp2, accounts, liquidity)
        );

        // Verify version 2 data (version 1 data not accessible from v2)
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, timestamp1), 0); // Before v2
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, timestamp2), 75e18); // V2 data
    }

    function test_settleData_withVersion() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        bytes32 key = keccak256("test_key");
        bytes memory value1 = abi.encode("value_v1");
        bytes memory value2 = abi.encode("value_v2");

        // Settle data for version 1
        uint64 timestamp1 = uint64(block.timestamp);
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = key;
        bytes[] memory values = new bytes[](1);
        values[0] = value1;

        changePrank(settlers[0], settlers[0]);
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(timestamp1, keys, values));

        // Add a reorg
        skip(100);
        uint64 reorgTimestamp = uint64(block.timestamp);
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(reorgTimestamp);

        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Settle different data for version 2
        skip(100);
        uint64 timestamp2 = uint64(block.timestamp);
        values[0] = value2;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(timestamp2, keys, values));

        // Verify version 2 data (version 1 data not accessible from v2)
        assertEq(keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, key, timestamp1)), keccak256("")); // Empty in v2
        assertEq(keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, key, timestamp2)), keccak256(value2)); // V2 data
    }

    function test_integration_reorgWithActiveSettlements() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address chronicle;

        // Setup: Settle liquidity at multiple timestamps for version 1
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        int256[] memory liquidity = new int256[](2);

        changePrank(settlers[0], settlers[0]);

        // Settlement 1 at t=1000
        vm.warp(1000);
        liquidity[0] = 100e18;
        liquidity[1] = 200e18;
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1000, accounts, liquidity)
        );

        // Settlement 2 at t=2000
        vm.warp(2000);
        liquidity[0] = 150e18;
        liquidity[1] = 250e18;
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(2000, accounts, liquidity)
        );

        // Reorg happens at t=1500 (between the two settlements)
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1500);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // New settlements for version 2
        changePrank(settlers[0], settlers[0]);

        // Settlement for version 2 at t=1600
        vm.warp(1600);
        liquidity[0] = 120e18;
        liquidity[1] = 220e18;
        // Settlement after reorg - version handled by chronicle
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1600, accounts, liquidity)
        );

        // Verify: Query at different timestamps returns correct version data
        // Before reorg (t=1400): in version 2 context, no data yet
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1400), 0);
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, bob, 1400), 0);

        // After reorg (t=1550): version 2 is active but has no data yet, returns 0
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1550), 0);
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, bob, 1550), 0);

        // After version 2 settlement (t=1700): should use version 2 data
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1700), 120e18);
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, bob, 1700), 220e18);
    }

    function test_integration_multipleReorgsWithSettlements() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address chronicle;
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);

        // Version 1: Settlement at t=1000
        vm.warp(1000);
        liquidity[0] = 100e18;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1000, accounts, liquidity)
        );

        // First reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1500);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Version 2: Settlement at t=2000
        vm.warp(2000);
        liquidity[0] = 200e18;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(2000, accounts, liquidity)
        );

        // Second reorg at t=2500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(2500);
        // Create RemoteAppChronicle for version 3
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 3);

        // Version 3: Settlement at t=3000
        vm.warp(3000);
        liquidity[0] = 300e18;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(3000, accounts, liquidity)
        );

        // Third reorg at t=3500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(3500);
        // Create RemoteAppChronicle for version 4
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 4);

        // Version 4: Settlement at t=4000
        vm.warp(4000);
        liquidity[0] = 400e18;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(4000, accounts, liquidity)
        );

        // Verify current version's data (version 4 after last reorg)
        // All previous version data is not accessible from version 4
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1200), 0); // Before v4 data
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 2200), 0); // Before v4 data
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 3200), 0); // Before v4 data
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 4200), 400e18); // Version 4 data
    }

    function test_edgeCase_manyReorgs() public {
        changePrank(settlers[0], settlers[0]);

        // Add many reorgs to test scalability
        uint256 numReorgs = 1000;
        for (uint256 i = 1; i <= numReorgs; i++) {
            liquidityMatrices[0].addReorg(uint64(block.timestamp + i * 100));
        }

        // Verify version calculation is still efficient
        uint256 gasStart = gasleft();
        uint256 version = liquidityMatrices[0].getVersion(50_000);
        uint256 gasUsed = gasStart - gasleft();

        // Reorgs at block.timestamp + 100, block.timestamp + 200, ..., block.timestamp + 100000
        // block.timestamp starts at 1, so reorgs are at 101, 201, ..., 100001
        // At timestamp 50000, reorgs <= 50000 are: 101, 201, ..., 49901 (i=1 to i=499)
        // That's 499 reorgs, so version = 1 + 499 = 500
        assertEq(version, 500);
        assertLt(gasUsed, 150_000); // Should use reasonable gas even with many reorgs
    }

    function test_edgeCase_settlementAtReorgTimestamp() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address chronicle;
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 100e18;

        // Add reorg at t=1000
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1000);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Try to settle exactly at reorg timestamp for version 2
        vm.warp(1000);
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1000, accounts, liquidity)
        );

        // Verify settlement worked and is associated with version 2
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1000), 100e18);
        assertEq(liquidityMatrices[0].getVersion(1000), 2);
    }

    function test_edgeCase_queryBeforeAnySettlement() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));

        // Add a reorg
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1000);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Query at various timestamps without any settlements
        // getSettledRemoteLiquidity removed - no settlements means no chronicle yet
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 500), 0);
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1500), 0);
        // getSettledRemoteTotalLiquidity removed - no remote total when no settlements
        assertEq(liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, 2000), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    COMPREHENSIVE REORG GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_reorg_allLiquidityGetters() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address chronicle;
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        int256[] memory liquidity = new int256[](2);

        // Setup local liquidity
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateLocalLiquidity(alice, 50e18);
        liquidityMatrices[0].updateLocalLiquidity(bob, 75e18);

        // Phase 1: Before reorg - settle liquidity at t=1000
        vm.warp(1000);
        liquidity[0] = 100e18;
        liquidity[1] = 200e18;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1000, accounts, liquidity)
        );

        // Also settle data for finalization tests
        bytes32[] memory keys = new bytes32[](2);
        keys[0] = keccak256("key1");
        keys[1] = keccak256("key2");
        bytes[] memory values = new bytes[](2);
        values[0] = abi.encode("data1");
        values[1] = abi.encode("data2");
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(1000, keys, values));

        // Test all getters BEFORE reorg (at t=1100)
        vm.warp(1100);

        // Remote liquidity getters
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1100), 100e18, "Remote liquidity at 1100"
        );
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, bob, 1100), 200e18, "Remote liquidity bob at 1100"
        );
        // Verify using RemoteAppChronicle method
        assertEq(IRemoteAppChronicle(chronicle).getLiquidityAt(alice, 1000), 100e18, "Settled remote liquidity");
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1000), 100e18, "Finalized remote liquidity"
        );

        // Remote total liquidity getters
        assertEq(liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, 1100), 300e18, "Remote total at 1100");
        // getSettledRemoteTotalLiquidity removed - use getTotalLiquidityAt
        assertEq(liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, 1000), 300e18, "Settled remote total");
        assertEq(
            liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, uint64(block.timestamp)),
            300e18,
            "Finalized remote total"
        );

        // Aggregated liquidity getters (local + remote)
        assertEq(liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, 1100), 150e18, "Total liquidity at 1100"); // 50 local + 100 remote
        // getSettledLiquidity removed - using aggregated at timestamp
        assertEq(
            liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, uint64(block.timestamp)),
            150e18,
            "Settled total liquidity"
        );
        // getFinalizedLiquidity removed - using aggregated at timestamp
        assertEq(
            liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, uint64(block.timestamp)),
            150e18,
            "Finalized total liquidity"
        );

        // Aggregated total liquidity getters
        assertEq(liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], 1100), 425e18, "Total at 1100"); // 125 local + 300 remote
        assertEq(
            liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], uint64(block.timestamp)),
            425e18,
            "Settled total"
        );
        assertEq(
            liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], uint64(block.timestamp)),
            425e18,
            "Finalized total"
        );

        // Phase 2: Add reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1500);
        // Create LocalAppChronicle for version 2
        liquidityMatrices[0].addLocalAppChronicle(apps[0], 2);
        // Create RemoteAppChronicles for version 2 (need for all remote chains)
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], bytes32(uint256(eids[2])), 2);

        // Test all getters RIGHT AFTER reorg (at t=1600, no new settlements yet)
        vm.warp(1600);

        // All remote getters should return 0 for version 2
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1600),
            0,
            "Remote liquidity at 1600 after reorg"
        );
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, bob, 1600),
            0,
            "Remote liquidity bob at 1600 after reorg"
        );
        // After reorg, get the new chronicle for version 2
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        assertEq(IRemoteAppChronicle(chronicle).getLastSettledLiquidityTimestamp(), 0, "Settled remote after reorg");
        assertEq(liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1500), 0, "Finalized remote after reorg");

        assertEq(
            liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, 1600), 0, "Remote total at 1600 after reorg"
        );
        // getSettledRemoteTotalLiquidity removed - check chronicle state
        assertEq(IRemoteAppChronicle(chronicle).getTotalLiquidityAt(1600), 0, "Settled remote total after reorg");
        assertEq(
            liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, uint64(block.timestamp)),
            0,
            "Finalized remote total after reorg"
        );

        // Aggregated getters in v2 show 0 (v2 LocalAppChronicle has no data)
        assertEq(
            liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, 1600),
            0,
            "Total liquidity at 1600 after reorg"
        ); // v2 has no data
        // getSettledLiquidity removed - using aggregated at timestamp
        assertEq(
            liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, uint64(block.timestamp)),
            0,
            "Settled total after reorg"
        );
        // getFinalizedLiquidity removed - using aggregated at timestamp
        assertEq(
            liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, uint64(block.timestamp)),
            0,
            "Finalized total after reorg"
        );

        assertEq(liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], 1600), 0, "Total at 1600 after reorg"); // v2 has no data
        assertEq(
            liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], uint64(block.timestamp)),
            0,
            "Settled total after reorg"
        );
        assertEq(
            liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], uint64(block.timestamp)),
            0,
            "Finalized total after reorg"
        );

        // Queries before reorg timestamp in version 2 return 0 (no data in v2 yet)
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1400),
            0,
            "Remote liquidity at 1400 (before reorg, but in v2)"
        );

        // Phase 3: Settle new data for version 2 at t=1700
        vm.warp(1700);
        liquidity[0] = 150e18;
        liquidity[1] = 250e18;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1700, accounts, liquidity)
        );

        // Settle data for finalization
        values[0] = abi.encode("data1_v2");
        values[1] = abi.encode("data2_v2");
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(1700, keys, values));

        // Test all getters AFTER new settlement (at t=1800)
        vm.warp(1800);

        // Remote liquidity getters should now return new values
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1800),
            150e18,
            "Remote liquidity at 1800 after settlement"
        );
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, bob, 1800), 250e18, "Remote liquidity bob at 1800"
        );
        // getSettledRemoteLiquidity removed - use chronicle method
        assertEq(IRemoteAppChronicle(chronicle).getLiquidityAt(alice, 1700), 150e18, "Settled remote after settlement");
        assertEq(
            liquidityMatrices[0].getLiquidityAt(apps[0], chainUID, alice, 1700),
            150e18,
            "Finalized remote after settlement"
        );

        assertEq(liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, 1800), 400e18, "Remote total at 1800");
        // getSettledRemoteTotalLiquidity removed - use getTotalLiquidityAt
        assertEq(
            liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, 1700),
            400e18,
            "Settled remote total after settlement"
        );
        assertEq(
            liquidityMatrices[0].getTotalLiquidityAt(apps[0], chainUID, uint64(block.timestamp)),
            400e18,
            "Finalized remote total after settlement"
        );

        // Aggregated getters should show only remote (v2 local has no data)
        assertEq(liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, 1800), 150e18, "Total liquidity at 1800"); // 0 local + 150 remote (v2 has no local data)
        // getSettledLiquidity removed - using aggregated at timestamp
        assertEq(
            liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, uint64(block.timestamp)),
            150e18,
            "Settled total after settlement"
        );
        // getFinalizedLiquidity removed - using aggregated at timestamp
        assertEq(
            liquidityMatrices[0].getAggregatedLiquidityAt(apps[0], alice, uint64(block.timestamp)),
            150e18,
            "Finalized total after settlement"
        );

        assertEq(liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], 1800), 400e18, "Total at 1800"); // 0 local + 400 remote (v2 has no local data)
        assertEq(
            liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], uint64(block.timestamp)),
            400e18,
            "Settled total after settlement"
        );
        assertEq(
            liquidityMatrices[0].getAggregatedTotalLiquidityAt(apps[0], uint64(block.timestamp)),
            400e18,
            "Finalized total after settlement"
        );
    }

    function test_reorg_allDataGetters() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address chronicle;
        bytes32[] memory keys = new bytes32[](3);
        keys[0] = keccak256("alpha");
        keys[1] = keccak256("beta");
        keys[2] = keccak256("gamma");
        bytes[] memory values = new bytes[](3);

        // Phase 1: Before reorg - settle data at t=1000
        vm.warp(1000);
        values[0] = abi.encode("value1", uint256(100));
        values[1] = abi.encode("value2", uint256(200));
        values[2] = abi.encode("value3", uint256(300));

        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(1000, keys, values));

        // Test data getters BEFORE reorg (at t=1100)
        vm.warp(1100);

        // Remote data hash getters
        assertEq(
            keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[0], 1100)),
            keccak256(values[0]),
            "Remote data hash at 1100"
        );
        assertEq(
            keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[0], 1000)),
            keccak256(values[0]),
            "Settled remote data hash"
        );

        // For finalized, we need liquidity settled too
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 100e18;
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1000, accounts, liquidity)
        );

        assertEq(
            keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[0], 1000)),
            keccak256(values[0]),
            "Finalized remote data hash"
        );

        // Check all keys
        for (uint256 i = 0; i < keys.length; i++) {
            assertEq(
                keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[i], 1100)),
                keccak256(values[i]),
                string.concat("Key ", vm.toString(i), " before reorg")
            );
        }

        // Phase 2: Add reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1500);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Test data getters RIGHT AFTER reorg (at t=1600, no new settlements)
        vm.warp(1600);

        // All data getters should return empty for version 2
        for (uint256 i = 0; i < keys.length; i++) {
            assertEq(
                keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[i], 1600)),
                keccak256(""),
                string.concat("Key ", vm.toString(i), " after reorg should be empty")
            );
        }

        assertEq(
            keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[0], 1500)),
            keccak256(""),
            "Settled after reorg"
        );
        assertEq(
            keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[0], uint64(block.timestamp))),
            keccak256(""),
            "Finalized after reorg"
        );

        // Queries before reorg timestamp in version 2 return empty
        assertEq(
            keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[0], 1400)),
            keccak256(""),
            "Data at 1400 (before reorg, but in v2)"
        );

        // Phase 3: Settle new data for version 2 at t=1700
        vm.warp(1700);
        values[0] = abi.encode("value1_v2", uint256(1000));
        values[1] = abi.encode("value2_v2", uint256(2000));
        values[2] = abi.encode("value3_v2", uint256(3000));

        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(1700, keys, values));

        // Also settle liquidity for finalization
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1700, accounts, liquidity)
        );

        // Test data getters AFTER new settlement (at t=1800)
        vm.warp(1800);

        // All data getters should return new values
        for (uint256 i = 0; i < keys.length; i++) {
            assertEq(
                keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[i], 1800)),
                keccak256(values[i]),
                string.concat("Key ", vm.toString(i), " after new settlement")
            );
        }

        assertEq(
            keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[0], 1700)),
            keccak256(values[0]),
            "Settled after new settlement"
        );
        assertEq(
            keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, keys[0], uint64(block.timestamp))),
            keccak256(values[0]),
            "Finalized after new settlement"
        );
    }

    function test_reorg_rootGetters() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address chronicle;

        // Setup and sync to get initial roots
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(alice, 100e18);
        bytes32 key = keccak256("testKey");
        bytes memory value = abi.encode("testValue");
        liquidityMatrices[1].updateLocalData(key, value);

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];

        vm.warp(1000);
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Get roots before reorg
        (bytes32 liquidityRootBefore, uint64 liquidityTimestampBefore) =
            liquidityMatrices[0].getLastReceivedLiquidityRoot(chainUID);
        (bytes32 dataRootBefore, uint64 dataTimestampBefore) = liquidityMatrices[0].getLastReceivedDataRoot(chainUID);

        assertTrue(liquidityRootBefore != bytes32(0), "Liquidity root should exist before reorg");
        assertTrue(dataRootBefore != bytes32(0), "Data root should exist before reorg");
        // Note: sync adds 1 to the timestamp internally
        assertEq(liquidityTimestampBefore, 1001, "Liquidity timestamp before reorg");
        assertEq(dataTimestampBefore, 1001, "Data timestamp before reorg");

        // Settle the roots
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 100e18;

        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1001, accounts, liquidity)
        );

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = key;
        bytes[] memory values = new bytes[](1);
        values[0] = value;
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(1001, keys, values));

        // Check settled and finalized roots before reorg
        (bytes32 settledLiqRoot, uint64 settledLiqTime) =
            liquidityMatrices[0].getLastSettledLiquidityRoot(apps[0], chainUID);
        (bytes32 finalizedLiqRoot, uint64 finalizedLiqTime) =
            liquidityMatrices[0].getLastFinalizedLiquidityRoot(apps[0], chainUID);

        assertEq(settledLiqRoot, liquidityRootBefore, "Settled liquidity root before reorg");
        assertEq(finalizedLiqRoot, liquidityRootBefore, "Finalized liquidity root before reorg");
        assertEq(settledLiqTime, 1001, "Settled time before reorg");
        assertEq(finalizedLiqTime, 1001, "Finalized time before reorg");

        // Add reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1500);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // After reorg, settled/finalized roots should be empty for current version
        (settledLiqRoot, settledLiqTime) = liquidityMatrices[0].getLastSettledLiquidityRoot(apps[0], chainUID);
        (finalizedLiqRoot, finalizedLiqTime) = liquidityMatrices[0].getLastFinalizedLiquidityRoot(apps[0], chainUID);

        assertEq(settledLiqRoot, bytes32(0), "Settled liquidity root after reorg");
        assertEq(finalizedLiqRoot, bytes32(0), "Finalized liquidity root after reorg");
        assertEq(settledLiqTime, 0, "Settled time after reorg");
        assertEq(finalizedLiqTime, 0, "Finalized time after reorg");

        // Historical queries still return synced roots (sync persists across reorgs)
        assertEq(
            liquidityMatrices[0].getLiquidityRootAt(chainUID, 1001),
            liquidityRootBefore,
            "Historical liquidity root at t=1001 (synced root persists)"
        );
        assertEq(
            liquidityMatrices[0].getDataRootAt(chainUID, 1001),
            dataRootBefore,
            "Historical data root at t=1001 (synced root persists)"
        );

        // After a reorg, this test doesn't need to sync new data or settle
        // The test was verifying that historical root queries work correctly across reorgs
        // which we've already verified above
    }

    function test_reorg_settlementStatusGetters() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address chronicle;

        // Setup initial settlement
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 100e18;

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("key");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("value");

        // Settle at t=1000 for version 1
        vm.warp(1000);
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1000, accounts, liquidity)
        );
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(1000, keys, values));

        // Check settlement status before reorg
        IRemoteAppChronicle remoteChronicle = IRemoteAppChronicle(chronicle);
        assertTrue(remoteChronicle.isLiquiditySettled(1000), "Liquidity settled at 1000");
        assertTrue(remoteChronicle.isDataSettled(1000), "Data settled at 1000");
        assertTrue(remoteChronicle.isFinalized(1000), "Finalized at 1000");

        // Add reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1500);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Check settlement status after reorg
        // Version 1 chronicle still has its data
        assertTrue(remoteChronicle.isLiquiditySettled(1000), "V1 chronicle: Liquidity still settled at 1000");
        assertTrue(remoteChronicle.isDataSettled(1000), "V1 chronicle: Data still settled at 1000");
        assertTrue(remoteChronicle.isFinalized(1000), "V1 chronicle: Still finalized at 1000");

        // Get new chronicle for version 2
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        remoteChronicle = IRemoteAppChronicle(chronicle);

        // Version 2 chronicle has no data yet
        assertFalse(remoteChronicle.isLiquiditySettled(1600), "V2 chronicle: Liquidity not settled at 1600");
        assertFalse(remoteChronicle.isDataSettled(1600), "V2 chronicle: Data not settled at 1600");
        assertFalse(remoteChronicle.isFinalized(1600), "V2 chronicle: Not finalized at 1600");

        // Settle only liquidity for version 2 at t=1700
        vm.warp(1700);
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1700, accounts, liquidity)
        );

        // Check partial settlement (liquidity but not data)
        assertTrue(remoteChronicle.isLiquiditySettled(1700), "Liquidity settled at 1700");
        assertFalse(remoteChronicle.isDataSettled(1700), "Data not settled at 1700");
        assertFalse(remoteChronicle.isFinalized(1700), "Not finalized without data");

        // Now settle data
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(1700, keys, values));

        // Check full settlement
        assertTrue(remoteChronicle.isLiquiditySettled(1700), "Liquidity settled at 1700");
        assertTrue(remoteChronicle.isDataSettled(1700), "Data settled at 1700");
        assertTrue(remoteChronicle.isFinalized(1700), "Finalized at 1700");
    }

    function test_edgeCase_finalizationAcrossReorg() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address chronicle;

        // Simulate receiving roots for version 1 (need to call as the contract itself)
        vm.warp(1000);
        vm.stopPrank(); // Stop any existing prank
        vm.prank(address(liquidityMatrices[0]));
        liquidityMatrices[0].onReceiveRoots(
            chainUID, 1, keccak256("liquidity_root_v1"), keccak256("data_root_v1"), 1000
        );

        // Settle liquidity for version 1
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 100e18;

        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(1000, accounts, liquidity)
        );

        // Also settle data for version 1 to achieve finalization
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("test_key");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("test_value");
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(1000, keys, values));

        // Check finalization for version 1 (both liquidity and data are settled)
        IRemoteAppChronicle remoteChronicle = IRemoteAppChronicle(chronicle);
        assertTrue(remoteChronicle.isFinalized(1000));

        // Add reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addReorg(1500);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // After reorg, timestamp 1600 should not be finalized (different version)
        assertFalse(remoteChronicle.isFinalized(1600));

        // Receive new roots for version 2
        vm.warp(2000);
        vm.stopPrank(); // Stop the owner prank first
        vm.prank(address(liquidityMatrices[0]));
        liquidityMatrices[0].onReceiveRoots(
            chainUID, 1, keccak256("liquidity_root_v2"), keccak256("data_root_v2"), 2000
        );

        // Settle liquidity and data for version 2
        liquidity[0] = 200e18;
        changePrank(settlers[0], settlers[0]);
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleLiquidity(
            IRemoteAppChronicle.SettleLiquidityParams(2000, accounts, liquidity)
        );
        values[0] = abi.encode("test_value_v2");
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle(chronicle).settleData(IRemoteAppChronicle.SettleDataParams(2000, keys, values));

        // Check finalization for version 2
        remoteChronicle = IRemoteAppChronicle(chronicle);
        assertTrue(remoteChronicle.isFinalized(2000));

        // Version 1 finalization should NOT be valid in version 2 chronicle
        assertFalse(remoteChronicle.isFinalized(1000));
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Override _eid functions to handle array-based structure
    function _eid(ILiquidityMatrix liquidityMatrix) internal view override returns (bytes32) {
        for (uint32 i = 0; i < CHAINS; ++i) {
            if (address(liquidityMatrix) == address(liquidityMatrices[i])) {
                return bytes32(uint256(eids[i]));
            }
        }
        revert("Unknown LiquidityMatrix");
    }

    function _eid(address addr) internal view override returns (bytes32) {
        // For gateway addresses, check which endpoint they're associated with
        for (uint32 i = 0; i < CHAINS; ++i) {
            if (address(liquidityMatrices[i]) != address(0) && addr == address(gateways[i])) {
                return bytes32(uint256(eids[i]));
            }
        }
        revert("Unknown address");
    }
}
