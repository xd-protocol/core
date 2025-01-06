// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ArrayLib } from "../libraries/ArrayLib.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { SynchronizerRemote } from "./SynchronizerRemote.sol";

/**
 * @title SynchronizerRemoteBatched
 * @dev Extends SynchronizerRemote with batch processing for liquidity and data settlements.
 * This contract allows applications to group liquidity and data updates into batches for efficient
 * Merkle tree generation and root verification.
 *
 * # Workflow:
 * 1. **Batch Creation**:
 *    - A batch is created using `createLiquidityBatch` or `createDataBatch`.
 *    - These functions initialize a new batch with a unique ID and populate the associated Merkle tree.
 *
 * 2. **Appending to BatchedRemoteState**:
 *    - Additional accounts/liquidity or keys/values can be appended to an existing batch using
 *      `submitLiquidity` or `submitData`.
 *
 * 3. **Batch Settlement**:
 *    - A batch is settled by verifying the associated Merkle proof and updating the application state.
 *    - Settlement finalizes the batch, preventing further modifications.
 *
 * # State Tracking:
 * - BatchedRemoteStates are tracked per application and chain (`eid`), ensuring isolated state management.
 * - Each batch has its own Merkle tree (`liquidityTree`, `dataHashTree`).
 */
abstract contract SynchronizerRemoteBatched is SynchronizerRemote {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    struct BatchedRemoteState {
        mapping(uint256 batchId => LiquidityBatch) liquidity;
        mapping(uint256 batchId => MerkleTreeLib.Tree) liquidityTree;
        uint256 lastLiquidityBatchId;
        mapping(uint256 batchId => DataBatch) data;
        mapping(uint256 batchId => MerkleTreeLib.Tree) dataHashTree;
        uint256 lastDataBatchId;
    }

    struct LiquidityBatch {
        address submitter;
        uint256 timestamp;
        address[] accounts;
        int256[] liquidity;
    }

    struct DataBatch {
        address submitter;
        uint256 timestamp;
        bytes32[] keys;
        bytes[] values;
    }
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address app => mapping(uint32 eid => BatchedRemoteState)) internal _batchedStates;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CreateLiquidityBatch(address indexed app, uint32 indexed eid, address submitter, uint256 indexed batchId);
    event CreateDataBatch(address indexed app, uint32 indexed eid, address submitter, uint256 indexed batchId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function liquidityBatchRoot(address app, uint32 eid, uint256 batchId) external view returns (bytes32) {
        return _batchedStates[app][eid].liquidityTree[batchId].root;
    }

    function lastLiquidityBatchId(address app, uint32 eid) external view returns (uint256) {
        return _batchedStates[app][eid].lastLiquidityBatchId;
    }

    function dataBatchRoot(address app, uint32 eid, uint256 batchId) external view returns (bytes32) {
        return _batchedStates[app][eid].dataHashTree[batchId].root;
    }

    function lastDataBatchId(address app, uint32 eid) external view returns (uint256) {
        return _batchedStates[app][eid].lastDataBatchId;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new batch for liquidity settlement with a unique batch ID.
     * @param app The address of the application on the current chain.
     * @param eid The endpoint ID of the remote chain.
     * @param timestamp The timestamp of the root.
     * @param accounts The array of accounts to include in the batch.
     * @param liquidity The array of liquidity values corresponding to the accounts.
     *
     * Requirements:
     * - The `accounts` and `liquidity` arrays must have the same length.
     * - The caller must be a registered application.
     */
    function createLiquidityBatch(
        address app,
        uint32 eid,
        uint256 timestamp,
        address[] calldata accounts,
        int256[] calldata liquidity
    ) external onlyApp(app) {
        if (accounts.length != liquidity.length) revert InvalidLengths();

        BatchedRemoteState storage state = _batchedStates[app][eid];
        uint256 id = state.lastLiquidityBatchId;
        state.liquidity[id] = LiquidityBatch(msg.sender, timestamp, accounts, liquidity);
        state.liquidityTree[id].initialize();
        state.lastLiquidityBatchId = id + 1;

        for (uint256 i; i < accounts.length; ++i) {
            (address account, int256 _liquidity) = (accounts[i], liquidity[i]);
            state.liquidityTree[id].update(bytes32(uint256(uint160(account))), bytes32(uint256(_liquidity)));
        }

        emit CreateLiquidityBatch(app, eid, msg.sender, id);
    }

    /**
     * @notice Adds additional accounts and liquidity to an existing liquidity batch.
     * @param app The address of the application on the current chain.
     * @param eid The endpoint ID of the remote chain.
     * @param batchId The ID of the batch to append to.
     * @param accounts The array of accounts to append to the batch.
     * @param liquidity The array of liquidity values to append to the batch.
     *
     * Requirements:
     * - The `accounts` and `liquidity` arrays must have the same length.
     * - The caller must be the original submitter of the batch.
     */
    function submitLiquidity(
        address app,
        uint32 eid,
        uint256 batchId,
        address[] memory accounts,
        int256[] memory liquidity
    ) external onlyApp(app) {
        if (accounts.length != liquidity.length) revert InvalidLengths();

        BatchedRemoteState storage state = _batchedStates[app][eid];
        LiquidityBatch storage batch = state.liquidity[batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        for (uint256 i; i < accounts.length; ++i) {
            (address account, int256 _liquidity) = (accounts[i], liquidity[i]);
            batch.accounts.push(accounts[i]);
            batch.liquidity.push(liquidity[i]);
            state.liquidityTree[batchId].update(bytes32(uint256(uint160(account))), bytes32(uint256(_liquidity)));
        }
    }

    /**
     * @notice Settles liquidity states for an application using data from an existing batch and verifies the Merkle proof.
     * @param app The address of the application on the current chain.
     * @param eid The endpoint ID of the remote chain.
     * @param batchId The ID of the batch to settle.
     * @param mainTreeIndex the index of app in the main liquidity tree on the remote chain.
     * @param mainTreeProof The proof array to verify the sub-root within the top tree.
     *
     * Requirements:
     * - The caller must be the original submitter of the batch.
     */
    function settleLiquidityBatched(
        address app,
        uint32 eid,
        uint256 batchId,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof
    ) external nonReentrant onlyApp(app) {
        BatchedRemoteState storage state = _batchedStates[app][eid];
        LiquidityBatch memory batch = state.liquidity[batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        bytes32 mainRoot = liquidityRoots[eid][batch.timestamp];
        _verifyRoot(
            _getRemoteAppOrRevert(app, eid), state.liquidityTree[batchId].root, mainTreeIndex, mainTreeProof, mainRoot
        );
        _settleLiquidity(SettleLiquidityParams(app, eid, mainRoot, batch.timestamp, batch.accounts, batch.liquidity));
    }

    /**
     * @notice Creates a new batch for data settlement with a unique batch ID.
     * @param app The address of the application on the current chain.
     * @param eid The endpoint ID of the remote chain.
     * @param timestamp The timestamp of the root.
     * @param keys The array of keys to include in the batch.
     * @param values The array of data values corresponding to the keys.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     * - The caller must be a registered application.
     */
    function createDataBatch(
        address app,
        uint32 eid,
        uint256 timestamp,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external onlyApp(app) {
        if (keys.length != values.length) revert InvalidLengths();

        BatchedRemoteState storage state = _batchedStates[app][eid];
        uint256 id = state.lastDataBatchId;
        state.data[id] = DataBatch(msg.sender, timestamp, keys, values);
        state.dataHashTree[id].initialize();
        state.lastDataBatchId = id + 1;

        for (uint256 i; i < keys.length; ++i) {
            (bytes32 key, bytes memory value) = (keys[i], values[i]);
            state.dataHashTree[id].update(key, keccak256(value));
        }

        emit CreateDataBatch(app, eid, msg.sender, id);
    }

    /**
     * @notice Adds additional keys and values to an existing data batch.
     * @param app The address of the application on the current chain.
     * @param eid The endpoint ID of the remote chain.
     * @param batchId The ID of the batch to append to.
     * @param keys The array of keys to append to the batch.
     * @param values The array of data values to append to the batch.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     * - The caller must be the original submitter of the batch.
     */
    function submitData(address app, uint32 eid, uint256 batchId, bytes32[] memory keys, bytes[] memory values)
        external
        onlyApp(app)
    {
        if (keys.length != values.length) revert InvalidLengths();

        BatchedRemoteState storage state = _batchedStates[app][eid];
        DataBatch storage batch = state.data[batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        for (uint256 i; i < keys.length; ++i) {
            (bytes32 key, bytes memory value) = (keys[i], values[i]);
            batch.keys.push(key);
            batch.values.push(value);
            state.dataHashTree[batchId].update(key, keccak256(value));
        }
    }

    /**
     * @notice Settles data states for an application using data from an existing batch and verifies the Merkle proof.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application on the current chain.
     * @param batchId The ID of the batch to settle.
     * @param mainTreeIndex the index of app in the main data tree on the remote chain.
     * @param mainTreeProof The proof array to verify the sub-root within the top tree.
     *
     * Requirements:
     * - The caller must be the original submitter of the batch.
     */
    function settleDataBatched(
        address app,
        uint32 eid,
        uint256 batchId,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof
    ) external nonReentrant onlyApp(app) {
        BatchedRemoteState storage state = _batchedStates[app][eid];
        DataBatch memory batch = state.data[batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        bytes32 mainRoot = dataRoots[eid][batch.timestamp];
        _verifyRoot(
            _getRemoteAppOrRevert(app, eid), state.dataHashTree[batchId].root, mainTreeIndex, mainTreeProof, mainRoot
        );
        _settleData(SettleDataParams(app, eid, mainRoot, batch.timestamp, batch.keys, batch.values));
    }

    function _verifyRoot(
        address app,
        bytes32 appRoot,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        bytes32 mainTreeRoot
    ) internal {
        if (mainTreeRoot == bytes32(0)) revert RootNotReceived();

        // Construct the Merkle tree and verify mainTreeRoot
        bool valid = MerkleTreeLib.verifyProof(
            bytes32(uint256(uint160(app))), appRoot, mainTreeIndex, mainTreeProof, mainTreeRoot
        );
        if (!valid) revert InvalidRoot();

        emit VerifyRoot(app, mainTreeRoot);
    }
}
