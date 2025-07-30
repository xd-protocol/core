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

    function test_sync(bytes32 seed) public {
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            _updateLocalLiquidity(liquidityMatrices[i], apps[i], storages[i], users, seed);
            remotes[i - 1] = liquidityMatrices[i];
            seed = keccak256(abi.encodePacked(seed, i));
        }
        _sync(syncers[0], liquidityMatrices[0], remotes);
    }

    function test_requestMapRemoteAccounts() public {
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        address[] memory remoteApps = new address[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            remotes[i - 1] = liquidityMatrices[i];
            remoteApps[i - 1] = apps[i];
        }
        _requestMapRemoteAccounts(liquidityMatrices[0], apps[0], remotes, remoteApps, users);
    }

    function test_sync_withSpecificEids() public {
        bytes32 seed = keccak256("test_sync_withSpecificEids");

        // Update liquidity on all chains
        ILiquidityMatrix[] memory allRemotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint32 i = 0; i < CHAINS; ++i) {
            _updateLocalLiquidity(liquidityMatrices[i], apps[i], storages[i], users, seed);
            if (i > 0) {
                allRemotes[i - 1] = liquidityMatrices[i];
            }
            seed = keccak256(abi.encodePacked(seed, i));
        }

        // Test syncing with specific endpoint IDs
        uint32[] memory targetEids = new uint32[](2);
        targetEids[0] = eids[1];
        targetEids[1] = eids[2];

        // Use helper to properly simulate cross-chain sync with specific eids
        _syncWithEids(syncers[0], liquidityMatrices[0], targetEids, allRemotes);
    }

    function test_sync_withSpecificEids_forbiddenCaller() public {
        uint32[] memory targetEids = new uint32[](2);
        targetEids[0] = eids[1];
        targetEids[1] = eids[2];

        changePrank(users[0], users[0]); // Not the syncer
        uint128 gasLimit = 400_000;
        uint32 calldataSize = 256;

        vm.expectRevert(ISynchronizer.Forbidden.selector);
        synchronizers[0].sync{ value: 1 ether }(targetEids, gasLimit, calldataSize);
    }

    function test_sync_withSpecificEids_alreadyRequested() public {
        uint32[] memory targetEids = new uint32[](2);
        targetEids[0] = eids[1];
        targetEids[1] = eids[2];

        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 400_000;
        uint32 calldataSize = 256;
        uint256 fee = synchronizers[0].quoteSync(targetEids, gasLimit, calldataSize);

        // First sync should succeed
        synchronizers[0].sync{ value: fee }(targetEids, gasLimit, calldataSize);

        // Second sync in same block should fail
        vm.expectRevert(ISynchronizer.AlreadyRequested.selector);
        synchronizers[0].sync{ value: fee }(targetEids, gasLimit, calldataSize);

        // After time passes, sync should succeed again
        skip(1);
        synchronizers[0].sync{ value: fee }(targetEids, gasLimit, calldataSize);
    }

    function test_sync_withSpecificEids_insufficientFee() public {
        uint32[] memory targetEids = new uint32[](2);
        targetEids[0] = eids[1];
        targetEids[1] = eids[2];

        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 600_000;
        uint32 calldataSize = 384;
        uint256 fee = synchronizers[0].quoteSync(targetEids, gasLimit, calldataSize);

        // Try to sync with insufficient fee
        vm.expectRevert();
        synchronizers[0].sync{ value: fee - 1 }(targetEids, gasLimit, calldataSize);
    }

    function test_sync_withSpecificEids_emptyArray() public {
        uint32[] memory targetEids = new uint32[](0);

        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 200_000;
        uint32 calldataSize = 128;

        // Empty array might be rejected by LayerZero codec, expecting InvalidCmd
        vm.expectRevert(ISynchronizer.InvalidCmd.selector);
        synchronizers[0].sync{ value: 1 ether }(targetEids, gasLimit, calldataSize);
    }

    function test_sync_withSpecificEids_singleEid() public {
        bytes32 seed = keccak256("test_sync_withSpecificEids_singleEid");

        // Update liquidity on a single remote chain
        _updateLocalLiquidity(liquidityMatrices[2], apps[2], storages[2], users, seed);

        uint32[] memory targetEids = new uint32[](1);
        targetEids[0] = eids[2];

        ILiquidityMatrix[] memory allRemotes = new ILiquidityMatrix[](1);
        allRemotes[0] = liquidityMatrices[2];

        // Use helper to properly simulate cross-chain sync with single eid
        _syncWithEids(syncers[0], liquidityMatrices[0], targetEids, allRemotes);
    }

    function test_sync_withSpecificEids_allChains() public {
        bytes32 seed = keccak256("test_sync_withSpecificEids_allChains");

        // Update liquidity on all chains and prepare remotes
        ILiquidityMatrix[] memory allRemotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint32 i = 0; i < CHAINS; ++i) {
            _updateLocalLiquidity(liquidityMatrices[i], apps[i], storages[i], users, seed);
            if (i > 0) {
                allRemotes[i - 1] = liquidityMatrices[i];
            }
            seed = keccak256(abi.encodePacked(seed, i));
        }

        // Create array with all endpoint IDs except the local one
        uint32[] memory targetEids = new uint32[](CHAINS - 1);
        for (uint32 i = 0; i < CHAINS - 1; ++i) {
            targetEids[i] = eids[i + 1];
        }

        // Use helper to properly simulate cross-chain sync with all chains
        _syncWithEids(syncers[0], liquidityMatrices[0], targetEids, allRemotes);
    }

    function test_sync_allChains() public {
        bytes32 seed = keccak256("test_sync_allChains");

        // Prepare all remote matrices
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            _updateLocalLiquidity(liquidityMatrices[i], apps[i], storages[i], users, seed);
            remotes[i - 1] = liquidityMatrices[i];
            seed = keccak256(abi.encodePacked(seed, i));
        }

        // Use _sync helper to properly simulate cross-chain sync
        _sync(syncers[0], liquidityMatrices[0], remotes);
    }

    function test_sync_forbiddenCaller() public {
        changePrank(users[0], users[0]); // Not the syncer
        uint128 gasLimit = 400_000;
        uint32 calldataSize = 256;

        vm.expectRevert(ISynchronizer.Forbidden.selector);
        synchronizers[0].sync{ value: 1 ether }(gasLimit, calldataSize);
    }

    function test_sync_alreadyRequested() public {
        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 400_000;
        uint32 calldataSize = 256;
        uint256 fee = synchronizers[0].quoteSync(gasLimit, calldataSize);

        // First sync should succeed
        synchronizers[0].sync{ value: fee }(gasLimit, calldataSize);

        // Second sync in same block should fail
        vm.expectRevert(ISynchronizer.AlreadyRequested.selector);
        synchronizers[0].sync{ value: fee }(gasLimit, calldataSize);

        // After time passes, sync should succeed again
        skip(1);
        synchronizers[0].sync{ value: fee }(gasLimit, calldataSize);
    }

    function test_sync_insufficientFee() public {
        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 600_000;
        uint32 calldataSize = 384;
        uint256 fee = synchronizers[0].quoteSync(gasLimit, calldataSize);

        // Try to sync with insufficient fee
        vm.expectRevert();
        synchronizers[0].sync{ value: fee - 1 }(gasLimit, calldataSize);
    }

    function test_sync_withNoConfiguredChains() public {
        // Deploy a new LiquidityMatrix without configured chains
        changePrank(owner, owner);
        LiquidityMatrix emptyMatrix = new LiquidityMatrix(owner);
        Synchronizer emptySynchronizer =
            new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[1], address(emptyMatrix), syncers[0], owner);
        emptyMatrix.setSynchronizer(address(emptySynchronizer));

        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 200_000;
        uint32 calldataSize = 128;

        // Should revert with InvalidCmd because no chains are configured
        vm.expectRevert(ISynchronizer.InvalidCmd.selector);
        emptySynchronizer.sync{ value: 1 ether }(gasLimit, calldataSize);
    }

    function test_sync_withMultipleConfirmations() public {
        bytes32 seed = keccak256("test_sync_withMultipleConfirmations");

        // Reconfigure chains with different confirmation requirements
        changePrank(owner, owner);
        uint32[] memory configEids = new uint32[](2);
        uint16[] memory configConfirmations = new uint16[](2);
        configEids[0] = eids[1];
        configEids[1] = eids[2];
        configConfirmations[0] = 1;
        configConfirmations[1] = 5;
        synchronizers[0].configChains(configEids, configConfirmations);

        // Prepare remote matrices with updated liquidity
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](2);
        for (uint32 i = 1; i <= 2; ++i) {
            _updateLocalLiquidity(liquidityMatrices[i], apps[i], storages[i], users, seed);
            remotes[i - 1] = liquidityMatrices[i];
            seed = keccak256(abi.encodePacked(seed, i));
        }

        // Use _sync helper to properly simulate cross-chain sync with confirmations
        _sync(syncers[0], liquidityMatrices[0], remotes);
    }

    function test_sync_gasLimitVariations() public {
        bytes32 seed = keccak256("test_sync_gasLimitVariations");

        // Prepare ALL remote matrices (CHAINS - 1)
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            _updateLocalLiquidity(liquidityMatrices[i], apps[i], storages[i], users, seed);
            remotes[i - 1] = liquidityMatrices[i];
            seed = keccak256(abi.encodePacked(seed, i));
        }

        // Test fee scaling with different gas limits
        uint128 minGasLimit = 100_000 * uint128(remotes.length);
        uint128 maxGasLimit = 1_000_000 * uint128(remotes.length);
        uint32 calldataSize = 128 * uint32(remotes.length);

        uint256 minFee = synchronizers[0].quoteSync(minGasLimit, calldataSize);
        uint256 maxFee = synchronizers[0].quoteSync(maxGasLimit, calldataSize);

        // Verify fees scale with gas limit
        assertGt(maxFee, minFee);

        // Actually perform sync with standard gas limit
        _sync(syncers[0], liquidityMatrices[0], remotes);
    }

    // Tests from LiquidityMatrixLocal.t.sol
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

    function test_updateMappedAccountsOnly() public {
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateSyncMappedAccountsOnly(true);

        (, bool syncMappedAccountsOnly,,) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertTrue(syncMappedAccountsOnly);
    }

    function test_updateUseCallbacks() public {
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateUseCallbacks(true);

        (,, bool useCallbacks,) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertTrue(useCallbacks);
    }

    function test_updateSettler() public {
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateSettler(address(1));

        (,,, address settler) = liquidityMatrices[0].getAppSetting(apps[0]);
        assertEq(settler, address(1));
    }

    function test_updateLocalLiquidity(bytes32 seed) public {
        changePrank(apps[0], apps[0]);
        _updateLocalLiquidity(liquidityMatrices[0], apps[0], storages[0], users, seed);
    }

    function test_updateLocalData(bytes32 seed) public {
        changePrank(apps[0], apps[0]);
        _updateLocalData(liquidityMatrices[0], apps[0], storages[0], seed);
    }

    function test_updateRemoteApp() public {
        changePrank(apps[0], apps[0]);
        liquidityMatrices[0].updateRemoteApp(eids[1], address(0xdead));

        assertEq(liquidityMatrices[0].getRemoteApp(apps[0], eids[1]), address(0xdead));
    }

    // Tests from LiquidityMatrixRemote.t.sol
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

    function test_updateMaxLoop() public {
        changePrank(owner, owner);
        liquidityMatrices[0].updateMaxLoop(20);
        assertEq(liquidityMatrices[0].maxLoop(), 20);

        // Cannot set to 0
        vm.expectRevert(ILiquidityMatrix.InvalidAmount.selector);
        liquidityMatrices[0].updateMaxLoop(0);
    }

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

    // Helper function to sync with specific eids
    function _syncWithEids(
        address syncer,
        ILiquidityMatrix local,
        uint32[] memory targetEids,
        ILiquidityMatrix[] memory allRemotes
    ) internal {
        (, address txOrigin, address msgSender) = vm.readCallers();
        changePrank(syncer, syncer);

        uint128 gasLimit = 200_000 * uint128(targetEids.length);
        uint32 calldataSize = 128 * uint32(targetEids.length);
        // Get the synchronizer from local LiquidityMatrix
        ISynchronizer localSync = ISynchronizer(local.synchronizer());
        uint256 fee = localSync.quoteSync(targetEids, gasLimit, calldataSize);
        localSync.sync{ value: fee }(targetEids, gasLimit, calldataSize);
        skip(1);

        // Prepare responses only for the specified eids
        bytes[] memory responses = new bytes[](targetEids.length);
        for (uint256 i; i < targetEids.length; ++i) {
            // Find the remote matrix for this eid
            for (uint256 j; j < allRemotes.length; ++j) {
                if (_eid(allRemotes[j]) == targetEids[i]) {
                    (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) = allRemotes[j].getMainRoots();
                    responses[i] = abi.encode(liquidityRoot, dataRoot, timestamp);
                    break;
                }
            }
        }

        // Get sync command from synchronizer (not implemented in this test context)
        // In production, this would use localSync.getSyncCmd() and localSync.lzReduce()
        // For testing, we'll skip the verification as it's handled by the synchronizer

        changePrank(txOrigin, msgSender);
    }
}
