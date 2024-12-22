// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DynamicSparseMerkleTreeLib } from "../libraries/DynamicSparseMerkleTreeLib.sol";
import { Checkpoints } from "../libraries/Checkpoints.sol";
import { SynchronizerLocal } from "./SynchronizerLocal.sol";
import { ISynchronizerCallbacks } from "../interfaces/ISynchronizerCallbacks.sol";

abstract contract SynchronizerRemote is SynchronizerLocal {
    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct RemoteState {
        mapping(uint32 eid => int256) remoteSum;
        mapping(uint32 eid => mapping(bytes32 tag => int256)) remoteValues;
        mapping(uint32 eid => mapping(uint256 timestamp => bool)) rootSettled;
        mapping(uint32 eid => mapping(uint256 batchId => Batch)) batches;
        mapping(uint32 eid => uint256) lastBatchId;
    }

    struct Batch {
        address submitter;
        bytes32[] tags;
        int256[] values;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(address app => RemoteState) internal _remoteStates;

    mapping(uint32 eid => uint256) lastRootTimestamp;
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) roots;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SettleValues(address indexed app, uint32 indexed eid, uint256 indexed timestamp);
    event OnUpdateValueFailure(uint32 indexed eid, bytes32 indexed tag, bytes reason);
    event OnUpdateSumFailure(uint32 indexed eid, bytes reason);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidLengths();
    error Forbidden();
    error RootNotSynced();
    error RootAlreadySynced();
    error InvalidRoot(bytes32 computed, bytes32 expected);

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _eidsLength() internal view virtual returns (uint256);

    function _eidAt(uint256) internal view virtual returns (uint32);

    /**
     * @notice Computes the global sum for an application by aggregating local and remote sums.
     * @param app The address of the application.
     * @return sum The total global sum for the application.
     */
    function getGlobalSum(address app) external view returns (int256 sum) {
        sum = getLocalSum(app);
        RemoteState storage state = _remoteStates[app];
        for (uint256 i; i < _eidsLength(); ++i) {
            sum += state.remoteSum[_eidAt(i)];
        }
    }

    /**
     * @notice Retrieves the global value of a specific tag for an application by aggregating local and remote values.
     * @param app The address of the application.
     * @param tag The tag to query.
     * @return value The global value for the given tag.
     */
    function getGlobalValue(address app, bytes32 tag) external view returns (int256 value) {
        value = getLocalValue(app, tag);
        RemoteState storage state = _remoteStates[app];
        for (uint256 i; i < _eidsLength(); ++i) {
            value += state.remoteValues[_eidAt(i)][tag];
        }
    }

    /**
     * @notice Converts an array of `int256` values into an array of `bytes32`.
     * @param values The array of `int256` values to be converted.
     * @return result The array of `bytes32` values.
     */
    function convertToBytes32(int256[] memory values) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](values.length); // Allocate memory for the result array
        for (uint256 i = 0; i < values.length; i++) {
            unchecked {
                result[i] = bytes32(uint256(values[i])); // Convert int256 to bytes32
            }
        }
        return result;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new batch for settlement with a unique batch ID.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param tags The array of tags to include in the batch.
     * @param values The array of values corresponding to the tags.
     */
    function submitForSettlement(uint32 eid, address app, bytes32[] calldata tags, int256[] calldata values)
        external
        onlyApp(app)
    {
        if (tags.length != values.length) revert InvalidLengths();

        RemoteState storage state = _remoteStates[app];
        uint256 lastBatchId = state.lastBatchId[eid];
        state.batches[eid][lastBatchId] = Batch(msg.sender, tags, values);
        state.lastBatchId[eid] = lastBatchId + 1;
    }

    /**
     * @notice Adds additional tags and values to an existing batch.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param batchId The ID of the batch to append to.
     * @param tags The array of tags to append to the batch.
     * @param values The array of values corresponding to the tags.
     */
    function submitToBatch(uint32 eid, address app, uint256 batchId, bytes32[] memory tags, int256[] memory values)
        external
        onlyApp(app)
    {
        if (tags.length != values.length) revert InvalidLengths();

        RemoteState storage state = _remoteStates[app];
        Batch storage batch = state.batches[eid][batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        for (uint256 i; i < tags.length; ++i) {
            batch.tags.push(tags[i]);
            batch.values.push(values[i]);
        }
    }

    /**
     * @notice Settles values for an application using data from an existing batch and verifies the proof.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param batchId The ID of the batch to settle.
     * @param proof The proof array to verify the sub-tree root within the main tree.
     */
    function settleValuesFromBatch(uint32 eid, address app, uint256 batchId, bytes32[] memory proof)
        external
        onlyApp(app)
    {
        RemoteState storage state = _remoteStates[app];
        Batch memory batch = state.batches[eid][batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        _settleValues(eid, app, proof, batch.tags, batch.values);
    }

    /**
     * @notice Settles values directly without batching, verifying the proof for the sub-tree root.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param proof The proof array to verify the sub-tree root within the main tree.
     * @param tags The array of tags to settle.
     * @param values The array of values corresponding to the tags.
     */
    function settleValues(
        uint32 eid,
        address app,
        bytes32[] memory proof,
        bytes32[] calldata tags,
        int256[] calldata values
    ) external onlyApp(app) {
        if (tags.length != values.length) revert InvalidLengths();

        _settleValues(eid, app, proof, tags, values);
    }

    function _settleValues(
        uint32 eid,
        address app,
        bytes32[] memory proof,
        bytes32[] memory tags,
        int256[] memory values
    ) internal {
        uint256 timestamp = lastRootTimestamp[eid];
        bytes32 root = roots[eid][timestamp];
        if (root == bytes32(0)) revert RootNotSynced();

        RemoteState storage state = _remoteStates[app];
        if (state.rootSettled[eid][timestamp]) revert RootAlreadySynced();

        // Construct the Merkle tree and verify root
        bytes32 subRoot = DynamicSparseMerkleTreeLib.getRoot(tags, convertToBytes32(values));
        bool valid =
            DynamicSparseMerkleTreeLib.verifyProof(MAIN_TREE_HEIGHT, bytes32(bytes20(app)), subRoot, proof, root);
        if (!valid) revert InvalidRoot(subRoot, root);

        // Settle each checkpoint
        int256 sum;
        for (uint256 i; i < tags.length; i++) {
            (bytes32 tag, int256 value) = (tags[i], values[i]);
            sum += value;
            state.remoteValues[eid][tag] = value;

            try ISynchronizerCallbacks(app).onUpdateValue(eid, tag, value) {
                // Empty
            } catch (bytes memory reason) {
                emit OnUpdateValueFailure(eid, tag, reason);
            }
        }
        state.remoteSum[eid] = sum;
        try ISynchronizerCallbacks(app).onUpdateSum(eid, sum) {
            // Empty
        } catch (bytes memory reason) {
            emit OnUpdateSumFailure(eid, reason);
        }

        state.rootSettled[eid][timestamp] = true;

        emit SettleValues(app, eid, timestamp);
    }
}
