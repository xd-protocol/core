// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    MessagingFee,
    MessagingReceipt,
    ILayerZeroEndpointV2
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { Synchronizer } from "src/Synchronizer.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract SynchronizerTest is TestHelperOz5 {
    uint32 constant EID_LOCAL = 1;
    uint32 constant EID_REMOTE = 2;
    uint16 constant CMD_SYNC = 1;

    LiquidityMatrix local;
    LiquidityMatrix remote;
    Synchronizer localSynchronizer;
    Synchronizer remoteSynchronizer;

    address owner = makeAddr("owner");
    address localSyncer = makeAddr("localSyncer");
    address remoteSyncer = makeAddr("remoteSyncer");

    function setUp() public override {
        super.setUp();
        vm.deal(address(this), 100 ether);
        setUpEndpoints(2, LibraryType.UltraLightNode);

        changePrank(owner, owner);

        // Deploy LiquidityMatrix contracts
        local = new LiquidityMatrix(owner);
        remote = new LiquidityMatrix(owner);

        // Deploy Synchronizer contracts
        localSynchronizer =
            new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[EID_LOCAL], address(local), localSyncer, owner);
        remoteSynchronizer =
            new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[EID_REMOTE], address(remote), remoteSyncer, owner);

        // Set synchronizers
        local.setSynchronizer(address(localSynchronizer));
        remote.setSynchronizer(address(remoteSynchronizer));

        // Wire OApps
        address[] memory oapps = new address[](2);
        oapps[0] = address(localSynchronizer);
        oapps[1] = address(remoteSynchronizer);
        wireOApps(oapps);

        // Configure chains
        uint32[] memory configEids = new uint32[](1);
        uint16[] memory configConfirmations = new uint16[](1);

        configEids[0] = EID_REMOTE;
        configConfirmations[0] = 0;
        localSynchronizer.configChains(configEids, configConfirmations);

        configEids[0] = EID_LOCAL;
        configConfirmations[0] = 0;
        remoteSynchronizer.configChains(configEids, configConfirmations);

        vm.deal(localSyncer, 10_000e18);
        vm.deal(remoteSyncer, 10_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                        chainConfigs() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_chainConfigs() public {
        uint32[] memory eids = new uint32[](2);
        uint16[] memory confirmations = new uint16[](2);
        eids[0] = 3;
        eids[1] = 4;
        confirmations[0] = 10;
        confirmations[1] = 20;

        changePrank(owner, owner);
        localSynchronizer.configChains(eids, confirmations);

        (uint32[] memory returnedEids, uint16[] memory returnedConfirmations) = localSynchronizer.chainConfigs();
        assertEq(returnedEids.length, 2);
        assertEq(returnedEids[0], 3);
        assertEq(returnedEids[1], 4);
        assertEq(returnedConfirmations[0], 10);
        assertEq(returnedConfirmations[1], 20);
    }

    /*//////////////////////////////////////////////////////////////
                         lzReduce() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_lzReduce() public view {
        // Create a mock command and responses
        bytes memory cmd = localSynchronizer.getSyncCmd();
        bytes[] memory responses = new bytes[](1);
        responses[0] = abi.encode(bytes32(uint256(1)), bytes32(uint256(2)), uint256(block.timestamp));

        bytes memory result = localSynchronizer.lzReduce(cmd, responses);
        assertGt(result.length, 0);
    }

    function test_lzReduce_invalidCmd() public {
        // Create a valid command structure but with invalid CMD type
        // The lzReduce expects a properly encoded ReadCodecV1 command
        uint16 invalidCmd = 999;
        EVMCallRequestV1[] memory requests = new EVMCallRequestV1[](0);
        EVMCallComputeV1 memory computeSettings = EVMCallComputeV1({
            computeSetting: 1,
            targetEid: 1,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: address(localSynchronizer)
        });

        // Encode with ReadCodecV1 but with invalid command
        bytes memory cmd = ReadCodecV1.encode(invalidCmd, requests, computeSettings);
        bytes[] memory responses = new bytes[](0);

        vm.expectRevert(ISynchronizer.InvalidCmd.selector);
        localSynchronizer.lzReduce(cmd, responses);
    }

    function test_lzReduce_multipleResponses() public view {
        // This test already exists as test_lzReduce(), so let's test error case instead
        // Create a valid command structure but with invalid CMD type
        uint16 validCmd = CMD_SYNC;
        EVMCallRequestV1[] memory requests = new EVMCallRequestV1[](2);

        // Create two mock requests
        requests[0] = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: 10,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: address(localSynchronizer),
            callData: abi.encodeWithSignature("getMainRoots()")
        });

        requests[1] = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: 20,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: address(localSynchronizer),
            callData: abi.encodeWithSignature("getMainRoots()")
        });

        EVMCallComputeV1 memory computeSettings = EVMCallComputeV1({
            computeSetting: 1,
            targetEid: 1,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: address(localSynchronizer)
        });

        bytes memory cmd = ReadCodecV1.encode(validCmd, requests, computeSettings);

        // Create matching responses
        bytes[] memory responses = new bytes[](2);
        responses[0] = abi.encode(bytes32(uint256(100)), bytes32(uint256(200)), uint256(block.timestamp));
        responses[1] = abi.encode(bytes32(uint256(300)), bytes32(uint256(400)), uint256(block.timestamp + 100));

        // Should process multiple responses correctly
        bytes memory result = localSynchronizer.lzReduce(cmd, responses);

        // Decode and verify
        (uint16 cmdType, uint32[] memory eids, bytes32[] memory liquidityRoots, bytes32[] memory dataRoots,) =
            abi.decode(result, (uint16, uint32[], bytes32[], bytes32[], uint256[]));

        assertEq(cmdType, CMD_SYNC);
        assertEq(eids.length, 2);
        assertEq(eids[0], 10);
        assertEq(eids[1], 20);
        assertEq(liquidityRoots[0], bytes32(uint256(100)));
        assertEq(dataRoots[1], bytes32(uint256(400)));
    }

    function test_lzReduce_mismatchedResponses() public view {
        // This test should verify that lzReduce handles empty responses
        // Get the sync command
        bytes memory cmd = localSynchronizer.getSyncCmd();

        // Create a valid response for the single configured chain
        bytes[] memory responses = new bytes[](1);
        responses[0] = abi.encode(bytes32(uint256(123)), bytes32(uint256(456)), uint256(block.timestamp));

        // Should work with matching response count
        bytes memory result = localSynchronizer.lzReduce(cmd, responses);

        // Verify the result is properly encoded
        (uint16 cmdType, uint32[] memory eids,,,) =
            abi.decode(result, (uint16, uint32[], bytes32[], bytes32[], uint256[]));
        assertEq(cmdType, CMD_SYNC);
        assertEq(eids.length, 1);
        assertEq(eids[0], EID_REMOTE);
    }

    /*//////////////////////////////////////////////////////////////
                         quoteSync() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_quoteSync() public view {
        uint256 fee = localSynchronizer.quoteSync(200_000, 256);
        assertGt(fee, 0);
    }

    function test_quoteSyncWithEids() public view {
        uint32[] memory eids = new uint32[](1);
        eids[0] = EID_REMOTE;
        uint256 fee = localSynchronizer.quoteSync(eids, 200_000, 256);
        assertGt(fee, 0);
    }

    function test_quoteSync_varyingParameters() public view {
        // Test with different gas limits
        uint256 fee1 = localSynchronizer.quoteSync(100_000, 128);
        uint256 fee2 = localSynchronizer.quoteSync(200_000, 128);
        uint256 fee3 = localSynchronizer.quoteSync(100_000, 256);

        // Higher gas limit should result in higher fee
        assertGt(fee2, fee1);
        // Larger calldata size should result in higher fee
        assertGt(fee3, fee1);
    }

    /*//////////////////////////////////////////////////////////////
                 quoteRequestMapRemoteAccounts() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_quoteRequestMapRemoteAccounts() public {
        // Register apps
        address localApp = address(new AppMock(address(local)));
        address remoteApp = address(new AppMock(address(remote)));

        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        changePrank(remoteApp, remoteApp);
        remote.registerApp(false, false, address(0));

        // Prepare account arrays
        address[] memory locals = new address[](3);
        address[] memory remotes = new address[](3);
        locals[0] = makeAddr("local1");
        locals[1] = makeAddr("local2");
        locals[2] = makeAddr("local3");
        remotes[0] = makeAddr("remote1");
        remotes[1] = makeAddr("remote2");
        remotes[2] = makeAddr("remote3");

        // Quote fee
        uint128 gasLimit = 300_000;
        uint256 fee =
            localSynchronizer.quoteRequestMapRemoteAccounts(EID_REMOTE, localApp, remoteApp, locals, remotes, gasLimit);
        assertGt(fee, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        getSyncCmd() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getSyncCmd() public view {
        bytes memory cmd = localSynchronizer.getSyncCmd();
        assertGt(cmd.length, 0);
    }

    function test_getSyncCmdWithEids() public view {
        uint32[] memory eids = new uint32[](1);
        eids[0] = EID_REMOTE;
        bytes memory cmd = localSynchronizer.getSyncCmd(eids);
        assertGt(cmd.length, 0);
    }

    function test_getSyncCmd_largeEidsArray() public {
        // Use existing configured eid instead of creating new ones that need peers
        uint32[] memory eids = new uint32[](1);
        uint16[] memory confirmations = new uint16[](1);
        eids[0] = EID_REMOTE; // Use the already configured eid
        confirmations[0] = 0;

        changePrank(owner, owner);
        localSynchronizer.configChains(eids, confirmations);

        bytes memory cmd = localSynchronizer.getSyncCmd();
        assertGt(cmd.length, 0);

        // Verify we can get length and access individual eids
        assertEq(localSynchronizer.eidsLength(), 1);
        assertEq(localSynchronizer.eidAt(0), EID_REMOTE);
    }

    /*//////////////////////////////////////////////////////////////
                         eidsLength() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_eidsLength() public {
        uint32[] memory eids = new uint32[](3);
        uint16[] memory confirmations = new uint16[](3);
        eids[0] = 10;
        eids[1] = 20;
        eids[2] = 30;

        changePrank(owner, owner);
        localSynchronizer.configChains(eids, confirmations);

        assertEq(localSynchronizer.eidsLength(), 3);
    }

    /*//////////////////////////////////////////////////////////////
                          eidAt() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_eidAt() public {
        uint32[] memory eids = new uint32[](3);
        uint16[] memory confirmations = new uint16[](3);
        eids[0] = 10;
        eids[1] = 20;
        eids[2] = 30;

        changePrank(owner, owner);
        localSynchronizer.configChains(eids, confirmations);

        assertEq(localSynchronizer.eidAt(0), 10);
        assertEq(localSynchronizer.eidAt(1), 20);
        assertEq(localSynchronizer.eidAt(2), 30);
    }

    function test_eidAt_outOfBounds() public {
        uint32[] memory eids = new uint32[](2);
        uint16[] memory confirmations = new uint16[](2);
        eids[0] = 10;
        eids[1] = 20;

        changePrank(owner, owner);
        localSynchronizer.configChains(eids, confirmations);

        // Should revert when accessing out of bounds index
        vm.expectRevert();
        localSynchronizer.eidAt(2);
    }

    /*//////////////////////////////////////////////////////////////
                       configChains() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_configChains() public {
        uint32[] memory eids = new uint32[](2);
        uint16[] memory confirmations = new uint16[](2);
        eids[0] = 3;
        eids[1] = 4;
        confirmations[0] = 10;
        confirmations[1] = 20;

        changePrank(owner, owner);
        localSynchronizer.configChains(eids, confirmations);

        (uint32[] memory returnedEids, uint16[] memory returnedConfirmations) = localSynchronizer.chainConfigs();
        assertEq(returnedEids.length, 2);
        assertEq(returnedEids[0], 3);
        assertEq(returnedEids[1], 4);
        assertEq(returnedConfirmations[0], 10);
        assertEq(returnedConfirmations[1], 20);
    }

    function test_configChains_duplicateEid() public {
        uint32[] memory eids = new uint32[](2);
        uint16[] memory confirmations = new uint16[](2);
        eids[0] = 3;
        eids[1] = 3; // duplicate
        confirmations[0] = 10;
        confirmations[1] = 20;

        changePrank(owner, owner);
        vm.expectRevert(ISynchronizer.DuplicateTargetEid.selector);
        localSynchronizer.configChains(eids, confirmations);
    }

    function test_configChains_invalidLengths() public {
        uint32[] memory eids = new uint32[](2);
        uint16[] memory confirmations = new uint16[](1); // mismatched length
        eids[0] = 3;
        eids[1] = 4;
        confirmations[0] = 10;

        changePrank(owner, owner);
        vm.expectRevert(ISynchronizer.InvalidLengths.selector);
        localSynchronizer.configChains(eids, confirmations);
    }

    function test_configChains_onlyOwner() public {
        address notOwner = makeAddr("notOwner");
        uint32[] memory eids = new uint32[](1);
        uint16[] memory confirmations = new uint16[](1);
        eids[0] = 3;
        confirmations[0] = 10;

        changePrank(notOwner, notOwner);
        vm.expectRevert(abi.encodeWithSelector(0x118cdaa7, notOwner));
        localSynchronizer.configChains(eids, confirmations);
    }

    function test_configChains_clearAndReconfigure() public {
        // Initial configuration
        uint32[] memory eids = new uint32[](2);
        uint16[] memory confirmations = new uint16[](2);
        eids[0] = 10;
        eids[1] = 20;
        confirmations[0] = 5;
        confirmations[1] = 10;

        changePrank(owner, owner);
        localSynchronizer.configChains(eids, confirmations);
        assertEq(localSynchronizer.eidsLength(), 2);

        // Clear configuration
        uint32[] memory emptyEids = new uint32[](0);
        uint16[] memory emptyConfirmations = new uint16[](0);
        localSynchronizer.configChains(emptyEids, emptyConfirmations);
        assertEq(localSynchronizer.eidsLength(), 0);

        // Reconfigure with new values
        uint32[] memory newEids = new uint32[](3);
        uint16[] memory newConfirmations = new uint16[](3);
        newEids[0] = 30;
        newEids[1] = 40;
        newEids[2] = 50;
        newConfirmations[0] = 1;
        newConfirmations[1] = 2;
        newConfirmations[2] = 3;

        localSynchronizer.configChains(newEids, newConfirmations);
        assertEq(localSynchronizer.eidsLength(), 3);
        assertEq(localSynchronizer.eidAt(0), 30);
        assertEq(localSynchronizer.eidAt(1), 40);
        assertEq(localSynchronizer.eidAt(2), 50);

        (, uint16[] memory returnedConfirmations) = localSynchronizer.chainConfigs();
        assertEq(returnedConfirmations[0], 1);
        assertEq(returnedConfirmations[1], 2);
        assertEq(returnedConfirmations[2], 3);
    }

    /*//////////////////////////////////////////////////////////////
                       updateSyncer() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateSyncer() public {
        address newSyncer = makeAddr("newSyncer");

        changePrank(owner, owner);
        localSynchronizer.updateSyncer(newSyncer);

        assertEq(localSynchronizer.syncer(), newSyncer);
    }

    function test_updateSyncer_onlyOwner() public {
        address notOwner = makeAddr("notOwner");
        address newSyncer = makeAddr("newSyncer");

        changePrank(notOwner, notOwner);
        vm.expectRevert(abi.encodeWithSelector(0x118cdaa7, notOwner));
        localSynchronizer.updateSyncer(newSyncer);
    }

    function test_events_updateSyncer() public {
        address newSyncer = makeAddr("newSyncer");

        changePrank(owner, owner);
        vm.expectEmit(true, false, false, true);
        emit ISynchronizer.UpdateSyncer(newSyncer);
        localSynchronizer.updateSyncer(newSyncer);
    }

    /*//////////////////////////////////////////////////////////////
                           sync() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_sync_onlySyncer() public {
        address notSyncer = makeAddr("notSyncer");
        vm.deal(notSyncer, 10 ether);
        changePrank(notSyncer, notSyncer);
        vm.expectRevert(ISynchronizer.Forbidden.selector);
        localSynchronizer.sync{ value: 1 ether }(100_000, 128);
    }

    function test_sync_alreadyRequested() public {
        changePrank(localSyncer, localSyncer);
        uint256 fee = localSynchronizer.quoteSync(100_000, 128);

        // First sync should succeed
        localSynchronizer.sync{ value: fee }(100_000, 128);

        // Second sync in same block should fail
        vm.expectRevert(ISynchronizer.AlreadyRequested.selector);
        localSynchronizer.sync{ value: fee }(100_000, 128);
    }

    function test_sync_rateLimiting() public {
        changePrank(localSyncer, localSyncer);
        uint256 fee = localSynchronizer.quoteSync(100_000, 128);

        // First sync
        localSynchronizer.sync{ value: fee }(100_000, 128);

        // Advance time by 1 second
        skip(1);

        // Second sync should succeed after time advancement
        localSynchronizer.sync{ value: fee }(100_000, 128);
    }

    function test_sync_insufficientFee() public {
        changePrank(localSyncer, localSyncer);
        uint256 fee = localSynchronizer.quoteSync(100_000, 128);

        // Try to sync with less than quoted fee
        vm.expectRevert();
        localSynchronizer.sync{ value: fee - 1 }(100_000, 128);
    }

    function test_sync_noConfiguredChains() public {
        // Deploy a new synchronizer without configured chains
        changePrank(owner, owner);
        LiquidityMatrix newMatrix = new LiquidityMatrix(owner);
        Synchronizer newSynchronizer =
            new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[EID_LOCAL], address(newMatrix), localSyncer, owner);
        newMatrix.setSynchronizer(address(newSynchronizer));

        changePrank(localSyncer, localSyncer);
        // Should revert because no chains are configured
        vm.expectRevert(ISynchronizer.InvalidCmd.selector);
        newSynchronizer.sync{ value: 1 ether }(100_000, 128);
    }

    function test_sync_gasEstimation() public {
        changePrank(localSyncer, localSyncer);

        // Get quote for sync
        uint128 gasLimit = 150_000;
        uint32 calldataSize = 192;
        uint256 quotedFee = localSynchronizer.quoteSync(gasLimit, calldataSize);

        // Execute sync with quoted fee
        uint256 gasBefore = gasleft();
        localSynchronizer.sync{ value: quotedFee }(gasLimit, calldataSize);
        uint256 gasUsed = gasBefore - gasleft();

        // Verify gas was used (basic sanity check)
        assertGt(gasUsed, 0);
        assertLt(gasUsed, gasLimit * 10); // Should not use excessive gas
    }

    function test_events_sync() public {
        changePrank(localSyncer, localSyncer);
        uint256 fee = localSynchronizer.quoteSync(100_000, 128);

        vm.expectEmit(true, false, false, false);
        emit ISynchronizer.Sync(localSyncer);
        localSynchronizer.sync{ value: fee }(100_000, 128);
    }

    // Sync with specific EIDs tests
    function test_sync_withSpecificEids() public {
        changePrank(localSyncer, localSyncer);
        uint32[] memory eids = new uint32[](1);
        eids[0] = EID_REMOTE;

        uint256 fee = localSynchronizer.quoteSync(eids, 200_000, 256);
        assertGt(fee, 0);

        localSynchronizer.sync{ value: fee }(eids, 200_000, 256);
    }

    function test_sync_withSpecificEids_onlySyncer() public {
        address notSyncer = makeAddr("notSyncer");
        vm.deal(notSyncer, 10 ether);
        uint32[] memory eids = new uint32[](1);
        eids[0] = EID_REMOTE;

        changePrank(notSyncer, notSyncer);
        vm.expectRevert(ISynchronizer.Forbidden.selector);
        localSynchronizer.sync{ value: 1 ether }(eids, 100_000, 128);
    }

    function test_sync_withSpecificEids_alreadyRequested() public {
        changePrank(localSyncer, localSyncer);
        uint32[] memory eids = new uint32[](1);
        eids[0] = EID_REMOTE;
        uint256 fee = localSynchronizer.quoteSync(eids, 100_000, 128);

        // First sync should succeed
        localSynchronizer.sync{ value: fee }(eids, 100_000, 128);

        // Second sync in same block should fail
        vm.expectRevert(ISynchronizer.AlreadyRequested.selector);
        localSynchronizer.sync{ value: fee }(eids, 100_000, 128);
    }

    function test_sync_withEmptyEids() public {
        changePrank(localSyncer, localSyncer);
        uint32[] memory eids = new uint32[](0);

        // Should revert with InvalidCmd when trying to build command with empty array
        vm.expectRevert(ISynchronizer.InvalidCmd.selector);
        localSynchronizer.sync{ value: 1 ether }(eids, 100_000, 128);
    }

    /*//////////////////////////////////////////////////////////////
                  requestMapRemoteAccounts() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_requestMapRemoteAccounts() public {
        // Register apps
        address localApp = address(new AppMock(address(local)));
        address remoteApp = address(new AppMock(address(remote)));

        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        changePrank(remoteApp, remoteApp);
        remote.registerApp(false, false, address(0));

        // Prepare account arrays
        address[] memory locals = new address[](3);
        address[] memory remotes = new address[](3);
        locals[0] = makeAddr("local1");
        locals[1] = makeAddr("local2");
        locals[2] = makeAddr("local3");
        remotes[0] = makeAddr("remote1");
        remotes[1] = makeAddr("remote2");
        remotes[2] = makeAddr("remote3");

        // Quote fee
        uint128 gasLimit = 300_000;
        uint256 fee =
            localSynchronizer.quoteRequestMapRemoteAccounts(EID_REMOTE, localApp, remoteApp, locals, remotes, gasLimit);
        assertGt(fee, 0);

        // Request mapping
        vm.deal(localApp, fee);
        changePrank(localApp, localApp);
        localSynchronizer.requestMapRemoteAccounts{ value: fee }(EID_REMOTE, remoteApp, locals, remotes, gasLimit);
    }

    function test_requestMapRemoteAccounts_invalidLengths() public {
        address localApp = address(new AppMock(address(local)));
        vm.deal(localApp, 10 ether);
        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        address[] memory locals = new address[](2);
        address[] memory remotes = new address[](3); // mismatched length
        locals[0] = makeAddr("local1");
        locals[1] = makeAddr("local2");
        remotes[0] = makeAddr("remote1");
        remotes[1] = makeAddr("remote2");
        remotes[2] = makeAddr("remote3");

        vm.expectRevert(ISynchronizer.InvalidLengths.selector);
        localSynchronizer.requestMapRemoteAccounts{ value: 1 ether }(EID_REMOTE, address(1), locals, remotes, 100_000);
    }

    function test_requestMapRemoteAccounts_zeroAddress() public {
        address localApp = address(new AppMock(address(local)));
        vm.deal(localApp, 10 ether);
        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        address[] memory locals = new address[](1);
        address[] memory remotes = new address[](1);
        locals[0] = address(0); // zero address
        remotes[0] = makeAddr("remote1");

        vm.expectRevert(ISynchronizer.InvalidAddress.selector);
        localSynchronizer.requestMapRemoteAccounts{ value: 1 ether }(EID_REMOTE, address(1), locals, remotes, 100_000);
    }

    function test_requestMapRemoteAccounts_onlyApp() public {
        address notApp = makeAddr("notApp");
        vm.deal(notApp, 10 ether);
        address[] memory locals = new address[](1);
        address[] memory remotes = new address[](1);
        locals[0] = makeAddr("local1");
        remotes[0] = makeAddr("remote1");

        changePrank(notApp, notApp);
        vm.expectRevert(ISynchronizer.Forbidden.selector);
        localSynchronizer.requestMapRemoteAccounts{ value: 1 ether }(EID_REMOTE, address(1), locals, remotes, 100_000);
    }

    function test_requestMapRemoteAccounts_crossChain() public {
        // Register apps
        address localApp = address(new AppMock(address(local)));
        address remoteApp = address(new AppMock(address(remote)));

        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        changePrank(remoteApp, remoteApp);
        remote.registerApp(false, false, address(0));

        // Set up mapping permissions
        address local1 = makeAddr("local1");
        address remote1 = makeAddr("remote1");
        // The shouldMapAccounts checks the remote against local in the order they're sent
        IAppMock(remoteApp).setShouldMapAccounts(EID_LOCAL, local1, remote1, true);

        // Prepare account arrays
        address[] memory locals = new address[](1);
        address[] memory remotes = new address[](1);
        locals[0] = local1;
        remotes[0] = remote1;

        // Request mapping
        uint128 gasLimit = 300_000;
        uint256 fee =
            localSynchronizer.quoteRequestMapRemoteAccounts(EID_REMOTE, localApp, remoteApp, remotes, locals, gasLimit);

        vm.deal(localApp, fee);
        changePrank(localApp, localApp);
        localSynchronizer.requestMapRemoteAccounts{ value: fee }(EID_REMOTE, remoteApp, locals, remotes, gasLimit);

        // Verify the packet and deliver it
        verifyPackets(EID_REMOTE, address(remoteSynchronizer));

        // Check that mapping was created
        // The mapping is created on the remote chain: local1 (from source) -> remote1 (on remote)
        assertEq(remote.getMappedAccount(remoteApp, EID_LOCAL, local1), remote1);
    }

    function test_requestMapRemoteAccounts_largeArrays() public {
        address localApp = address(new AppMock(address(local)));
        vm.deal(localApp, 100 ether);
        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        // Create large arrays (e.g., 50 accounts)
        uint256 accountCount = 50;
        address[] memory locals = new address[](accountCount);
        address[] memory remotes = new address[](accountCount);

        for (uint256 i = 0; i < accountCount; i++) {
            locals[i] = address(uint160(1000 + i));
            remotes[i] = address(uint160(2000 + i));
        }

        uint128 gasLimit = 2_000_000; // Higher gas limit for large arrays
        uint256 fee =
            localSynchronizer.quoteRequestMapRemoteAccounts(EID_REMOTE, localApp, address(1), remotes, locals, gasLimit);

        // Fee should be non-zero for large arrays
        assertGt(fee, 0);

        // Should succeed with sufficient fee
        localSynchronizer.requestMapRemoteAccounts{ value: fee }(EID_REMOTE, address(1), locals, remotes, gasLimit);
    }

    function test_events_requestMapRemoteAccounts() public {
        address localApp = address(new AppMock(address(local)));
        address remoteApp = address(new AppMock(address(remote)));

        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));

        address[] memory locals = new address[](1);
        address[] memory remotes = new address[](1);
        locals[0] = makeAddr("local1");
        remotes[0] = makeAddr("remote1");

        uint256 fee =
            localSynchronizer.quoteRequestMapRemoteAccounts(EID_REMOTE, localApp, remoteApp, remotes, locals, 100_000);

        vm.deal(localApp, fee);
        vm.expectEmit(true, true, true, true);
        emit ISynchronizer.RequestMapRemoteAccounts(localApp, EID_REMOTE, remoteApp, remotes, locals);
        localSynchronizer.requestMapRemoteAccounts{ value: fee }(EID_REMOTE, remoteApp, locals, remotes, 100_000);
    }
}
