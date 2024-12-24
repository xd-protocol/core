// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DynamicSparseMerkleTreeLib } from "../libraries/DynamicSparseMerkleTreeLib.sol";
import { SynchronizerLocal } from "./SynchronizerLocal.sol";
import { ISynchronizerCallbacks } from "../interfaces/ISynchronizerCallbacks.sol";

abstract contract SynchronizerRemote is SynchronizerLocal {
    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct RemoteState {
        mapping(uint32 eid => int256) totalLiquidity;
        mapping(uint32 eid => mapping(address account => int256)) liquidities;
        // batches
        mapping(uint32 eid => mapping(uint256 batchId => LiquidityBatch)) liquidityBatches;
        mapping(uint32 eid => uint256) lastLiquidityBatchId;
        mapping(uint32 eid => mapping(uint256 batchId => DataBatch)) dataBatches;
        mapping(uint32 eid => uint256) lastDataBatchId;
        // settlement
        mapping(bytes32 => bool) rootVerified;
    }

    struct LiquidityBatch {
        address submitter;
        address[] accounts;
        int256[] liquidities;
    }

    struct DataBatch {
        address submitter;
        bytes32[] keys;
        bytes[] values;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    mapping(address app => RemoteState) internal _remoteStates;

    mapping(uint32 eid => uint256) lastRootTimestamp;
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) liquidityRoots;
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) dataRoots;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OnUpdateLiquidityFailure(uint32 indexed eid, address indexed account, int256 liquidity, bytes reason);
    event OnUpdateDataFailure(uint32 indexed eid, bytes32 indexed account, bytes indexed data, bytes reason);
    event OnUpdateTotalLiquidityFailure(uint32 indexed eid, int256 totalLiquidity, bytes reason);
    event VerifyRoot(address indexed app, bytes32 indexed root);
    event SettleLiquidities(address indexed app, bytes32 indexed root);
    event SettleData(address indexed app, bytes32 indexed root);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidLengths();
    error Forbidden();
    error RootNotReceived();
    error RootAlreadyVerified();
    error InvalidRoot(bytes32 computed, bytes32 expected);

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _eidsLength() internal view virtual returns (uint256);

    function _eidAt(uint256) internal view virtual returns (uint32);

    /**
     * @notice Retrieves the aggregated total liquidity for an application across all external IDs (`eid`) and local states.
     * @param app The address of the application.
     * @return liquidity The aggregated total liquidity across all `eid` and local states.
     */
    function getOmniTotalLiquidity(address app) external view returns (int256 liquidity) {
        liquidity = getTotalLiquidity(app);
        RemoteState storage state = _remoteStates[app];
        for (uint256 i; i < _eidsLength(); ++i) {
            liquidity += state.totalLiquidity[_eidAt(i)];
        }
    }

    /**
     * @notice Retrieves the aggregated liquidity of a specific account across all external IDs (`eid`) and local states.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @return liquidity The aggregated liquidity of the specified account across all `eid` and local states.
     */
    function getOmniLiquidity(address app, address account) external view returns (int256 liquidity) {
        liquidity = getLiquidity(app, account);
        RemoteState storage state = _remoteStates[app];
        for (uint256 i; i < _eidsLength(); ++i) {
            liquidity += state.liquidities[_eidAt(i)][account];
        }
    }

    /**
     * @notice Retrieves the total liquidity for a specific external ID (`eid`) of a remote application.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @return liquidity The total liquidity for the specified `eid`.
     */
    function getRemoteTotalLiquidity(uint32 eid, address app) public view returns (int256 liquidity) {
        RemoteState storage state = _remoteStates[app];
        return state.totalLiquidity[eid];
    }

    /**
     * @notice Retrieves the liquidity of a specific account for a specific external ID (`eid`) of a remote application.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @return liquidity The liquidity of the specified account for the specified `eid`.
     */
    function getRemoteLiquidity(uint32 eid, address app, address account) public view returns (int256 liquidity) {
        RemoteState storage state = _remoteStates[app];
        return state.liquidities[eid][account];
    }

    /**
     * @notice Retrieves the last liquidity root and its associated timestamp for a specific external ID (`eid`).
     * @param eid The external ID of the remote application.
     * @return root The last liquidity root for the specified `eid`.
     * @return timestamp The timestamp associated with the last liquidity root.
     */
    function getLastLiquidityRoot(uint32 eid) public view returns (bytes32, uint256) {
        uint256 timestamp = lastRootTimestamp[eid];
        return (liquidityRoots[eid][timestamp], timestamp);
    }

    /**
     * @notice Retrieves the last data root and its associated timestamp for a specific external ID (`eid`).
     * @param eid The external ID of the remote application.
     * @return root The last data root for the specified `eid`.
     * @return timestamp The timestamp associated with the last data root.
     */
    function getLastDataRoot(uint32 eid) public view returns (bytes32, uint256) {
        uint256 timestamp = lastRootTimestamp[eid];
        return (dataRoots[eid][timestamp], timestamp);
    }

    /**
     * @notice Converts an array of `address` values into an array of `bytes32`.
     * @param values The array of `address` values to be converted.
     * @return result The array of `bytes32` values.
     */
    function _convertToBytes32(address[] memory values) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](values.length); // Allocate memory for the result array
        for (uint256 i; i < values.length; i++) {
            unchecked {
                result[i] = bytes32(uint256(uint160(values[i]))); // Convert address to bytes32
            }
        }
        return result;
    }

    /**
     * @notice Converts an array of `int256` values into an array of `bytes32`.
     * @param values The array of `int256` values to be converted.
     * @return result The array of `bytes32` values.
     */
    function _convertToBytes32(int256[] memory values) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](values.length); // Allocate memory for the result array
        for (uint256 i; i < values.length; i++) {
            unchecked {
                result[i] = bytes32(uint256(values[i])); // Convert int256 to bytes32
            }
        }
        return result;
    }

    function _hashElements(bytes[] memory values) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](values.length); // Allocate memory for the result array
        for (uint256 i; i < values.length; i++) {
            unchecked {
                result[i] = keccak256(values[i]); // Hash value
            }
        }
        return result;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new batch for liquidity settlement with a unique batch ID.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param accounts The array of accounts to include in the batch.
     * @param liquidities The array of liquidity values corresponding to the accounts.
     *
     * Requirements:
     * - The `accounts` and `liquidities` arrays must have the same length.
     * - The caller must be a registered application.
     */
    function submitForLiquiditySettlement(
        uint32 eid,
        address app,
        address[] calldata accounts,
        int256[] calldata liquidities
    ) external onlyApp(app) {
        if (accounts.length != liquidities.length) revert InvalidLengths();

        RemoteState storage state = _remoteStates[app];
        uint256 lastBatchId = state.lastLiquidityBatchId[eid];
        state.liquidityBatches[eid][lastBatchId] = LiquidityBatch(msg.sender, accounts, liquidities);
        state.lastLiquidityBatchId[eid] = lastBatchId + 1;
    }

    /**
     * @notice Adds additional accounts and liquidities to an existing liquidity batch.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param batchId The ID of the batch to append to.
     * @param accounts The array of accounts to append to the batch.
     * @param liquidities The array of liquidity values to append to the batch.
     *
     * Requirements:
     * - The `accounts` and `liquidities` arrays must have the same length.
     * - The caller must be the original submitter of the batch.
     */
    function submitToLiquidityBatch(
        uint32 eid,
        address app,
        uint256 batchId,
        address[] memory accounts,
        int256[] memory liquidities
    ) external onlyApp(app) {
        if (accounts.length != liquidities.length) revert InvalidLengths();

        RemoteState storage state = _remoteStates[app];
        LiquidityBatch storage batch = state.liquidityBatches[eid][batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        for (uint256 i; i < accounts.length; ++i) {
            batch.accounts.push(accounts[i]);
            batch.liquidities.push(liquidities[i]);
        }
    }

    /**
     * @notice Settles liquidity states for an application using data from an existing batch and verifies the Merkle proof.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param proof The proof array to verify the sub-root within the top tree.
     * @param batchId The ID of the batch to settle.
     *
     * Requirements:
     * - The caller must be the original submitter of the batch.
     */
    function settleLiquiditiesFromBatch(uint32 eid, address app, bytes32[] memory proof, uint256 batchId)
        external
        nonReentrant
        onlyApp(app)
    {
        RemoteState storage state = _remoteStates[app];
        LiquidityBatch memory batch = state.liquidityBatches[eid][batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        (bytes32 root,) = getLastLiquidityRoot(eid);
        _verifyRoot(
            app,
            root,
            LIQUIDITY_TREE_HEIGHT,
            proof,
            _convertToBytes32(batch.accounts),
            _convertToBytes32(batch.liquidities)
        );
        _updateLiquidities(eid, app, root, batch.accounts, batch.liquidities);
    }

    /**
     * @notice Settles liquidity states directly without batching, verifying the proof for the sub-tree root.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param proof The proof array to verify the sub-root within the top tree.
     * @param accounts The array of accounts to settle.
     * @param liquidities The array of liquidity values corresponding to the accounts.
     *
     * Requirements:
     * - The `accounts` and `liquidities` arrays must have the same length.
     */
    function settleLiquidities(
        uint32 eid,
        address app,
        bytes32[] memory proof,
        address[] calldata accounts,
        int256[] calldata liquidities
    ) external nonReentrant onlyApp(app) {
        if (accounts.length != liquidities.length) revert InvalidLengths();

        (bytes32 root,) = getLastLiquidityRoot(eid);
        _verifyRoot(
            app, root, LIQUIDITY_TREE_HEIGHT, proof, _convertToBytes32(accounts), _convertToBytes32(liquidities)
        );
        _updateLiquidities(eid, app, root, accounts, liquidities);
    }

    /**
     * @notice Creates a new batch for data settlement with a unique batch ID.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param keys The array of keys to include in the batch.
     * @param values The array of data values corresponding to the keys.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     * - The caller must be a registered application.
     */
    function submitForDataSettlement(uint32 eid, address app, bytes32[] calldata keys, bytes[] calldata values)
        external
        onlyApp(app)
    {
        if (keys.length != values.length) revert InvalidLengths();

        RemoteState storage state = _remoteStates[app];
        uint256 lastBatchId = state.lastDataBatchId[eid];
        state.dataBatches[eid][lastBatchId] = DataBatch(msg.sender, keys, values);
        state.lastDataBatchId[eid] = lastBatchId + 1;
    }

    /**
     * @notice Adds additional keys and values to an existing data batch.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param batchId The ID of the batch to append to.
     * @param keys The array of keys to append to the batch.
     * @param values The array of data values to append to the batch.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     * - The caller must be the original submitter of the batch.
     */
    function submitToDataBatch(uint32 eid, address app, uint256 batchId, bytes32[] memory keys, bytes[] memory values)
        external
        onlyApp(app)
    {
        if (keys.length != values.length) revert InvalidLengths();

        RemoteState storage state = _remoteStates[app];
        DataBatch storage batch = state.dataBatches[eid][batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        for (uint256 i; i < keys.length; ++i) {
            batch.keys.push(keys[i]);
            batch.values.push(values[i]);
        }
    }

    /**
     * @notice Settles data states for an application using data from an existing batch and verifies the Merkle proof.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param proof The proof array to verify the sub-root within the top tree.
     * @param batchId The ID of the batch to settle.
     *
     * Requirements:
     * - The caller must be the original submitter of the batch.
     */
    function settleDataFromBatch(uint32 eid, address app, bytes32[] memory proof, uint256 batchId)
        external
        nonReentrant
        onlyApp(app)
    {
        RemoteState storage state = _remoteStates[app];
        DataBatch memory batch = state.dataBatches[eid][batchId];
        if (batch.submitter != msg.sender) revert Forbidden();

        (bytes32 root,) = getLastDataRoot(eid);
        _verifyRoot(app, root, DATA_TREE_HEIGHT, proof, batch.keys, _hashElements(batch.values));
        _updateData(eid, app, root, batch.keys, batch.values);
    }

    /**
     * @notice Settles data states directly without batching, verifying the proof for the sub-tree root.
     * @param eid The external ID of the remote application.
     * @param app The address of the application.
     * @param proof The proof array to verify the sub-root within the top tree.
     * @param keys The array of keys to settle.
     * @param values The array of data values corresponding to the keys.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     */
    function settleData(
        uint32 eid,
        address app,
        bytes32[] memory proof,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external nonReentrant onlyApp(app) {
        if (keys.length != values.length) revert InvalidLengths();

        (bytes32 root,) = getLastDataRoot(eid);
        _verifyRoot(app, root, DATA_TREE_HEIGHT, proof, keys, _hashElements(values));
        _updateData(eid, app, root, keys, values);
    }

    function _verifyRoot(
        address app,
        bytes32 root,
        uint256 height,
        bytes32[] memory proof,
        bytes32[] memory keys,
        bytes32[] memory values
    ) internal {
        if (root == bytes32(0)) revert RootNotReceived();

        RemoteState storage state = _remoteStates[app];
        if (state.rootVerified[root]) revert RootAlreadyVerified();

        // Construct the Merkle tree and verify root
        bytes32 appRoot = DynamicSparseMerkleTreeLib.getRoot(height, keys, values);
        bool valid = DynamicSparseMerkleTreeLib.verifyProof(
            TOP_TREE_HEIGHT, bytes32(uint256(uint160(app))), appRoot, proof, root
        );
        if (!valid) revert InvalidRoot(appRoot, root);

        state.rootVerified[root] = true;

        emit VerifyRoot(app, root);
    }

    function _updateLiquidities(
        uint32 eid,
        address app,
        bytes32 root,
        address[] memory accounts,
        int256[] memory liquidities
    ) internal {
        AppSetting storage appSetting = _appSettings[app];
        bool syncContracts = appSetting.syncContracts;

        RemoteState storage state = _remoteStates[app];
        int256 totalLiquidity;
        for (uint256 i; i < accounts.length; i++) {
            (address account, int256 liquidity) = (accounts[i], liquidities[i]);
            if (_isContract(account) && !syncContracts) continue;

            // TODO: check again and use prevAccountRedirections
            address redirected = appSetting.accountRedirections[eid][account];
            account = redirected == address(0) ? account : redirected;

            totalLiquidity += liquidity;
            state.liquidities[eid][account] = liquidity;

            try ISynchronizerCallbacks(app).onUpdateLiquidity(eid, account, liquidity) { }
            catch (bytes memory reason) {
                emit OnUpdateLiquidityFailure(eid, account, liquidity, reason);
            }
        }
        state.totalLiquidity[eid] = totalLiquidity;
        try ISynchronizerCallbacks(app).onUpdateTotalLiquidity(eid, totalLiquidity) { }
        catch (bytes memory reason) {
            emit OnUpdateTotalLiquidityFailure(eid, totalLiquidity, reason);
        }

        emit SettleLiquidities(app, root);
    }

    function _updateData(uint32 eid, address app, bytes32 root, bytes32[] memory keys, bytes[] memory values)
        internal
    {
        for (uint256 i; i < keys.length; i++) {
            (bytes32 key, bytes memory value) = (keys[i], values[i]);

            try ISynchronizerCallbacks(app).onUpdateData(eid, key, value) { }
            catch (bytes memory reason) {
                emit OnUpdateDataFailure(eid, key, value, reason);
            }
        }

        emit SettleData(app, root);
    }
}
