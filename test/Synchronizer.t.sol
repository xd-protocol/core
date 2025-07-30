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

    function test_updateSyncer() public {
        address newSyncer = makeAddr("newSyncer");

        changePrank(owner, owner);
        localSynchronizer.updateSyncer(newSyncer);

        assertEq(localSynchronizer.syncer(), newSyncer);
    }

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

    // Account mapping tests
    function test_requestMapRemoteAccounts() public {
        // Register apps
        address localApp = address(new AppMock(address(local)));
        address remoteApp = address(new AppMock(address(remote)));

        changePrank(localApp, localApp);
        local.registerApp(false, false, address(0));
        local.updateRemoteApp(EID_REMOTE, remoteApp);

        changePrank(remoteApp, remoteApp);
        remote.registerApp(false, false, address(0));
        remote.updateRemoteApp(EID_LOCAL, localApp);

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
}
