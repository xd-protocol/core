// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { ArrayLib } from "../libraries/ArrayLib.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { SnapshotsLib } from "../libraries/SnapshotsLib.sol";
import { SynchronizerLocal } from "./SynchronizerLocal.sol";
import { ISynchronizerCallbacks } from "../interfaces/ISynchronizerCallbacks.sol";

/**
 * @title SynchronizerRemote
 * @notice Manages cross-chain state synchronization for liquidity and data by verifying and settling roots.
 *
 * # Lifecycle of a Root
 * A root progresses through the following states:
 *
 * 1. **None**:
 *    - The initial state where no root exists for a given chain and timestamp.
 *
 * 2. **Synced**:
 *    - Roots are received via `_onReceiveRoots` and stored in `liquidityRoots` or `dataRoots` for their respective timestamps.
 *    - Roots are accessible for verification but remain unprocessed.
 *
 * 3. **Settled**:
 *    - Settled roots are tracked in `liquiditySettled` or `dataSettled` mappings.
 *    - Once settled, data is processed via `_settleLiquidity` or `_settleData`, updating local states and triggering application-specific callbacks.
 *
 * 4. **Finalized**:
 *    - A root becomes finalized when both the liquidity root and data root for the same timestamp are settled.
 *    - Finalized roots represent a complete and validated cross-chain state.
 *
 * # How Settlement Works
 *
 * 1. **Root Reception**:
 *    - `_onReceiveRoots` processes incoming roots from remote chains.
 *    - Stores roots in `liquidityRoots` and `dataRoots`, indexed by `eid` and timestamp.
 *
 * 2. **Verification**:
 *    - `_verifyRoot` reconstructs subtree roots and validates proofs against the main tree root.
 *    - Marks roots as settled if valid.
 *
 * 3. **Settlement**:
 *    - `_settleLiquidity` and `_settleData` process settled roots, updating snapshots and triggering application-specific callbacks.
 *    - Calls `ISynchronizerCallbacks` hooks to notify applications of updates.
 *
 * 4. **Finalization**:
 *    - Finalized states require both liquidity and data roots to be settled for the same timestamp.
 *    - Enables accurate cross-chain state aggregation.
 */
