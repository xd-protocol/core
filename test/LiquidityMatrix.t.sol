// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ArrayLib } from "src/libraries/ArrayLib.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { LiquidityMatrixTestHelper } from "./helpers/LiquidityMatrixTestHelper.sol";

contract LiquidityMatrixTest is LiquidityMatrixTestHelper {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    uint8 public constant CHAINS = 16;

    uint32[CHAINS] eids;
    address[CHAINS] syncers;
    ILiquidityMatrix[CHAINS] liquidityMatrices;
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
            liquidityMatrices[i] = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[eids[i]], syncers[i], owner);
            oapps[i] = address(liquidityMatrices[i]);
            apps[i] = address(new AppMock(address(liquidityMatrices[i])));
        }

        wireOApps(address[](oapps));

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
            liquidityMatrices[i].configChains(configEids, configConfirmations);
            initialize(storages[i]);
        }

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
        uint32[] memory targetEids = new uint32[](3);
        targetEids[0] = eids[1];
        targetEids[1] = eids[3];
        targetEids[2] = eids[5];
        
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
        
        vm.expectRevert(LiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].sync{value: 1 ether}(targetEids, gasLimit, calldataSize);
    }
    
    function test_sync_withSpecificEids_alreadyRequested() public {
        uint32[] memory targetEids = new uint32[](2);
        targetEids[0] = eids[1];
        targetEids[1] = eids[2];
        
        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 400_000;
        uint32 calldataSize = 256;
        uint256 fee = liquidityMatrices[0].quoteSync(targetEids, gasLimit, calldataSize);
        
        // First sync should succeed
        liquidityMatrices[0].sync{value: fee}(targetEids, gasLimit, calldataSize);
        
        // Second sync in same block should fail
        vm.expectRevert(LiquidityMatrix.AlreadyRequested.selector);
        liquidityMatrices[0].sync{value: fee}(targetEids, gasLimit, calldataSize);
        
        // After time passes, sync should succeed again
        skip(1);
        liquidityMatrices[0].sync{value: fee}(targetEids, gasLimit, calldataSize);
    }
    
    function test_sync_withSpecificEids_insufficientFee() public {
        uint32[] memory targetEids = new uint32[](3);
        targetEids[0] = eids[2];
        targetEids[1] = eids[4];
        targetEids[2] = eids[6];
        
        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 600_000;
        uint32 calldataSize = 384;
        uint256 fee = liquidityMatrices[0].quoteSync(targetEids, gasLimit, calldataSize);
        
        // Try to sync with insufficient fee
        vm.expectRevert();
        liquidityMatrices[0].sync{value: fee - 1}(targetEids, gasLimit, calldataSize);
    }
    
    function test_sync_withSpecificEids_emptyArray() public {
        uint32[] memory targetEids = new uint32[](0);
        
        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 200_000;
        uint32 calldataSize = 128;
        
        // Empty array might be rejected by LayerZero codec, expecting InvalidCmd
        vm.expectRevert(LiquidityMatrix.InvalidCmd.selector);
        liquidityMatrices[0].sync{value: 1 ether}(targetEids, gasLimit, calldataSize);
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
        
        vm.expectRevert(LiquidityMatrix.Forbidden.selector);
        liquidityMatrices[0].sync{value: 1 ether}(gasLimit, calldataSize);
    }
    
    function test_sync_alreadyRequested() public {
        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 400_000;
        uint32 calldataSize = 256;
        uint256 fee = liquidityMatrices[0].quoteSync(gasLimit, calldataSize);
        
        // First sync should succeed
        liquidityMatrices[0].sync{value: fee}(gasLimit, calldataSize);
        
        // Second sync in same block should fail
        vm.expectRevert(LiquidityMatrix.AlreadyRequested.selector);
        liquidityMatrices[0].sync{value: fee}(gasLimit, calldataSize);
        
        // After time passes, sync should succeed again
        skip(1);
        liquidityMatrices[0].sync{value: fee}(gasLimit, calldataSize);
    }
    
    function test_sync_insufficientFee() public {
        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 600_000;
        uint32 calldataSize = 384;
        uint256 fee = liquidityMatrices[0].quoteSync(gasLimit, calldataSize);
        
        // Try to sync with insufficient fee
        vm.expectRevert();
        liquidityMatrices[0].sync{value: fee - 1}(gasLimit, calldataSize);
    }
    
    function test_sync_withNoConfiguredChains() public {
        // Deploy a new LiquidityMatrix without configured chains
        LiquidityMatrix emptyMatrix = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[1], syncers[0], owner);
        
        changePrank(syncers[0], syncers[0]);
        uint128 gasLimit = 200_000;
        uint32 calldataSize = 128;
        
        // Should revert with InvalidCmd because no chains are configured
        vm.expectRevert(LiquidityMatrix.InvalidCmd.selector);
        emptyMatrix.sync{value: 1 ether}(gasLimit, calldataSize);
    }
    
    function test_sync_withMultipleConfirmations() public {
        bytes32 seed = keccak256("test_sync_withMultipleConfirmations");
        
        // Reconfigure chains with different confirmation requirements
        changePrank(owner, owner);
        uint32[] memory configEids = new uint32[](3);
        uint16[] memory configConfirmations = new uint16[](3);
        configEids[0] = eids[1];
        configEids[1] = eids[2];
        configEids[2] = eids[3];
        configConfirmations[0] = 1;
        configConfirmations[1] = 5;
        configConfirmations[2] = 10;
        liquidityMatrices[0].configChains(configEids, configConfirmations);
        
        // Prepare remote matrices with updated liquidity
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](3);
        for (uint32 i = 1; i <= 3; ++i) {
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
        
        uint256 minFee = liquidityMatrices[0].quoteSync(minGasLimit, calldataSize);
        uint256 maxFee = liquidityMatrices[0].quoteSync(maxGasLimit, calldataSize);
        
        // Verify fees scale with gas limit
        assertGt(maxFee, minFee);
        
        // Actually perform sync with standard gas limit
        _sync(syncers[0], liquidityMatrices[0], remotes);
    }
    
    // Helper function to sync with specific eids
    function _syncWithEids(address syncer, ILiquidityMatrix local, uint32[] memory targetEids, ILiquidityMatrix[] memory allRemotes)
        internal
    {
        (, address txOrigin, address msgSender) = vm.readCallers();
        changePrank(syncer, syncer);
        
        uint128 gasLimit = 200_000 * uint128(targetEids.length);
        uint32 calldataSize = 128 * uint32(targetEids.length);
        uint256 fee = local.quoteSync(targetEids, gasLimit, calldataSize);
        local.sync{ value: fee }(targetEids, gasLimit, calldataSize);
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
        
        bytes memory payload = local.lzReduce(local.getSyncCmd(targetEids), responses);
        verifyPackets(_eid(local), bytes32(uint256(uint160(address(local)))), 0, address(0), payload);
        
        changePrank(txOrigin, msgSender);
    }
}
