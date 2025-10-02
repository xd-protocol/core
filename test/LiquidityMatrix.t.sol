// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { LocalAppChronicleDeployer } from "src/chronicles/LocalAppChronicleDeployer.sol";
import { RemoteAppChronicleDeployer } from "src/chronicles/RemoteAppChronicleDeployer.sol";
import { RemoteAppChronicle } from "src/chronicles/RemoteAppChronicle.sol";
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

        // Deploy deployers for each chain (they need the LiquidityMatrix address)
        LocalAppChronicleDeployer[] memory localDeployers = new LocalAppChronicleDeployer[](CHAINS);
        RemoteAppChronicleDeployer[] memory remoteDeployers = new RemoteAppChronicleDeployer[](CHAINS);

        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            syncers[i] = makeAddr(string.concat("syncer", vm.toString(i)));

            // Create a dummy LiquidityMatrix first to get the address
            LiquidityMatrix tempMatrix = new LiquidityMatrix(owner, 1, address(0), address(0));

            // Create deployers with the LiquidityMatrix address
            localDeployers[i] = new LocalAppChronicleDeployer(address(tempMatrix));
            remoteDeployers[i] = new RemoteAppChronicleDeployer(address(tempMatrix));

            // Update the LiquidityMatrix with the correct deployer addresses
            tempMatrix.updateLocalAppChronicleDeployer(address(localDeployers[i]));
            tempMatrix.updateRemoteAppChronicleDeployer(address(remoteDeployers[i]));

            liquidityMatrices[i] = tempMatrix;

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

            vm.label(address(liquidityMatrices[i]), string.concat("LiquidityMatrix", vm.toString(i)));
            vm.label(address(gateways[i]), string.concat("Gateway", vm.toString(i)));
            vm.label(address(settlers[i]), string.concat("Settler", vm.toString(i)));
            vm.label(address(apps[i]), string.concat("App", vm.toString(i)));
        }

        wireOApps(oapps);

        // Authorize LiquidityMatrix to send messages to all apps and other LiquidityMatrices
        for (uint32 i; i < CHAINS; ++i) {
            changePrank(owner, owner);
            for (uint32 j; j < CHAINS; ++j) {
                if (i != j) {
                    // Allow LiquidityMatrix[i] to send to apps[j] and liquidityMatrices[j]
                    gateways[i].authorizeTarget(address(liquidityMatrices[i]), apps[j], true);
                    gateways[i].authorizeTarget(address(liquidityMatrices[i]), address(liquidityMatrices[j]), true);
                }
            }
        }

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
            gateways[i].configureChains(chainUIDs, configConfirmations);

            // Set read targets for LiquidityMatrix to read each other
            bytes32[] memory readChainUIDs = new bytes32[](CHAINS - 1);
            address[] memory readTargets = new address[](CHAINS - 1);
            uint256 readCount;
            for (uint32 j; j < CHAINS; ++j) {
                if (i != j) {
                    changePrank(apps[i], apps[i]);
                    liquidityMatrices[i].updateRemoteApp(bytes32(uint256(eids[j])), address(apps[j]), 0);
                    readChainUIDs[readCount] = bytes32(uint256(eids[j]));
                    readTargets[readCount] = address(liquidityMatrices[j]);
                    readCount++;
                }
            }
            // Configure read chains and targets for LiquidityMatrix
            changePrank(owner, owner);
            liquidityMatrices[i].configureReadChains(readChainUIDs, readTargets);
            changePrank(apps[i], apps[i]);
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

        changePrank(address(liquidityMatrices[0]), address(liquidityMatrices[0]));
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(
            bytes32(uint256(bytes32(uint256(eids[1])))), apps[0], remotes, locals
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

        changePrank(address(liquidityMatrices[0]), address(liquidityMatrices[0]));
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(
            bytes32(uint256(bytes32(uint256(eids[1])))), apps[0], remotes, locals
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
                  getLastReceivedRemoteLiquidityRoot() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLastReceivedRemoteLiquidityRoot() public {
        // Initially no root
        (bytes32 root, uint256 timestamp) =
            liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);

        // Update remote liquidity and sync
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 100e18);

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Now has received root
        (root, timestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(bytes32(uint256(eids[1])));
        assertTrue(root != bytes32(0));
        assertTrue(timestamp > 0);

        // Sync again with updated liquidity
        skip(100);
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 200e18);
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Should return the latest root
        (bytes32 newRoot, uint256 newTimestamp) =
            liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(bytes32(uint256(eids[1])));
        assertTrue(newRoot != root);
        assertTrue(newTimestamp > timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                    getLastReceivedRemoteDataRoot() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLastReceivedRemoteDataRoot() public {
        // Initially no root
        (bytes32 root, uint256 timestamp) =
            liquidityMatrices[0].getLastReceivedRemoteDataRoot(bytes32(uint256(eids[1])));
        assertEq(root, bytes32(0));
        assertEq(timestamp, 0);

        // Update remote data and sync
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalData(keccak256("key"), abi.encode("value"));

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Now has received root
        (root, timestamp) = liquidityMatrices[0].getLastReceivedRemoteDataRoot(bytes32(uint256(eids[1])));
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
                      getRemoteLiquidityRootAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getRemoteLiquidityRootAt() public {
        // Setup: Create liquidity updates on remote chain
        changePrank(apps[1], apps[1]);

        bytes32 initialRoot = liquidityMatrices[0].getLocalLiquidityRoot(apps[0]);

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
            liquidityMatrices[0].getRemoteLiquidityRootAt(remoteEid, uint64(timestamp0)),
            liquidityRoot0,
            "Root at T0 mismatch"
        );
        assertEq(
            liquidityMatrices[0].getRemoteLiquidityRootAt(remoteEid, uint64(timestamp1)),
            liquidityRoot1,
            "Root at T1 mismatch"
        );
        assertEq(
            liquidityMatrices[0].getRemoteLiquidityRootAt(remoteEid, uint64(timestamp2)),
            liquidityRoot2,
            "Root at T2 mismatch"
        );

        // Verify roots changed between syncs
        assertTrue(liquidityRoot0 != liquidityRoot1, "Root should change after update");
        assertTrue(liquidityRoot1 != liquidityRoot2, "Root should change after clearing");

        // Test between timestamps
        assertEq(liquidityMatrices[0].getRemoteLiquidityRootAt(remoteEid, uint64(timestamp0 + 100)), liquidityRoot0);
        assertEq(liquidityMatrices[0].getRemoteLiquidityRootAt(remoteEid, uint64(timestamp1 + 100)), liquidityRoot1);

        // Test before first root
        if (timestamp0 > 100) {
            assertEq(liquidityMatrices[0].getRemoteLiquidityRootAt(remoteEid, uint64(timestamp0 - 100)), initialRoot);
        }

        // Test far future
        assertEq(
            liquidityMatrices[0].getRemoteLiquidityRootAt(remoteEid, uint64(block.timestamp + 10_000)), liquidityRoot2
        );
    }

    /*//////////////////////////////////////////////////////////////
                        getRemoteDataRootAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getRemoteDataRootAt_historicalValues() public {
        // Setup: Create data updates on remote chain
        changePrank(apps[1], apps[1]);

        bytes32 initialRoot = liquidityMatrices[0].getLocalLiquidityRoot(apps[0]);

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
            liquidityMatrices[0].getRemoteDataRootAt(remoteEid, uint64(timestamp0)),
            dataRoot0,
            "Data root at T0 mismatch"
        );
        assertEq(
            liquidityMatrices[0].getRemoteDataRootAt(remoteEid, uint64(timestamp1)),
            dataRoot1,
            "Data root at T1 mismatch"
        );
        assertEq(
            liquidityMatrices[0].getRemoteDataRootAt(remoteEid, uint64(timestamp2)),
            dataRoot2,
            "Data root at T2 mismatch"
        );

        // Verify roots changed between syncs
        assertTrue(dataRoot0 != dataRoot1, "Data root should change after update");
        assertTrue(dataRoot1 != dataRoot2, "Data root should change after clearing");

        // Test between timestamps
        assertEq(liquidityMatrices[0].getRemoteDataRootAt(remoteEid, uint64(timestamp0 + 100)), dataRoot0);
        assertEq(liquidityMatrices[0].getRemoteDataRootAt(remoteEid, uint64(timestamp1 + 100)), dataRoot1);

        // Test before first root
        if (timestamp0 > 100) {
            assertEq(liquidityMatrices[0].getRemoteDataRootAt(remoteEid, uint64(timestamp0 - 100)), initialRoot);
        }

        // Test far future
        assertEq(liquidityMatrices[0].getRemoteDataRootAt(remoteEid, uint64(block.timestamp + 10_000)), dataRoot2);
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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(bytes32(uint256(eids[1])));
        changePrank(settler, settler);
        address[] memory accounts = new address[](2);
        accounts[0] = users[0];
        accounts[1] = users[2];
        int256[] memory liquidity = new int256[](2);
        liquidity[0] = 400e18;
        liquidity[1] = 100e18;

        // Settle liquidity with automatic proof generation
        _settleLiquidity(
            liquidityMatrices[0],
            remotes[0],
            apps[0],
            bytes32(uint256(eids[1])),
            uint64(rootTimestamp),
            accounts,
            liquidity
        );

        // Test REMOTE total liquidity after settling (for the specific remote chain)
        // Remote chain total: 500e18 (400 + 100)
        assertEq(
            liquidityMatrices[0].getRemoteTotalLiquidityAt(apps[0], bytes32(uint256(eids[1])), uint64(block.timestamp)),
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
        // First whitelist the new settler
        address newSettler = makeAddr("newWhitelistedSettler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(newSettler, true);

        // Now app can update to the whitelisted settler
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateSettler(newSettler);

        (,,, address settler) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertEq(settler, newSettler);
    }

    function test_updateSettler_requiresWhitelistedSettler() public {
        // Try to update to unwhitelisted settler - should fail with the fix
        address unwhitelistedSettler = makeAddr("unwhitelistedSettler");

        changePrank(apps[0], apps[0]);
        vm.expectRevert(ILiquidityMatrix.InvalidSettler.selector);
        liquidityMatrices[0].updateSettler(unwhitelistedSettler);

        // Verify settler hasn't changed
        (,,, address settler) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertEq(settler, settlers[0]); // Should still be the original settler

        // Whitelist the new settler
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(unwhitelistedSettler, true);

        // Now update should succeed
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateSettler(unwhitelistedSettler);

        // Verify settler has changed
        (,,, settler) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertEq(settler, unwhitelistedSettler);
    }

    function test_registerApp_requiresWhitelistedSettler() public {
        address unwhitelistedSettler = makeAddr("unwhitelistedSettler");
        address newApp = makeAddr("securityTestApp");

        // Try to register with unwhitelisted settler - should fail
        changePrank(newApp, newApp);
        vm.expectRevert(ILiquidityMatrix.InvalidSettler.selector);
        liquidityMatrices[0].registerApp(false, false, unwhitelistedSettler);

        // Whitelist the settler
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(unwhitelistedSettler, true);

        // Now registration should succeed
        changePrank(newApp, newApp);
        liquidityMatrices[0].registerApp(false, false, unwhitelistedSettler);

        // Verify app is registered with correct settler
        (bool registered,,, address settler) = liquidityMatrices[0].getAppSetting(newApp);
        assertTrue(registered);
        assertEq(settler, unwhitelistedSettler);
    }

    function test_settlerWhitelistBypass_prevented() public {
        // This test demonstrates the vulnerability would have allowed before the fix
        // and confirms it's now prevented

        address maliciousSettler = makeAddr("maliciousSettler");
        address secureApp = makeAddr("secureApp");

        // Step 1: App registers with whitelisted settler (settlers[0] is whitelisted in setup)
        changePrank(secureApp, secureApp);
        liquidityMatrices[0].registerApp(false, false, settlers[0]);

        // Step 2: App attempts to change to malicious unwhitelisted settler
        // Before fix: This would succeed, giving malicious settler full privileges
        // After fix: This should revert
        changePrank(secureApp, secureApp);
        vm.expectRevert(ILiquidityMatrix.InvalidSettler.selector);
        liquidityMatrices[0].updateSettler(maliciousSettler);

        // Create version 2 for further testing
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(uint64(block.timestamp + 1));

        // Verify the malicious settler cannot perform settler actions
        changePrank(maliciousSettler, maliciousSettler);
        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].addLocalAppChronicle(secureApp, 2);

        // The original whitelisted settler can still perform actions
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addLocalAppChronicle(secureApp, 2);
    }

    function test_onlyAppSettler_worksWithWhitelistedSettlers() public {
        address testApp = makeAddr("multiSettlerApp");

        // Register app with initial whitelisted settler
        changePrank(testApp, testApp);
        liquidityMatrices[0].registerApp(false, false, settlers[0]);

        // Create version 2
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(uint64(block.timestamp + 1));

        // The app's designated settler can add chronicles for version 2
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addLocalAppChronicle(testApp, 2);

        // Whitelist another settler globally
        address globalSettler = makeAddr("globalSettler");
        changePrank(owner, owner);
        liquidityMatrices[0].updateSettlerWhitelisted(globalSettler, true);

        // Global settler can also add chronicles (for version 3)
        changePrank(globalSettler, globalSettler);
        liquidityMatrices[0].addVersion(uint64(block.timestamp + 2));
        liquidityMatrices[0].addLocalAppChronicle(testApp, 3);

        // Unwhitelisted settler cannot add chronicles
        address unwhitelistedSettler = makeAddr("unwhitelistedSettler");
        changePrank(unwhitelistedSettler, unwhitelistedSettler);
        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].addRemoteAppChronicle(testApp, bytes32("CHAIN"), 1);
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

    function test_settleLiquidity_basic() public {
        // Use the settler that was configured during app registration
        address settler = settlers[0];

        // Verify app is registered with correct settler
        (bool registered,,, address appSettler) = liquidityMatrices[0].getAppSetting(apps[0]);
        require(registered, "App not registered");
        require(appSettler == settler, "Wrong settler configured");

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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(remoteEid);

        _settleLiquidity(
            liquidityMatrices[0], remotes[0], apps[0], remoteEid, uint64(rootTimestamp), testAccounts, testLiquidity
        );

        // Verify settlement - check liquidity through LiquidityMatrix wrapper functions
        for (uint256 i = 0; i < testAccounts.length; i++) {
            int256 remoteLiquidity = liquidityMatrices[1].getLocalLiquidity(apps[1], testAccounts[i]);
            assertEq(
                liquidityMatrices[0].getRemoteLiquidityAt(apps[0], remoteEid, testAccounts[i], uint64(rootTimestamp)),
                remoteLiquidity
            );
        }
        assertEq(
            liquidityMatrices[0].getRemoteTotalLiquidityAt(apps[0], remoteEid, uint64(rootTimestamp)), totalLiquidity
        );
        // Check if liquidity is settled through the chronicle
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
        assertTrue(IRemoteAppChronicle(chronicle).isLiquiditySettled(uint64(rootTimestamp)));
    }

    function test_settleLiquidity_withCallbacks() public {
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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(remoteEid);

        _settleLiquidity(
            liquidityMatrices[0], remotes[0], apps[0], remoteEid, uint64(rootTimestamp), testAccounts, testLiquidity
        );

        // Verify hooks were called with final liquidity values
        assertEq(IAppMock(apps[0]).remoteTotalLiquidity(remoteEid), totalLiquidity);
        for (uint256 i = 0; i < testAccounts.length; i++) {
            int256 remoteLiquidity = liquidityMatrices[1].getLocalLiquidity(apps[1], testAccounts[i]);
            assertEq(IAppMock(apps[0]).remoteLiquidity(remoteEid, testAccounts[i]), remoteLiquidity);
        }
    }

    function test_settleLiquidity_alreadySettled() public {
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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(remoteEid);

        _settleLiquidity(
            liquidityMatrices[0], remotes[0], apps[0], remoteEid, uint64(rootTimestamp), accounts, liquidity
        );

        // Second settlement should revert
        _settleLiquidity(
            liquidityMatrices[0],
            remotes[0],
            apps[0],
            remoteEid,
            uint64(rootTimestamp),
            accounts,
            liquidity,
            abi.encodeWithSelector(IRemoteAppChronicle.LiquidityAlreadySettled.selector)
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

        // Create valid params for testing access control
        bytes32[] memory accountKeys = new bytes32[](accounts.length);
        bytes32[] memory liquidityValues = new bytes32[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            accountKeys[i] = bytes32(uint256(uint160(accounts[i])));
            liquidityValues[i] = bytes32(uint256(liquidity[i]));
        }
        bytes32 appLiquidityRoot = MerkleTreeLib.computeRoot(accountKeys, liquidityValues);

        bytes32[] memory appKeys = new bytes32[](1);
        bytes32[] memory appRoots = new bytes32[](1);
        appKeys[0] = bytes32(uint256(uint160(apps[0])));
        appRoots[0] = appLiquidityRoot;

        bytes32[] memory proof = MerkleTreeLib.getProof(appKeys, appRoots, 0);

        // Calculate total liquidity
        int256 totalLiquidity = 0;
        for (uint256 i = 0; i < liquidity.length; i++) {
            totalLiquidity += liquidity[i];
        }

        // Create isContract array - all false for EOAs
        bool[] memory isContract = new bool[](accounts.length);

        RemoteAppChronicle(chronicle).settleLiquidity(
            RemoteAppChronicle.SettleLiquidityParams({
                timestamp: uint64(block.timestamp),
                accounts: accounts,
                liquidity: liquidity,
                isContract: isContract,
                totalLiquidity: totalLiquidity,
                liquidityRoot: appLiquidityRoot,
                proof: proof
            })
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

        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(bytes32(uint256(eids[1])));

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
        _settleLiquidity(
            liquidityMatrices[0],
            remotes[0],
            apps[0],
            bytes32(uint256(eids[1])),
            uint64(rootTimestamp),
            accounts,
            liquidity
        );

        // Verify settled values through LiquidityMatrix wrapper functions
        assertEq(
            liquidityMatrices[0].getRemoteLiquidityAt(
                apps[0], bytes32(uint256(eids[1])), users[0], uint64(rootTimestamp)
            ),
            100e18
        );
        assertEq(
            liquidityMatrices[0].getRemoteLiquidityAt(
                apps[0], bytes32(uint256(eids[1])), users[1], uint64(rootTimestamp)
            ),
            -50e18
        );
        assertEq(
            liquidityMatrices[0].getRemoteLiquidityAt(
                apps[0], bytes32(uint256(eids[1])), users[2], uint64(rootTimestamp)
            ),
            0
        );
        assertEq(
            liquidityMatrices[0].getRemoteLiquidityAt(
                apps[0], bytes32(uint256(eids[1])), users[3], uint64(rootTimestamp)
            ),
            200e18
        );
        assertEq(
            liquidityMatrices[0].getRemoteTotalLiquidityAt(apps[0], bytes32(uint256(eids[1])), uint64(rootTimestamp)),
            250e18
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
            (, uint256 rootTimestamp) =
                liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(bytes32(uint256(eids[i])));

            address[] memory accounts = new address[](3);
            int256[] memory liquidity = new int256[](3);
            for (uint256 j = 0; j < 3; j++) {
                accounts[j] = users[j];
                liquidity[j] = int256((i + 1) * (j + 1) * 1e18);
            }

            _settleLiquidity(
                liquidityMatrices[0],
                remotes[i - 1],
                apps[0],
                bytes32(uint256(eids[i])),
                uint64(rootTimestamp),
                accounts,
                liquidity
            );
        }

        // Verify total liquidity - calculate from local and remote
        int256 totalLocal = liquidityMatrices[0].getLocalTotalLiquidity(apps[0]);
        int256 totalRemote = 0;
        for (uint256 i = 1; i < CHAINS; i++) {
            (, uint256 rootTimestamp) =
                liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(bytes32(uint256(eids[i])));
            totalRemote += liquidityMatrices[0].getRemoteTotalLiquidityAt(
                apps[0], bytes32(uint256(eids[i])), uint64(rootTimestamp)
            );
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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(remoteEid);

        // Settle all accounts at once through RemoteAppChronicle
        changePrank(settler, settler);
        _settleLiquidity(
            liquidityMatrices[0], remotes[0], apps[0], remoteEid, uint64(rootTimestamp), accounts, liquidity
        );

        // Verify all settlements using LiquidityMatrix wrapper
        for (uint256 i = 0; i < numAccounts; i++) {
            assertEq(
                liquidityMatrices[0].getRemoteLiquidityAt(apps[0], remoteEid, accounts[i], uint64(rootTimestamp)),
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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(remoteEid);

        // Settler settles both accounts through RemoteAppChronicle
        changePrank(settler, settler);
        address[] memory accounts = new address[](2);
        accounts[0] = users[0];
        accounts[1] = users[1];
        int256[] memory liquidity = new int256[](2);
        liquidity[0] = 100e18;
        liquidity[1] = 200e18;

        _settleLiquidity(
            liquidityMatrices[0], remotes[0], apps[0], remoteEid, uint64(rootTimestamp), accounts, liquidity
        );

        // Try to settle again (should revert due to LiquidityAlreadySettled)
        _settleLiquidity(
            liquidityMatrices[0],
            remotes[0],
            apps[0],
            remoteEid,
            uint64(rootTimestamp),
            accounts,
            liquidity,
            abi.encodeWithSelector(IRemoteAppChronicle.LiquidityAlreadySettled.selector)
        );

        // Verify the first settlement succeeded using LiquidityMatrix wrapper
        assertEq(liquidityMatrices[0].getRemoteLiquidityAt(apps[0], remoteEid, users[0], uint64(rootTimestamp)), 100e18);
        assertEq(liquidityMatrices[0].getRemoteLiquidityAt(apps[0], remoteEid, users[1], uint64(rootTimestamp)), 200e18);

        // Test settlement at different timestamp works
        skip(100);
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(users[0], 150e18);
        _sync(syncers[0], liquidityMatrices[0], remotes);

        (, uint256 newTimestamp) = liquidityMatrices[0].getLastReceivedRemoteLiquidityRoot(remoteEid);
        changePrank(settler, settler);
        address[] memory newAccounts = new address[](1);
        newAccounts[0] = users[0];
        int256[] memory newLiquidity = new int256[](1);
        newLiquidity[0] = 150e18;

        // This should work as it's a different timestamp
        _settleLiquidity(
            liquidityMatrices[0], remotes[0], apps[0], remoteEid, uint64(newTimestamp), newAccounts, newLiquidity
        );

        assertEq(liquidityMatrices[0].getRemoteLiquidityAt(apps[0], remoteEid, users[0], uint64(newTimestamp)), 150e18);
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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteDataRoot(remoteEid);

        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], remoteEid, uint64(rootTimestamp), keys, values);

        // Verify settlement using RemoteAppChronicle
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteDataRoot(bytes32(uint256(eids[1])));

        // First settlement
        changePrank(settler, settler);
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("key");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("value");

        _settleData(
            liquidityMatrices[0],
            liquidityMatrices[1],
            apps[0],
            bytes32(uint256(eids[1])),
            uint64(rootTimestamp),
            keys,
            values
        );

        // Try to settle again
        _settleData(
            liquidityMatrices[0],
            liquidityMatrices[1],
            apps[0],
            bytes32(uint256(eids[1])),
            uint64(rootTimestamp),
            keys,
            values,
            abi.encodeWithSelector(IRemoteAppChronicle.DataAlreadySettled.selector)
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

        // Create valid params for testing access control
        bytes32[] memory valueHashes = new bytes32[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            valueHashes[i] = keccak256(values[i]);
        }
        bytes32 appDataRoot = MerkleTreeLib.computeRoot(keys, valueHashes);

        bytes32[] memory appKeys = new bytes32[](1);
        bytes32[] memory appRoots = new bytes32[](1);
        appKeys[0] = bytes32(uint256(uint160(apps[0])));
        appRoots[0] = appDataRoot;

        bytes32[] memory proof = MerkleTreeLib.getProof(appKeys, appRoots, 0);

        RemoteAppChronicle(chronicle).settleData(
            RemoteAppChronicle.SettleDataParams({
                timestamp: uint64(block.timestamp),
                keys: keys,
                values: values,
                dataRoot: appDataRoot,
                proof: proof
            })
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
        (, uint256 rootTimestamp) = liquidityMatrices[0].getLastReceivedRemoteDataRoot(remoteEid);

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

        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], remoteEid, uint64(rootTimestamp), keys, values);

        // Verify all data through RemoteAppChronicle
        address chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], remoteEid);
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
        changePrank(address(liquidityMatrices[0]), address(liquidityMatrices[0]));

        bytes32 chainUID = bytes32(uint256(30_001));

        // Send roots with timestamps out of order (using version 1)
        liquidityMatrices[0].onReceiveRoots(chainUID, 1, keccak256("liquidity_root_1"), keccak256("data_root_1"), 1000);

        // Send earlier timestamp (should be ignored for latest)
        vm.expectRevert(abi.encodeWithSelector(ILiquidityMatrix.StaleRoots.selector, chainUID));
        liquidityMatrices[0].onReceiveRoots(chainUID, 1, keccak256("liquidity_root_2"), keccak256("data_root_2"), 500);
    }

    /*//////////////////////////////////////////////////////////////
                onReceiveMapRemoteAccountRequests() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onReceiveMapRemoteAccountRequests_onlySynchronizer() public {
        address notSynchronizer = makeAddr("notSynchronizer");
        changePrank(notSynchronizer, notSynchronizer);

        vm.expectRevert(ILiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(
            bytes32(uint256(eids[1])), apps[0], new address[](0), new address[](0)
        );
    }

    function test_onReceiveMapRemoteAccountRequests_remoteAlreadyMapped() public {
        // App is already registered and remote app is already set up in setup()

        // Set up the app mock to allow mapping
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(bytes32(uint256(eids[1])))), users[0], users[1], true);
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(eids[1])), users[0], users[2], true);

        // Simulate receiving a map request from remote chain
        // First mapping succeeds
        changePrank(address(liquidityMatrices[0]), address(liquidityMatrices[0]));
        address[] memory remotes1 = new address[](1);
        address[] memory locals1 = new address[](1);
        remotes1[0] = users[0];
        locals1[0] = users[1];
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], remotes1, locals1);

        // Try to map same remote account to different local
        address[] memory remotes2 = new address[](1);
        address[] memory locals2 = new address[](1);
        remotes2[0] = users[0];
        locals2[0] = users[2];
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidityMatrix.RemoteAccountAlreadyMapped.selector, bytes32(uint256(eids[1])), users[0]
            )
        );
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], remotes2, locals2);
    }

    function test_onReceiveMapRemoteAccountRequests_localAlreadyMapped() public {
        // App is already registered and remote app is already set up in setup()

        // Set up the app mock to allow mapping
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(bytes32(uint256(eids[1])))), users[0], users[1], true);
        AppMock(apps[0]).setShouldMapAccounts(bytes32(uint256(eids[1])), users[2], users[1], true);

        // Simulate receiving a map request from remote chain
        // First mapping succeeds
        changePrank(address(liquidityMatrices[0]), address(liquidityMatrices[0]));
        address[] memory remotes1 = new address[](1);
        address[] memory locals1 = new address[](1);
        remotes1[0] = users[0];
        locals1[0] = users[1];
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], remotes1, locals1);

        // Try to map different remote account to same local
        address[] memory remotes2 = new address[](1);
        address[] memory locals2 = new address[](1);
        remotes2[0] = users[2];
        locals2[0] = users[1];
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidityMatrix.LocalAccountAlreadyMapped.selector, bytes32(uint256(eids[1])), users[1]
            )
        );
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), apps[0], remotes2, locals2);
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
        changePrank(address(liquidityMatrices[0]), address(liquidityMatrices[0]));
        liquidityMatrices[0].onReceiveMapRemoteAccountRequests(bytes32(uint256(eids[1])), callbackApp, remotes, locals);

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
                        PAUSE FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pausable_setPaused() public {
        changePrank(owner, owner);

        // Test pausing single action
        bytes32 pauseFlags = bytes32(uint256(1 << 0)); // Bit 1
        liquidityMatrices[0].setPaused(pauseFlags);

        assertEq(liquidityMatrices[0].pauseFlags(), pauseFlags);
        assertTrue(liquidityMatrices[0].isPaused(1));
        assertFalse(liquidityMatrices[0].isPaused(2));
    }

    function test_pausable_setPaused_unauthorized() public {
        changePrank(alice, alice);

        bytes32 pauseFlags = bytes32(uint256(1 << 0));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        liquidityMatrices[0].setPaused(pauseFlags);
    }

    function test_pausable_registerApp_whenPaused() public {
        // Pause registerApp (ACTION_REGISTER_APP = bit 1)
        changePrank(owner, owner);
        bytes32 pauseFlags = bytes32(uint256(1 << 0)); // Bit 1
        liquidityMatrices[0].setPaused(pauseFlags);

        // Try to register a new app
        address newApp = makeAddr("newApp");
        changePrank(newApp, newApp);

        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 1));
        liquidityMatrices[0].registerApp(false, false, settlers[0]);
    }

    function test_pausable_sync_whenPaused() public {
        // Pause sync (ACTION_SYNC = bit 2)
        changePrank(owner, owner);
        bytes32 pauseFlags = bytes32(uint256(1 << 1)); // Bit 2
        liquidityMatrices[0].setPaused(pauseFlags);

        // Try to sync
        changePrank(syncers[0], syncers[0]);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 2));
        liquidityMatrices[0].sync{ value: 1 ether }("");
    }

    function test_pausable_addVersion_whenPaused() public {
        // Pause addVersion (ACTION_ADD_VERSION = bit 3)
        changePrank(owner, owner);
        bytes32 pauseFlags = bytes32(uint256(1 << 2)); // Bit 3
        liquidityMatrices[0].setPaused(pauseFlags);

        // Try to add a version
        changePrank(settlers[0], settlers[0]);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 3));
        liquidityMatrices[0].addVersion(uint64(block.timestamp + 1000));
    }

    function test_pausable_addLocalAppChronicle_whenPaused() public {
        // First add a new version
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(uint64(block.timestamp + 1000));

        // Pause addLocalAppChronicle (ACTION_ADD_LOCAL_CHRONICLE = bit 4)
        changePrank(owner, owner);
        bytes32 pauseFlags = bytes32(uint256(1 << 3)); // Bit 4
        liquidityMatrices[0].setPaused(pauseFlags);

        // Try to add local app chronicle
        changePrank(settlers[0], settlers[0]);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 4));
        liquidityMatrices[0].addLocalAppChronicle(apps[0], 2);
    }

    function test_pausable_addRemoteAppChronicle_whenPaused() public {
        // First add a new version
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(uint64(block.timestamp + 1000));

        // Pause addRemoteAppChronicle (ACTION_ADD_REMOTE_CHRONICLE = bit 5)
        changePrank(owner, owner);
        bytes32 pauseFlags = bytes32(uint256(1 << 4)); // Bit 5
        liquidityMatrices[0].setPaused(pauseFlags);

        // Try to add remote app chronicle
        changePrank(settlers[0], settlers[0]);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 5));
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], bytes32(uint256(eids[1])), 2);
    }

    function test_pausable_multipleActions() public {
        changePrank(owner, owner);

        // Pause multiple actions: registerApp (bit 1) and sync (bit 2)
        bytes32 pauseFlags = bytes32(uint256((1 << 0) | (1 << 1)));
        liquidityMatrices[0].setPaused(pauseFlags);

        assertTrue(liquidityMatrices[0].isPaused(1));
        assertTrue(liquidityMatrices[0].isPaused(2));
        assertFalse(liquidityMatrices[0].isPaused(3));

        // Verify registerApp is paused
        address newApp = makeAddr("newApp");
        changePrank(newApp, newApp);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 1));
        liquidityMatrices[0].registerApp(false, false, settlers[0]);

        // Verify sync is paused
        changePrank(syncers[0], syncers[0]);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 2));
        liquidityMatrices[0].sync{ value: 1 ether }("");
    }

    function test_pausable_unpause() public {
        changePrank(owner, owner);

        // First pause an action
        bytes32 pauseFlags = bytes32(uint256(1 << 0));
        liquidityMatrices[0].setPaused(pauseFlags);
        assertTrue(liquidityMatrices[0].isPaused(1));

        // Unpause all actions
        liquidityMatrices[0].setPaused(bytes32(0));
        assertFalse(liquidityMatrices[0].isPaused(1));

        // Verify action works again
        address newApp = makeAddr("newApp");
        changePrank(newApp, newApp);
        liquidityMatrices[0].registerApp(false, false, settlers[0]);

        // Verify app was registered - check if local chronicle exists
        assertNotEq(liquidityMatrices[0].getCurrentLocalAppChronicle(newApp), address(0));
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