abstract contract SynchronizerRemote is SynchronizerLocal {
    using AddressLib for address;
    using SnapshotsLib for SnapshotsLib.Snapshots;

    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct RemoteState {
        address app;
        SnapshotsLib.Snapshots totalLiquidity;
        mapping(address account => SnapshotsLib.Snapshots) liquidity;
        mapping(bytes32 key => SnapshotsLib.Snapshots) dataHashes;
        // settlement
        mapping(uint256 timestamp => bool) liquiditySettled;
        mapping(uint256 timestamp => bool) dataSettled;
    }

    struct SettleLiquidityParams {
        address app;
        uint32 eid;
        bytes32 root;
        uint256 timestamp;
        address[] accounts;
        int256[] liquidity;
    }

    struct SettleDataParams {
        address app;
        uint32 eid;
        bytes32 root;
        uint256 timestamp;
        bytes32[] keys;
        bytes[] values;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MAX_LOOP = 4096;

    mapping(address app => mapping(uint32 eid => RemoteState)) internal _remoteStates;

    mapping(uint32 eid => uint256[]) rootTimestamps;
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) liquidityRoots;
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) dataRoots;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateRemoteApp(uint32 indexed eid, address indexed app, address indexed remoteApp);
    event OnUpdateLiquidityFailure(
        uint32 indexed eid,
        uint256 indexed timestamp,
        address indexed account,
        int256 liquidity,
        int256 totalLiquidity,
        bytes reason
    );
    event OnUpdateTotalLiquidityFailure(
        uint32 indexed eid, uint256 indexed timestamp, int256 totalLiquidity, bytes reason
    );
    event OnUpdateDataFailure(
        uint32 indexed eid, uint256 indexed timestamp, bytes32 indexed account, bytes32 dataHash, bytes reason
    );
    event VerifyRoot(address indexed app, bytes32 indexed root);
    event SettleLiquidity(uint32 indexed eid, address indexed app, bytes32 indexed root, uint256 timestamp);
    event SettleData(uint32 indexed eid, address indexed app, bytes32 indexed root, uint256 timestamp);
    event OnReceiveStaleRoots(
        uint32 indexed eid, bytes32 indexed liquidityRoot, bytes32 indexed dataRoot, uint256 timestamp
    );
    event OnReceiveRoots(
        uint32 indexed eid, bytes32 indexed liquidityRoot, bytes32 indexed dataRoot, uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidLengths();
    error RemoteAppNotSet();
    error RootNotReceived();
    error LiquidityAlreadySettled();
    error DataAlreadySettled();
    error InvalidRoot();

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function eidsLength() public view virtual returns (uint256);

    function eidAt(uint256) public view virtual returns (uint32);

    /**
     * @notice Returns the address of the remote application for a local application.
     * @param app The address of the application.
     * @param eid The endpoint ID of the remote chain.
     * @return The remote application's address.
     */
    function getRemoteApp(address app, uint32 eid) external view returns (address) {
        return _remoteStates[app][eid].app;
    }

    /**
     * @notice Retrieves the aggregated total liquidity for an application across all remote and local states that are settled.
     * @param app The address of the application.
     * @return liquidity The aggregated total liquidity across all remote and local states.
     */
    function getSettledTotalLiquidity(address app) external view returns (int256 liquidity) {
        liquidity = getLocalTotalLiquidity(app);
        for (uint256 i; i < eidsLength(); ++i) {
            uint32 eid = eidAt(i);
            (, uint256 timestamp) = getLastSettledLiquidityRoot(app, eid);
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][eid].totalLiquidity.getAsInt(timestamp);
        }
    }

    /**
     * @notice Retrieves the aggregated total liquidity for an application across all remote and local states that are finalized.
     * @param app The address of the application.
     * @return liquidity The aggregated total liquidity across all remote and local states.
     */
    function getFinalizedTotalLiquidity(address app) external view returns (int256 liquidity) {
        liquidity = getLocalTotalLiquidity(app);
        for (uint256 i; i < eidsLength(); ++i) {
            uint32 eid = eidAt(i);
            (, uint256 timestamp) = getLastFinalizedLiquidityRoot(app, eid);
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][eid].totalLiquidity.getAsInt(timestamp);
        }
    }

    /**
     * @notice Retrieves the aggregated total liquidity for an application across all remote and local states at timestamps.
     * @param app The address of the application.
     * @param timestamps The timestamps to query the total liquidity at for each chain.
     * @return liquidity The aggregated total liquidity across all remote and local states.
     */
    function getTotalLiquidityAt(address app, uint256[] memory timestamps) external view returns (int256 liquidity) {
        uint256 length = eidsLength();
        if (length + 1 != timestamps.length) revert InvalidLengths();

        liquidity = getLocalTotalLiquidityAt(app, timestamps[0]);
        for (uint256 i; i < length; ++i) {
            liquidity += _remoteStates[app][eidAt(i)].totalLiquidity.getAsInt(timestamps[i + 1]);
        }
    }

    /**
     * @notice Retrieves the aggregated liquidity of a specific account across all remote and local states that are settled.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @return liquidity The aggregated liquidity of the specified account across all remote and local states.
     */
    function getSettledLiquidity(address app, address account) external view returns (int256 liquidity) {
        liquidity = getLocalLiquidity(app, account);
        for (uint256 i; i < eidsLength(); ++i) {
            uint32 eid = eidAt(i);
            (, uint256 timestamp) = getLastSettledLiquidityRoot(app, eid);
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][eid].liquidity[account].getAsInt(timestamp);
        }
    }

    /**
     * @notice Retrieves the aggregated liquidity of a specific account across all remote and local states that are finalized.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @return liquidity The aggregated liquidity of the specified account across all remote and local states.
     */
    function getFinalizedLiquidity(address app, address account) external view returns (int256 liquidity) {
        liquidity = getLocalLiquidity(app, account);
        for (uint256 i; i < eidsLength(); ++i) {
            uint32 eid = eidAt(i);
            (, uint256 timestamp) = getLastFinalizedLiquidityRoot(app, eid);
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][eid].liquidity[account].getAsInt(timestamp);
        }
    }

    /**
     * @notice Retrieves the aggregated liquidity of a specific account across all remote and local states at timestampss.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @param timestamps The timestamps to query the total liquidity at for each chain.
     * @return liquidity The aggregated liquidity of the specified account across all remote and local states.
     */
    function getLiquidityAt(address app, address account, uint256[] memory timestamps)
        external
        view
        returns (int256 liquidity)
    {
        uint256 length = eidsLength();
        if (length + 1 != timestamps.length) revert InvalidLengths();

        liquidity = getLocalLiquidityAt(app, account, timestamps[0]);
        for (uint256 i; i < length; ++i) {
            liquidity += _remoteStates[app][eidAt(i)].liquidity[account].getAsInt(timestamps[i + 1]);
        }
    }

    /**
     * @notice Retrieves the total liquidity for a remote application on a specific chain that is settled.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @return liquidity The total liquidity for the specified `eid`.
     */
    function getSettledRemoteTotalLiquidity(address app, uint32 eid) public view returns (int256 liquidity) {
        (, uint256 timestamp) = getLastSettledLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteTotalLiquidityAt(app, eid, timestamp);
    }

    /**
     * @notice Retrieves the total liquidity for a remote application on a specific chain that is finalized.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @return liquidity The total liquidity for the specified `eid`.
     */
    function getFinalizedRemoteTotalLiquidity(address app, uint32 eid) public view returns (int256 liquidity) {
        (, uint256 timestamp) = getLastFinalizedLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteTotalLiquidityAt(app, eid, timestamp);
    }

    /**
     * @notice Retrieves the total liquidity for a remote application on a specific chain at timestamp.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param timestamp The timestamp to query liquidity at.
     * @return liquidity The total liquidity for the specified `eid`.
     */
    function getRemoteTotalLiquidityAt(address app, uint32 eid, uint256 timestamp)
        public
        view
        returns (int256 liquidity)
    {
        return _remoteStates[app][eid].totalLiquidity.getAsInt(timestamp);
    }

    /**
     * @notice Retrieves the liquidity of a specific account for a remote application on a specific chain that is settled.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @return liquidity The liquidity of the specified account for the specified `eid`.
     */
    function getSettledRemoteLiquidity(address app, uint32 eid, address account)
        public
        view
        returns (int256 liquidity)
    {
        (, uint256 timestamp) = getLastSettledLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteLiquidityAt(app, eid, account, timestamp);
    }

    /**
     * @notice Retrieves the liquidity of a specific account for a remote application on a specific chain that is finalized.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @return liquidity The liquidity of the specified account for the specified `eid`.
     */
    function getFinalizedRemoteLiquidity(address app, uint32 eid, address account)
        public
        view
        returns (int256 liquidity)
    {
        (, uint256 timestamp) = getLastFinalizedLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteLiquidityAt(app, eid, account, timestamp);
    }

    /**
     * @notice Retrieves the liquidity of a specific account for a remote application on a specific chain at timestamp.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @param timestamp The timestamp to query liquidity at.
     * @return liquidity The liquidity of the specified account for the specified `eid`.
     */
    function getRemoteLiquidityAt(address app, uint32 eid, address account, uint256 timestamp)
        public
        view
        returns (int256 liquidity)
    {
        return _remoteStates[app][eid].liquidity[account].getAsInt(timestamp);
    }

    /**
     * @notice Retrieves the hash of the data of a specific account for a remote application on a specific chain that is settled.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param key The key of the data to query.
     * @return value The value of the specified key for the specified `eid`.
     */
    function getSettledRemoteDataHash(address app, uint32 eid, bytes32 key) public view returns (bytes32 value) {
        (, uint256 timestamp) = getLastSettledLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteDataHashAt(app, eid, key, timestamp);
    }

    /**
     * @notice Retrieves the hash of the data of a specific account for a remote application on a specific chain that is finalized.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param key The key of the data to query.
     * @return value The value of the specified key for the specified `eid`.
     */
    function getFinalizedRemoteDataHash(address app, uint32 eid, bytes32 key) public view returns (bytes32 value) {
        (, uint256 timestamp) = getLastFinalizedLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteDataHashAt(app, eid, key, timestamp);
    }

    /**
     * @notice Retrieves the hash of the data of a specific account for a remote application on a specific chain at timestamp.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @param key The key of the data to query.
     * @param timestamp The timestamp to query liquidity at.
     * @return value The value of the specified key for the specified `eid`.
     */
    function getRemoteDataHashAt(address app, uint32 eid, bytes32 key, uint256 timestamp)
        public
        view
        returns (bytes32 value)
    {
        return _remoteStates[app][eid].dataHashes[key].get(timestamp);
    }

    /**
     * @notice Retrieves the last synced liquidity root and its associated timestamp for a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @return root The last liquidity root for the specified `eid`.
     * @return timestamp The timestamp associated with the last liquidity root.
     */
    function getLastSyncedLiquidityRoot(uint32 eid) public view returns (bytes32 root, uint256 timestamp) {
        uint256 length = rootTimestamps[eid].length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = rootTimestamps[eid][length - 1];
        root = liquidityRoots[eid][timestamp];
    }

    /**
     * @notice Retrieves the last settled liquidity root and its associated timestamp for an application on a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @return root The last liquidity root for the specified `eid`.
     * @return timestamp The timestamp associated with the last liquidity root.
     */
    function getLastSettledLiquidityRoot(address app, uint32 eid)
        public
        view
        returns (bytes32 root, uint256 timestamp)
    {
        RemoteState storage state = _remoteStates[app][eid];
        uint256[] storage timestamps = rootTimestamps[eid];
        uint256 length = timestamps.length;
        for (uint256 i; i < length && i < MAX_LOOP; ++i) {
            uint256 ts = timestamps[length - i - 1];
            if (state.liquiditySettled[ts]) return (liquidityRoots[eid][ts], ts);
        }
    }

    /**
     * @notice Retrieves the last finalized liquidity root and its associated timestamp for an application on a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @return root The last liquidity root for the specified `eid`.
     * @return timestamp The timestamp associated with the last liquidity root.
     */
    function getLastFinalizedLiquidityRoot(address app, uint32 eid)
        public
        view
        returns (bytes32 root, uint256 timestamp)
    {
        uint256[] storage timestamps = rootTimestamps[eid];
        uint256 length = timestamps.length;
        for (uint256 i; i < length && i < MAX_LOOP; ++i) {
            uint256 ts = timestamps[length - i - 1];
            if (areRootsFinalized(app, eid, ts)) return (liquidityRoots[eid][ts], ts);
        }
    }

    /**
     * @notice Retrieves the last synced data root and its associated timestamp for a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @return root The last data root for the specified `eid`.
     * @return timestamp The timestamp associated with the last data root.
     */
    function getLastSyncedDataRoot(uint32 eid) public view returns (bytes32 root, uint256 timestamp) {
        uint256 length = rootTimestamps[eid].length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = rootTimestamps[eid][length - 1];
        root = dataRoots[eid][timestamp];
    }

    /**
     * @notice Retrieves the last settled data root and its associated timestamp for an application on a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @return root The last data root for the specified `eid`.
     * @return timestamp The timestamp associated with the last data root.
     */
    function getLastSettledDataRoot(address app, uint32 eid) public view returns (bytes32 root, uint256 timestamp) {
        RemoteState storage state = _remoteStates[app][eid];
        uint256[] storage timestamps = rootTimestamps[eid];
        uint256 length = timestamps.length;
        for (uint256 i; i < length && i < MAX_LOOP; ++i) {
            uint256 ts = timestamps[i - 1];
            if (state.dataSettled[ts]) return (dataRoots[eid][ts], ts);
        }
    }

    /**
     * @notice Retrieves the last finalized data root and its associated timestamp for an application on a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application.
     * @return root The last data root for the specified `eid`.
     * @return timestamp The timestamp associated with the last data root.
     */
    function getLastFinalizedDataRoot(address app, uint32 eid) public view returns (bytes32 root, uint256 timestamp) {
        uint256[] storage timestamps = rootTimestamps[eid];
        uint256 length = timestamps.length;
        for (uint256 i; i < length && i < MAX_LOOP; ++i) {
            uint256 ts = timestamps[i - 1];
            if (areRootsFinalized(app, eid, ts)) return (dataRoots[eid][ts], ts);
        }
    }

    function isLiquidityRootSettled(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        return _remoteStates[app][eid].liquiditySettled[timestamp] || liquidityRoots[eid][timestamp] == bytes32(0);
    }

    function isDataRootSettled(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        return _remoteStates[app][eid].dataSettled[timestamp] || dataRoots[eid][timestamp] == bytes32(0);
    }

    function areRootsFinalized(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        RemoteState storage state = _remoteStates[app][eid];
        bool liquiditySettled = state.liquiditySettled[timestamp];
        bool dataSettled = state.dataSettled[timestamp];
        if (liquiditySettled && dataSettled) return true;
        if (liquiditySettled && dataRoots[eid][timestamp] == bytes32(0)) return true;
        if (dataSettled && liquidityRoots[eid][timestamp] == bytes32(0)) return true;
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the mapping of a local application to its corresponding remote application on a specific chain.
     * @dev This function links the caller's local application to a remote application on the specified `eid`.
     *      Only the local application itself can invoke this function.
     * @param eid The endpoint ID representing the remote chain.
     * @param remoteApp The address of the remote application on the specified chain.
     *
     * Requirements:
     * - The caller must be the local application.
     */
    function updateRemoteApp(uint32 eid, address remoteApp) external onlyApp(msg.sender) {
        _remoteStates[msg.sender][eid].app = remoteApp;

        emit UpdateRemoteApp(eid, msg.sender, remoteApp);
    }

    /**
     * @notice Settles liquidity states directly without batching, verifying the proof for the app-tree root.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application on the current chain.
     * @param mainTreeIndex the index of app in the liquidity tree on the remote chain.
     * @param mainTreeProof The proof array to verify the app-root within the main tree.
     * @param accounts The array of accounts to settle.
     * @param liquidity The array of liquidity values corresponding to the accounts.
     *
     * Requirements:
     * - The `accounts` and `liquidity` arrays must have the same length.
     */
    function settleLiquidity(
        address app,
        uint32 eid,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        address[] calldata accounts,
        int256[] calldata liquidity
    ) external nonReentrant onlyApp(app) {
        if (accounts.length != liquidity.length) revert InvalidLengths();

        address remoteApp = _remoteStates[app][eid].app;
        if (remoteApp == address(0)) revert RemoteAppNotSet();

        (bytes32 root, uint256 timestamp) = getLastSyncedLiquidityRoot(eid);
        _verifyRoot(
            remoteApp,
            ArrayLib.convertToBytes32(accounts),
            ArrayLib.convertToBytes32(liquidity),
            mainTreeIndex,
            mainTreeProof,
            root
        );

        _settleLiquidity(SettleLiquidityParams(app, eid, root, timestamp, accounts, liquidity));
    }

    /**
     * @notice Finalizes data states directly without batching, verifying the proof for the app-tree root.
     * @param eid The endpoint ID of the remote chain.
     * @param app The address of the application on the current chain.
     * @param mainTreeIndex the index of app in the data tree on the remote chain.
     * @param mainTreeProof The proof array to verify the app-root within the main tree.
     * @param keys The array of keys to settle.
     * @param values The array of data values corresponding to the keys.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     */
    function settleData(
        address app,
        uint32 eid,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external nonReentrant onlyApp(app) {
        if (keys.length != values.length) revert InvalidLengths();

        address remoteApp = _remoteStates[app][eid].app;
        if (remoteApp == address(0)) revert RemoteAppNotSet();

        (bytes32 root, uint256 timestamp) = getLastSyncedDataRoot(eid);
        _verifyRoot(remoteApp, keys, ArrayLib.hashElements(values), mainTreeIndex, mainTreeProof, root);

        _settleData(SettleDataParams(app, eid, root, timestamp, keys, values));
    }

    /**
     * @notice Verifies a Merkle tree root for an application and marks it as settled.
     * @param app The address of the application for which the root is being verified.
     * @param keys The array of keys representing the nodes in the application's subtree.
     * @param values The array of values corresponding to the keys in the application's subtree.
     * @param mainTreeIndex the index of application in the main tree on the remote chain.
     * @param mainTreeProof The Merkle proof connecting the application's subtree root to the main tree root.
     * @param mainTreeRoot The expected root of the main Merkle tree.
     *
     * @dev This function:
     * - Constructs the application's subtree root using the given keys and values.
     * - Validates the Merkle proof to ensure the application's subtree is correctly connected to the main tree.
     */
    function _verifyRoot(
        address app,
        bytes32[] memory keys,
        bytes32[] memory values,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        bytes32 mainTreeRoot
    ) internal {
        if (mainTreeRoot == bytes32(0)) revert RootNotReceived();

        // Construct the Merkle tree and verify mainTreeRoot
        bytes32 appRoot = MerkleTreeLib.computeRoot(keys, values);
        bool valid = MerkleTreeLib.verifyProof(
            bytes32(uint256(uint160(app))), appRoot, mainTreeIndex, mainTreeProof, mainTreeRoot
        );
        if (!valid) revert InvalidRoot();

        emit VerifyRoot(app, mainTreeRoot);
    }

    function _settleLiquidity(SettleLiquidityParams memory params) internal {
        AppState storage localState = _appStates[params.app];
        bool syncContracts = localState.syncContracts;

        RemoteState storage state = _remoteStates[params.app][params.eid];
        if (state.liquiditySettled[params.timestamp]) revert LiquidityAlreadySettled();
        state.liquiditySettled[params.timestamp] = true;

        int256 totalLiquidity;
        for (uint256 i; i < params.accounts.length; i++) {
            (address account, int256 liquidity) = (params.accounts[i], params.liquidity[i]);
            account = getLocalAccount(params.app, params.eid, account);
            if (account.isContract() && !syncContracts) continue;

            SnapshotsLib.Snapshots storage snapshots = state.liquidity[account];
            int256 accLiquidity = snapshots.getAsInt(params.timestamp) + liquidity;
            snapshots.appendAsInt(accLiquidity, params.timestamp);
            totalLiquidity += liquidity;

            try ISynchronizerCallbacks(params.app).onUpdateLiquidity(
                params.eid, params.timestamp, account, accLiquidity, totalLiquidity
            ) { } catch (bytes memory reason) {
                emit OnUpdateLiquidityFailure(
                    params.eid, params.timestamp, account, accLiquidity, totalLiquidity, reason
                );
            }
        }
        state.totalLiquidity.appendAsInt(totalLiquidity, params.timestamp);

        emit SettleLiquidity(params.eid, params.app, params.root, params.timestamp);
    }

    function _settleData(SettleDataParams memory params) internal {
        RemoteState storage state = _remoteStates[params.app][params.eid];
        if (state.dataSettled[params.timestamp]) revert DataAlreadySettled();
        state.dataSettled[params.timestamp] = true;

        for (uint256 i; i < params.keys.length; i++) {
            (bytes32 key, bytes memory value) = (params.keys[i], params.values[i]);

            bytes32 hash = keccak256(value);
            state.dataHashes[key].append(hash, params.timestamp);

            try ISynchronizerCallbacks(params.app).onUpdateData(params.eid, params.timestamp, key, value) { }
            catch (bytes memory reason) {
                emit OnUpdateDataFailure(params.eid, params.timestamp, key, hash, reason);
            }
        }

        emit SettleData(params.eid, params.app, params.root, params.timestamp);
    }

    /**
     * @notice Processes incoming liquidity and data roots for a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @param liquidityRoot The root hash of the liquidity Merkle tree.
     * @param dataRoot The root hash of the data Merkle tree.
     * @param timestamp The timestamp associated with these roots.
     */
    function _onReceiveRoots(uint32 eid, bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) internal {
        uint256 length = rootTimestamps[eid].length;
        if (length > 0 && timestamp <= rootTimestamps[eid][length - 1]) {
            emit OnReceiveStaleRoots(eid, liquidityRoot, dataRoot, timestamp);
            return;
        }

        rootTimestamps[eid].push(timestamp);
        liquidityRoots[eid][timestamp] = liquidityRoot;
        dataRoots[eid][timestamp] = dataRoot;

        emit OnReceiveRoots(eid, liquidityRoot, dataRoot, timestamp);
    }
}
