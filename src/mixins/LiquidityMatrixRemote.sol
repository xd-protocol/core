// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { ArrayLib } from "../libraries/ArrayLib.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { SnapshotsLib } from "../libraries/SnapshotsLib.sol";
import { LiquidityMatrixLocal } from "./LiquidityMatrixLocal.sol";
import { ILiquidityMatrixCallbacks } from "../interfaces/ILiquidityMatrixCallbacks.sol";
import { ILiquidityMatrixAccountMapper } from "../interfaces/ILiquidityMatrixAccountMapper.sol";

/**
 * @title LiquidityMatrixRemote
 * @notice Manages cross-chain state synchronization for liquidity and data by verifying and settling roots.
 *
 * # Lifecycle of a Root
 * A root progresses through the following states:
 *
 * 1. **None**:
 *    - The initial state where no root exists for a given chain and timestamp.
 *
 * 2. **Synced**:
 *    - Roots are received via `_onReceiveRoots` and stored in `_liquidityRoots` or `_dataRoots` for their respective timestamps.
 *    - Roots are accessible for verification but remain unprocessed.
 *
 * 3. **Settled**:
 *    - Settled roots are tracked in `liquiditySettled` or `dataSettled` mappings.
 *    - Once settled, data is processed via `settleLiquidity` or `settleData`, updating local states and triggering application-specific callbacks.
 *
 * 4. **Finalized**:
 *    - A root becomes finalized when both the liquidity root and data root for the same timestamp are settled.
 *    - Finalized roots represent a complete and validated cross-chain state.
 *
 * # How Settlement Works
 *
 * 1. **Root Reception**:
 *    - `_onReceiveRoots` processes incoming roots from remote chains.
 *    - Stores roots in `_liquidityRoots` and `_dataRoots`, indexed by `eid` and timestamp.
 *
 * 2. **Verification**:
 *    - `_verifyRoot` reconstructs subtree roots and validates proofs against the main tree root.
 *    - Marks roots as settled if valid.
 *
 * 3. **Settlement**:
 *    - `settleLiquidity` and `settleData` process settled roots, updating snapshots and triggering application-specific callbacks.
 *    - Calls `ILiquidityMatrixCallbacks` hooks to notify applications of updates.
 *
 * 4. **Finalization**:
 *    - Finalized states require both liquidity and data roots to be settled for the same timestamp.
 *    - Enables accurate cross-chain state aggregation.
 */
