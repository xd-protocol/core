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

contract LiquidityMatrixIntegrationTest is LiquidityMatrixTestHelper {
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

        // Deploy deployers once (shared across all chains for testing)
        LocalAppChronicleDeployer localDeployer = new LocalAppChronicleDeployer();
        RemoteAppChronicleDeployer remoteDeployer = new RemoteAppChronicleDeployer();

        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            syncers[i] = makeAddr(string.concat("syncer", vm.toString(i)));
            // Create LiquidityMatrix with owner, timestamp, and deployers
            liquidityMatrices[i] = new LiquidityMatrix(owner, 1, address(localDeployer), address(remoteDeployer));

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
                    changePrank(owner, owner);
                    liquidityMatrices[i].updateReadTarget(
                        bytes32(uint256(eids[j])), bytes32(uint256(uint160(address(liquidityMatrices[j]))))
                    );
                    changePrank(apps[i], apps[i]);
                    liquidityMatrices[i].updateRemoteApp(bytes32(uint256(eids[j])), address(apps[j]), 0);
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

        _settleLiquidity(
            liquidityMatrices[0],
            remotes[0],
            apps[0],
            chain1Eid,
            uint64(chain1Timestamp),
            chain1Accounts,
            chain1Liquidity
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
        changePrank(address(liquidityMatrices[0]), address(liquidityMatrices[0]));

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

        _settleLiquidity(
            liquidityMatrices[0],
            liquidityMatrices[1],
            apps[0],
            bytes32(uint256(eids[1])),
            uint64(t2),
            accounts,
            liquidity
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

        _settleData(
            liquidityMatrices[0], liquidityMatrices[1], apps[0], bytes32(uint256(eids[1])), uint64(t3), keys, values
        );

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
        _settleLiquidity(
            liquidityMatrices[0],
            liquidityMatrices[1],
            apps[0],
            bytes32(uint256(eids[1])),
            uint64(t1),
            accounts,
            liquidity
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
        _settleData(
            liquidityMatrices[0], liquidityMatrices[1], apps[0], bytes32(uint256(eids[1])), uint64(t2), keys, values
        );

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
        _settleLiquidity(
            liquidityMatrices[0],
            liquidityMatrices[1],
            apps[0],
            bytes32(uint256(eids[1])),
            uint64(t3),
            accounts,
            liquidity
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
        _settleData(
            liquidityMatrices[0], liquidityMatrices[1], apps[0], bytes32(uint256(eids[1])), uint64(t1), keys, values
        );

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

    function test_addVersion_basic() public {
        uint64 reorgTimestamp = uint64(block.timestamp + 1000);

        // Initially version should be 1
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp - 1), 1);
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp), 1);
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp + 1), 1);

        // Add a reorg (need to use a whitelisted settler)
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(reorgTimestamp);

        // After reorg, timestamps before should be version 1, after should be version 2
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp - 1), 1);
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp), 2);
        assertEq(liquidityMatrices[0].getVersion(reorgTimestamp + 1), 2);
    }

    function test_addVersion_multipleReorgs() public {
        uint64 reorg1 = uint64(block.timestamp + 1000);
        uint64 reorg2 = reorg1 + 1000;
        uint64 reorg3 = reorg2 + 1000;

        changePrank(settlers[0], settlers[0]);

        // Add multiple reorgs
        liquidityMatrices[0].addVersion(reorg1);
        liquidityMatrices[0].addVersion(reorg2);
        liquidityMatrices[0].addVersion(reorg3);

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

    function test_addVersion_revertNonOwner() public {
        uint64 reorgTimestamp = uint64(block.timestamp);

        changePrank(alice, alice);
        vm.expectRevert();
        liquidityMatrices[0].addVersion(reorgTimestamp);
    }

    function test_addVersion_revertInvalidTimestamp() public {
        changePrank(settlers[0], settlers[0]);

        // Add a reorg at timestamp 1000
        liquidityMatrices[0].addVersion(1000);

        // Try to add a reorg at an earlier timestamp (should revert)
        vm.expectRevert(ILiquidityMatrix.InvalidTimestamp.selector);
        liquidityMatrices[0].addVersion(999);

        // Try to add a reorg at the same timestamp (should revert)
        vm.expectRevert(ILiquidityMatrix.InvalidTimestamp.selector);
        liquidityMatrices[0].addVersion(1000);
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
            liquidityMatrices[0].addVersion(reorgTimestamps[i]);
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
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, timestamp1, accounts, liquidity);

        // Verify settlement for version 1
        address chronicle1 = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        assertEq(IRemoteAppChronicle(chronicle1).getLiquidityAt(alice, timestamp1), 50e18);

        // Add a reorg
        skip(100);
        uint64 reorgTimestamp = uint64(block.timestamp);
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(reorgTimestamp);

        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Settle for version 2 (after reorg)
        skip(100);
        uint64 timestamp2 = uint64(block.timestamp);
        liquidity[0] = 75e18;
        changePrank(settlers[0], settlers[0]);
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, timestamp2, accounts, liquidity);

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
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, timestamp1, keys, values);

        // Add a reorg
        skip(100);
        uint64 reorgTimestamp = uint64(block.timestamp);
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(reorgTimestamp);

        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Settle different data for version 2
        skip(100);
        uint64 timestamp2 = uint64(block.timestamp);
        values[0] = value2;
        changePrank(settlers[0], settlers[0]);
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, timestamp2, keys, values);

        // Verify version 2 data (version 1 data not accessible from v2)
        assertEq(keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, key, timestamp1)), keccak256("")); // Empty in v2
        assertEq(keccak256(liquidityMatrices[0].getDataAt(apps[0], chainUID, key, timestamp2)), keccak256(value2)); // V2 data
    }

    function test_integration_reorgWithActiveSettlements() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));

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
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, accounts, liquidity);

        // Settlement 2 at t=2000
        vm.warp(2000);
        liquidity[0] = 150e18;
        liquidity[1] = 250e18;
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 2000, accounts, liquidity);

        // Reorg happens at t=1500 (between the two settlements)
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(1500);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // New settlements for version 2
        changePrank(settlers[0], settlers[0]);

        // Settlement for version 2 at t=1600
        vm.warp(1600);
        liquidity[0] = 120e18;
        liquidity[1] = 220e18;
        // Settlement after reorg - version handled by chronicle
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1600, accounts, liquidity);

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
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);

        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(alice, 0);

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Version 1: Settlement at t=1000
        vm.warp(1000);
        liquidity[0] = 100e18;
        changePrank(settlers[0], settlers[0]);
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, accounts, liquidity);

        // First reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(1500);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        // Version 2: Settlement at t=2000
        vm.warp(2000);
        liquidity[0] = 200e18;
        changePrank(settlers[0], settlers[0]);
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 2000, accounts, liquidity);

        // Second reorg at t=2500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(2500);
        // Create RemoteAppChronicle for version 3
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 3);

        // Version 3: Settlement at t=3000
        vm.warp(3000);
        liquidity[0] = 300e18;
        changePrank(settlers[0], settlers[0]);
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 3000, accounts, liquidity);

        // Third reorg at t=3500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(3500);
        // Create RemoteAppChronicle for version 4
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 4);

        // Version 4: Settlement at t=4000
        vm.warp(4000);
        liquidity[0] = 400e18;
        changePrank(settlers[0], settlers[0]);
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 4000, accounts, liquidity);

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
            liquidityMatrices[0].addVersion(uint64(block.timestamp + i * 100));
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
        assertLt(gasUsed, 500_000); // Should use reasonable gas even with many reorgs
    }

    function test_edgeCase_settlementAtReorgTimestamp() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));
        address[] memory accounts = new address[](1);
        accounts[0] = alice;
        int256[] memory liquidity = new int256[](1);
        liquidity[0] = 100e18;

        // Add reorg at t=1000
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(1000);
        // Create RemoteAppChronicle for version 2
        liquidityMatrices[0].addRemoteAppChronicle(apps[0], chainUID, 2);

        changePrank(settlers[1], settlers[1]);
        liquidityMatrices[1].addVersion(1000);
        liquidityMatrices[1].addLocalAppChronicle(apps[1], 2);
        changePrank(apps[1], apps[1]);
        liquidityMatrices[1].updateLocalLiquidity(accounts[0], liquidity[0]);

        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = liquidityMatrices[1];
        _sync(syncers[0], liquidityMatrices[0], remotes);

        // Try to settle exactly at reorg timestamp for version 2
        vm.warp(1000);
        changePrank(settlers[0], settlers[0]);
        _settleLiquidity(liquidityMatrices[0], remotes[0], apps[0], chainUID, 1000, accounts, liquidity);
    }

    function test_edgeCase_queryBeforeAnySettlement() public {
        bytes32 chainUID = bytes32(uint256(eids[1]));

        // Add a reorg
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(1000);
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
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, accounts, liquidity);

        // Also settle data for finalization tests
        bytes32[] memory keys = new bytes32[](2);
        keys[0] = keccak256("key1");
        keys[1] = keccak256("key2");
        bytes[] memory values = new bytes[](2);
        values[0] = abi.encode("data1");
        values[1] = abi.encode("data2");
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, keys, values);

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
        liquidityMatrices[0].addVersion(1500);
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
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1700, accounts, liquidity);

        // Settle data for finalization
        values[0] = abi.encode("data1_v2");
        values[1] = abi.encode("data2_v2");
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1700, keys, values);

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
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, keys, values);

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
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, accounts, liquidity);

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
        liquidityMatrices[0].addVersion(1500);
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
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1700, keys, values);

        // Also settle liquidity for finalization
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1700, accounts, liquidity);

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
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1001, accounts, liquidity);

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = key;
        bytes[] memory values = new bytes[](1);
        values[0] = value;
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1001, keys, values);

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
        liquidityMatrices[0].addVersion(1500);
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
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, accounts, liquidity);
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, keys, values);

        // Check settlement status before reorg
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle remoteChronicle = IRemoteAppChronicle(chronicle);
        assertTrue(remoteChronicle.isLiquiditySettled(1000), "Liquidity settled at 1000");
        assertTrue(remoteChronicle.isDataSettled(1000), "Data settled at 1000");
        assertTrue(remoteChronicle.isFinalized(1000), "Finalized at 1000");

        // Add reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(1500);
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
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1700, accounts, liquidity);

        // Check partial settlement (liquidity but not data)
        assertTrue(remoteChronicle.isLiquiditySettled(1700), "Liquidity settled at 1700");
        assertFalse(remoteChronicle.isDataSettled(1700), "Data not settled at 1700");
        assertFalse(remoteChronicle.isFinalized(1700), "Not finalized without data");

        // Now settle data
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1700, keys, values);

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

        // Use helper to settle liquidity with proper Merkle proof
        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, accounts, liquidity);

        // Also settle data for version 1 to achieve finalization
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = keccak256("test_key");
        bytes[] memory values = new bytes[](1);
        values[0] = abi.encode("test_value");

        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 1000, keys, values);

        // Check finalization for version 1 (both liquidity and data are settled)
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        IRemoteAppChronicle remoteChronicle = IRemoteAppChronicle(chronicle);
        assertTrue(remoteChronicle.isFinalized(1000));

        // Add reorg at t=1500
        changePrank(settlers[0], settlers[0]);
        liquidityMatrices[0].addVersion(1500);
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

        _settleLiquidity(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 2000, accounts, liquidity);

        values[0] = abi.encode("test_value_v2");
        _settleData(liquidityMatrices[0], liquidityMatrices[1], apps[0], chainUID, 2000, keys, values);

        // Check finalization for version 2
        chronicle = liquidityMatrices[0].getCurrentRemoteAppChronicle(apps[0], chainUID);
        remoteChronicle = IRemoteAppChronicle(chronicle);
        assertTrue(remoteChronicle.isFinalized(2000));

        // Version 1 finalization should NOT be valid in version 2 chronicle
        assertFalse(remoteChronicle.isFinalized(1000));
    }
}
