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
 * 2. **Appending to Batches**:
 *    - Additional accounts/liquidity or keys/values can be appended to an existing batch using
 *      `submitLiquidity` or `submitDataBatch`.
 *
 * 3. **Batch Settlement**:
 *    - A batch is settled by verifying the associated Merkle proof and updating the application state.
 *    - Settlement finalizes the batch, preventing further modifications.
 *
 * # State Tracking:
 * - Batches are tracked per application and chain (`eid`), ensuring isolated state management.
 * - Each batch has its own Merkle tree (`liquidityTree`, `dataHashTree`).
 */
abstract contract SynchronizerRemoteBatched is SynchronizerRemote {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    struct Batches {
        mapping(uint256 batchId => LiquidityBatch) liquidity;
        mapping(uint256 batchId => MerkleTreeLib.Tree) liquidityTree;
        uint256 lastLiquidityBatchId;
        mapping(uint256 batchId => DataBatch) data;
        mapping(uint256 batchId => MerkleTreeLib.Tree) dataHashTree;
        uint256 lastDataBatchId;
    }

    struct LiquidityBatch {
        address submitter;
        address[] accounts;
        int256[] liquidity;
    }

    struct DataBatch {
        address submitter;
        bytes32[] keys;
        bytes[] values;
    }
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address app => mapping(uint32 eid => Batches)) internal _batches;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CreateLiquidityBatch(uint32 indexed eid, address indexed app, address submitter, uint256 indexed batchId);
    event CreateDataBatch(uint32 indexed eid, address indexed app, address submitter, uint256 indexed batchId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new batch for liquidity settlement with a unique batch ID.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param accounts The array of accounts to include in the batch.
     * @param liquidity The array of liquidity values corresponding to the accounts.
     *
     * Requirements:
     * - The `accounts` and `liquidity` arrays must have the same length.
     * - The caller must be a registered application.
     */
    function createLiquidityBatch(uint32 eid, address app, address[] calldata accounts, int256[] calldata liquidity)
        external
        onlyApp(app)
    {
        if (accounts.length != liquidity.length) revert InvalidLengths();

        Batches storage b = _batches[app][eid];
        uint256 id = b.lastLiquidityBatchId;
        b.liquidity[id] = LiquidityBatch(msg.sender, accounts, liquidity);
        b.liquidityTree[id].initialize();
        b.lastLiquidityBatchId = id + 1;

        for (uint256 i; i < accounts.length; ++i) {
            (address account, int256 _liquidity) = (accounts[i], liquidity[i]);
            b.liquidityTree[id].update(bytes32(uint256(uint160(account))), bytes32(uint256(_liquidity)));
        }

        emit CreateLiquidityBatch(eid, app, msg.sender, id);
    }

    /**
     * @notice Adds additional accounts and liquidity to an existing liquidity batch.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param batchId The ID of the batch to append to.
     * @param accounts The array of accounts to append to the batch.
     * @param liquidity The array of liquidity values to append to the batch.
     *
     * Requirements:
     * - The `accounts` and `liquidity` arrays must have the same length.
     * - The caller must be the original submitter of the batch.
     */
    function submitLiquidity(
        uint32 eid,
        address app,
        uint256 batchId,
        address[] memory accounts,
        int256[] memory liquidity
    ) external onlyApp(app) {
        if (accounts.length != liquidity.length) revert InvalidLengths();

        Batches storage b = _batches[app][eid];
        LiquidityBatch storage batch = b.liquidity[batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        for (uint256 i; i < accounts.length; ++i) {
            (address account, int256 _liquidity) = (accounts[i], liquidity[i]);
            batch.accounts.push(accounts[i]);
            batch.liquidity.push(liquidity[i]);
            b.liquidityTree[batchId].update(bytes32(uint256(uint160(account))), bytes32(uint256(_liquidity)));
        }
    }

    /**
     * @notice Settles liquidity states for an application using data from an existing batch and verifies the Merkle proof.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param appIndex the index of app in the liquidity tree on the remote chain.
     * @param proof The proof array to verify the sub-root within the top tree.
     * @param batchId The ID of the batch to settle.
     *
     * Requirements:
     * - The caller must be the original submitter of the batch.
     */
    function settleLiquidityFromBatch(
        uint32 eid,
        address app,
        uint256 appIndex,
        bytes32[] memory proof,
        uint256 batchId
    ) external nonReentrant onlyApp(app) {
        Batches storage b = _batches[app][eid];
        LiquidityBatch memory batch = b.liquidity[batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        bytes32 appRoot = b.liquidityTree[batchId].root;
        (bytes32 root, uint256 timestamp) = getLastSyncedLiquidityRoot(eid);
        _verifyRoot(app, appRoot, appIndex, proof, root);
        _settleLiquidity(SettleLiquidityParams(eid, app, root, timestamp, batch.accounts, batch.liquidity));
    }

    /**
     * @notice Creates a new batch for data settlement with a unique batch ID.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param keys The array of keys to include in the batch.
     * @param values The array of data values corresponding to the keys.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     * - The caller must be a registered application.
     */
    function createDataBatch(uint32 eid, address app, bytes32[] calldata keys, bytes[] calldata values)
        external
        onlyApp(app)
    {
        if (keys.length != values.length) revert InvalidLengths();

        Batches storage b = _batches[app][eid];
        uint256 id = b.lastDataBatchId;
        b.data[id] = DataBatch(msg.sender, keys, values);
        b.dataHashTree[id].initialize();
        b.lastDataBatchId = id + 1;

        for (uint256 i; i < keys.length; ++i) {
            (bytes32 key, bytes memory value) = (keys[i], values[i]);
            b.dataHashTree[id].update(key, keccak256(value));
        }

        emit CreateDataBatch(eid, app, msg.sender, id);
    }

    /**
     * @notice Adds additional keys and values to an existing data batch.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param batchId The ID of the batch to append to.
     * @param keys The array of keys to append to the batch.
     * @param values The array of data values to append to the batch.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     * - The caller must be the original submitter of the batch.
     */
    function submitDataBatch(uint32 eid, address app, uint256 batchId, bytes32[] memory keys, bytes[] memory values)
        external
        onlyApp(app)
    {
        if (keys.length != values.length) revert InvalidLengths();

        Batches storage b = _batches[app][eid];
        DataBatch storage batch = b.data[batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        for (uint256 i; i < keys.length; ++i) {
            (bytes32 key, bytes memory value) = (keys[i], values[i]);
            batch.keys.push(key);
            batch.values.push(value);
            b.dataHashTree[batchId].update(key, keccak256(value));
        }
    }

    /**
     * @notice Settles data states for an application using data from an existing batch and verifies the Merkle proof.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param appIndex the index of app in the data tree on the remote chain.
     * @param proof The proof array to verify the sub-root within the top tree.
     * @param batchId The ID of the batch to settle.
     *
     * Requirements:
     * - The caller must be the original submitter of the batch.
     */
    function settleDataFromBatch(uint32 eid, address app, uint256 appIndex, bytes32[] memory proof, uint256 batchId)
        external
        nonReentrant
        onlyApp(app)
    {
        Batches storage b = _batches[app][eid];
        DataBatch memory batch = b.data[batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        bytes32 appRoot = b.dataHashTree[batchId].root;
        (bytes32 root, uint256 timestamp) = getLastSyncedDataRoot(eid);
        _verifyRoot(app, appRoot, appIndex, proof, root);
        _settleData(SettleDataParams(eid, timestamp, app, root, batch.keys, batch.values));
    }

    function _verifyRoot(address app, bytes32 appRoot, uint256 mainIndex, bytes32[] memory mainProof, bytes32 mainRoot)
        internal
    {
        if (mainRoot == bytes32(0)) revert RootNotReceived();

        // Construct the Merkle tree and verify mainRoot
        bool valid = MerkleTreeLib.verifyProof(bytes32(uint256(uint160(app))), appRoot, mainIndex, mainProof, mainRoot);
        if (!valid) revert InvalidRoot(appRoot, mainRoot);

        emit VerifyRoot(app, mainRoot);
    }
}