abstract contract LiquidityMatrixRemote is LiquidityMatrixLocal {
    using AddressLib for address;
    using SnapshotsLib for SnapshotsLib.Snapshots;

    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct RemoteState {
        address app;
        mapping(address remote => address local) mappedAccounts;
        mapping(address local => bool) localAccountMapped;
        SnapshotsLib.Snapshots totalLiquidity;
        mapping(address account => SnapshotsLib.Snapshots) liquidity;
        mapping(bytes32 key => SnapshotsLib.Snapshots) dataHashes;
        // settlement
        mapping(uint256 timestamp => bool) liquiditySettled;
        mapping(uint256 timestamp => bool) dataSettled;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MAX_LOOP = 4096;

    mapping(address => bool) internal _isSettlerWhitelisted;

    mapping(address app => mapping(uint32 eid => RemoteState)) internal _remoteStates;

    mapping(uint32 eid => uint256[]) internal _rootTimestamps;
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) internal _liquidityRoots;
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) internal _dataRoots;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateRemoteApp(uint32 indexed eid, address indexed app, address indexed remoteApp);
    event OnUpdateLiquidityFailure(
        uint32 indexed eid, uint256 indexed timestamp, address indexed account, int256 liquidity, bytes reason
    );
    event OnUpdateTotalLiquidityFailure(
        uint32 indexed eid, uint256 indexed timestamp, int256 totalLiquidity, bytes reason
    );
    event OnUpdateDataFailure(
        uint32 indexed eid, uint256 indexed timestamp, bytes32 indexed account, bytes32 dataHash, bytes reason
    );
    event SettleLiquidity(uint32 indexed eid, address indexed app, bytes32 indexed root, uint256 timestamp);
    event SettleData(uint32 indexed eid, address indexed app, bytes32 indexed root, uint256 timestamp);
    event OnReceiveStaleRoots(
        uint32 indexed eid, bytes32 indexed liquidityRoot, bytes32 indexed dataRoot, uint256 timestamp
    );
    event OnReceiveRoots(
        uint32 indexed eid, bytes32 indexed liquidityRoot, bytes32 indexed dataRoot, uint256 timestamp
    );
    event MapAccount(address indexed app, uint32 indexed eid, address remote, address indexed local);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotSettler();
    error InvalidLengths();
    error LiquidityAlreadySettled();
    error DataAlreadySettled();
    error RemoteAccountAlreadyMapped(uint32 remoteEid, address remoteAccount);
    error LocalAccountAlreadyMapped(uint32 remoteEid, address localAccount);
    error AccountsNotMapped(uint32 remoteEid, address remoteAccount, address localAccount);

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlySettler(address account, address app) {
        if (!_isSettlerWhitelisted[account] || _appStates[app].settler != account) revert NotSettler();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function eidsLength() public view virtual returns (uint256);

    function eidAt(uint256) public view virtual returns (uint32);

    function isSettlerWhitelisted(address account) external view returns (bool) {
        return _isSettlerWhitelisted[account];
    }

    /**
     * @notice Retrieves the local account mapped to a given remote account for an application from a specific chain.
     * @param app The address of the application that owns the mapping.
     * @param eid The endpoint ID of the remote chain associated with the account mapping.
     * @param remote The address of the remote account.
     * @return local The address of the corresponding local account, or `address(0)` if no mapping exists.
     */
    function getMappedAccount(address app, uint32 eid, address remote) external view returns (address local) {
        local = _remoteStates[app][eid].mappedAccounts[remote];
        return local == address(0) ? remote : local;
    }

    /**
     * @notice Retrieves whether the local account was mapped for an application from a specific chain.
     * @param app The address of the application that owns the mapping.
     * @param eid The endpoint ID of the remote chain associated with the account mapping.
     * @param local The address of the local account.
     * @return `true` if the local account was mapped, `false` otherwise.
     */
    function isLocalAccountMapped(address app, uint32 eid, address local) external view returns (bool) {
        return _remoteStates[app][eid].localAccountMapped[local];
    }

    function getLiquidityRootAt(uint32 eid, uint256 timestamp) public view returns (bytes32 root) {
        return _liquidityRoots[eid][timestamp];
    }

    function getDataRootAt(uint32 eid, uint256 timestamp) public view returns (bytes32 root) {
        return _dataRoots[eid][timestamp];
    }

    /**
     * @notice Returns the address of the remote application for a local application.
     * @param app The address of the application.
     * @param eid The endpoint ID of the remote chain.
     * @return The remote application's address.
     */
    function getRemoteApp(address app, uint32 eid) public view returns (address) {
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
        (, uint256 timestamp) = getLastSettledDataRoot(app, eid);
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
        uint256 length = _rootTimestamps[eid].length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = _rootTimestamps[eid][length - 1];
        root = _liquidityRoots[eid][timestamp];
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
        uint256[] storage timestamps = _rootTimestamps[eid];
        uint256 length = timestamps.length;
        for (uint256 i; i < length && i < MAX_LOOP; ++i) {
            uint256 ts = timestamps[length - i - 1];
            if (state.liquiditySettled[ts]) return (_liquidityRoots[eid][ts], ts);
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
        uint256[] storage timestamps = _rootTimestamps[eid];
        uint256 length = timestamps.length;
        for (uint256 i; i < length && i < MAX_LOOP; ++i) {
            uint256 ts = timestamps[length - i - 1];
            if (areRootsFinalized(app, eid, ts)) return (_liquidityRoots[eid][ts], ts);
        }
    }

    /**
     * @notice Retrieves the last synced data root and its associated timestamp for a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @return root The last data root for the specified `eid`.
     * @return timestamp The timestamp associated with the last data root.
     */
    function getLastSyncedDataRoot(uint32 eid) public view returns (bytes32 root, uint256 timestamp) {
        uint256 length = _rootTimestamps[eid].length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = _rootTimestamps[eid][length - 1];
        root = _dataRoots[eid][timestamp];
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
        uint256[] storage timestamps = _rootTimestamps[eid];
        uint256 length = timestamps.length;
        for (uint256 i; i < length && i < MAX_LOOP; ++i) {
            uint256 ts = timestamps[length - i - 1];
            if (state.dataSettled[ts]) return (_dataRoots[eid][ts], ts);
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
        uint256[] storage timestamps = _rootTimestamps[eid];
        uint256 length = timestamps.length;
        for (uint256 i; i < length && i < MAX_LOOP; ++i) {
            uint256 ts = timestamps[length - i - 1];
            if (areRootsFinalized(app, eid, ts)) return (_dataRoots[eid][ts], ts);
        }
    }

    function isLiquidityRootSettled(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        return _remoteStates[app][eid].liquiditySettled[timestamp] || _liquidityRoots[eid][timestamp] == bytes32(0);
    }

    function isDataRootSettled(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        return _remoteStates[app][eid].dataSettled[timestamp] || _dataRoots[eid][timestamp] == bytes32(0);
    }

    function areRootsFinalized(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        RemoteState storage state = _remoteStates[app][eid];
        bool liquiditySettled = state.liquiditySettled[timestamp];
        bool dataSettled = state.dataSettled[timestamp];
        if (liquiditySettled && dataSettled) return true;
        if (liquiditySettled && _dataRoots[eid][timestamp] == bytes32(0)) return true;
        if (dataSettled && _liquidityRoots[eid][timestamp] == bytes32(0)) return true;
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

    function settleLiquidity(SettleLiquidityParams memory params) external onlySettler(msg.sender, params.app) {
        AppState storage localState = _appStates[params.app];
        bool syncMappedAccountsOnly = localState.syncMappedAccountsOnly;
        bool useCallbacks = localState.useCallbacks;

        RemoteState storage state = _remoteStates[params.app][params.eid];
        if (state.liquiditySettled[params.timestamp]) revert LiquidityAlreadySettled();
        state.liquiditySettled[params.timestamp] = true;

        int256 totalLiquidity;
        for (uint256 i; i < params.accounts.length; i++) {
            (address account, int256 liquidity) = (params.accounts[i], params.liquidity[i]);

            address _account = state.mappedAccounts[account];
            if (syncMappedAccountsOnly && _account == address(0)) continue;
            if (_account == address(0)) {
                _account = account;
            }

            SnapshotsLib.Snapshots storage snapshots = state.liquidity[_account];
            totalLiquidity -= state.liquidity[_account].getLastAsInt();
            snapshots.setAsInt(liquidity, params.timestamp);
            totalLiquidity += liquidity;

            if (useCallbacks) {
                try ILiquidityMatrixCallbacks(params.app).onUpdateLiquidity(
                    params.eid, params.timestamp, _account, liquidity
                ) { } catch (bytes memory reason) {
                    emit OnUpdateLiquidityFailure(params.eid, params.timestamp, _account, liquidity, reason);
                }
            }
        }

        state.totalLiquidity.setAsInt(totalLiquidity, params.timestamp);
        if (useCallbacks) {
            try ILiquidityMatrixCallbacks(params.app).onUpdateTotalLiquidity(
                params.eid, params.timestamp, totalLiquidity
            ) { } catch (bytes memory reason) {
                emit OnUpdateTotalLiquidityFailure(params.eid, params.timestamp, totalLiquidity, reason);
            }
        }

        emit SettleLiquidity(params.eid, params.app, _liquidityRoots[params.eid][params.timestamp], params.timestamp);
    }

    function settleData(SettleDataParams memory params) external onlySettler(msg.sender, params.app) {
        RemoteState storage state = _remoteStates[params.app][params.eid];
        if (state.dataSettled[params.timestamp]) revert DataAlreadySettled();
        state.dataSettled[params.timestamp] = true;

        for (uint256 i; i < params.keys.length; i++) {
            (bytes32 key, bytes memory value) = (params.keys[i], params.values[i]);

            bytes32 hash = keccak256(value);
            state.dataHashes[key].set(hash, params.timestamp);

            try ILiquidityMatrixCallbacks(params.app).onUpdateData(params.eid, params.timestamp, key, value) { }
            catch (bytes memory reason) {
                emit OnUpdateDataFailure(params.eid, params.timestamp, key, hash, reason);
            }
        }

        emit SettleData(params.eid, params.app, _dataRoots[params.eid][params.timestamp], params.timestamp);
    }

    /**
     * @notice Processes incoming liquidity and data roots for a specific chain.
     * @param eid The endpoint ID of the remote chain.
     * @param liquidityRoot The root hash of the liquidity Merkle tree.
     * @param dataRoot The root hash of the data Merkle tree.
     * @param timestamp The timestamp associated with these roots.
     */
    function _onReceiveRoots(uint32 eid, bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) internal {
        uint256 length = _rootTimestamps[eid].length;
        if (length > 0 && timestamp <= _rootTimestamps[eid][length - 1]) {
            emit OnReceiveStaleRoots(eid, liquidityRoot, dataRoot, timestamp);
            return;
        }

        _rootTimestamps[eid].push(timestamp);
        _liquidityRoots[eid][timestamp] = liquidityRoot;
        _dataRoots[eid][timestamp] = dataRoot;

        emit OnReceiveRoots(eid, liquidityRoot, dataRoot, timestamp);
    }

    function _onMapRemoteAccounts(address app, uint32 eid, address[] memory remotes, address[] memory locals)
        internal
    {
        // guaranteed that remotes and locals have same lengths
        // see `requestMapRemoteAccounts()`
        bool useCallbacks = _appStates[app].useCallbacks;
        RemoteState storage state = _remoteStates[app][eid];
        for (uint256 i; i < remotes.length; ++i) {
            (address remote, address local) = (remotes[i], locals[i]);
            // guaranteed that remote isn't address(0) nor local isn't address(0)
            // see `requestMapRemoteAccounts()`
            // only 1-1 mapping between remote-local is allowed and it can't be changed once set
            if (state.mappedAccounts[remote] != address(0)) revert RemoteAccountAlreadyMapped(eid, remote);
            if (state.localAccountMapped[local]) revert LocalAccountAlreadyMapped(eid, local);
            if (useCallbacks && !ILiquidityMatrixAccountMapper(app).shouldMapAccounts(eid, remote, local)) {
                revert AccountsNotMapped(eid, remote, local);
            }
            state.mappedAccounts[remote] = local;
            state.localAccountMapped[local] = true;

            // after mapping, `remote` account's liquidity is set to 0
            // and that amount is aggregated to `local` account's liquidity
            int256 prevRemote = state.liquidity[remote].getLastAsInt();
            state.liquidity[remote].setAsInt(0);
            int256 prevLocal = state.liquidity[local].getLastAsInt();
            state.liquidity[local].setAsInt(prevLocal + prevRemote);

            if (useCallbacks) {
                ILiquidityMatrixCallbacks(app).onMapAccounts(eid, remote, local);
            }

            emit MapAccount(app, eid, remote, local);
        }
    }
}
