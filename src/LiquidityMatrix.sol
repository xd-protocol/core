// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { ArrayLib } from "./libraries/ArrayLib.sol";
import { AddressLib } from "./libraries/AddressLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";
import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";
import { ILiquidityMatrix } from "./interfaces/ILiquidityMatrix.sol";
import { ILiquidityMatrixCallbacks } from "./interfaces/ILiquidityMatrixCallbacks.sol";
import { ILiquidityMatrixAccountMapper } from "./interfaces/ILiquidityMatrixAccountMapper.sol";
import { ISynchronizer } from "./interfaces/ISynchronizer.sol";

/**
 * @title LiquidityMatrix
 * @notice Core ledger contract managing hierarchical Merkle trees to track and synchronize liquidity and data updates across applications.
 * @dev This contract has no LayerZero dependencies and serves as the main state management layer.
 *      Cross-chain synchronization is handled by a pluggable Synchronizer contract.
 *
 * ## Architecture Overview:
 *
 * This contract maintains two main Merkle trees:
 * - **Main Liquidity Tree**: Tracks liquidity data for all registered applications.
 * - **Main Data Tree**: Tracks arbitrary key-value data for all registered applications.
 *
 * Each application maintains its own pair of Merkle trees:
 * - **Liquidity Tree**: Tracks account-specific liquidity data within the application.
 * - **Data Tree**: Tracks key-value pairs specific to the application.
 *
 * ## Relationship Between Main and App Trees:
 *
 * The roots of application-specific trees (liquidity and data) are added as nodes to their respective main trees.
 * This hierarchical structure allows efficient propagation of changes:
 * - When an application's liquidity or data tree is updated, its root is recalculated.
 * - The new root is propagated to the corresponding main tree, ensuring global consistency.
 *
 * ## ASCII Diagram:
 *
 *                         +--------------------------+
 *                         |    Main Liquidity Tree   |
 *                         |--------------------------|
 *                         |          Root            |
 *                         +--------------------------+
 *                                   |
 *               -------------------------------------------------
 *               |                               |               |
 *   +------------------------+   +------------------------+   +------------------------+
 *   | App A Liquidity Tree   |   | App B Liquidity Tree   |   | App C Liquidity Tree   |
 *   |------------------------|   |------------------------|   |------------------------|
 *   |          Root          |   |          Root          |   |          Root          |
 *   |------------------------|   |------------------------|   |------------------------|
 *   | + Node(Account X)      |   | + Node(Account Z)      |   | + Node(Account Y)      |
 *   | + Node(Account Y)      |   | + Node(Account W)      |   | + Node(Account Z)      |
 *   +------------------------+   +------------------------+   +------------------------+
 *
 *                         +--------------------------+
 *                         |     Main Data Tree       |
 *                         |--------------------------|
 *                         |          Root            |
 *                         +--------------------------+
 *                                   |
 *               -------------------------------------------------
 *               |                               |               |
 *   +------------------------+   +------------------------+   +------------------------+
 *   | App A Data Tree        |   | App B Data Tree        |   | App C Data Tree        |
 *   |------------------------|   |------------------------|   |------------------------|
 *   |          Root          |   |          Root          |   |          Root          |
 *   |------------------------|   |------------------------|   |------------------------|
 *   | + Node(Key 1)          |   | + Node(Key A)          |   | + Node(Key X)          |
 *   | + Node(Key 2)          |   | + Node(Key B)          |   | + Node(Key Y)          |
 *   +------------------------+   +------------------------+   +------------------------+
 *
 * ## Lifecycle of a Root (Remote State):
 *
 * A root progresses through the following states:
 *
 * 1. **None**:
 *    - The initial state where no root exists for a given chain and timestamp.
 *
 * 2. **Received**:
 *    - Roots are received via `onReceiveRoots` and stored in `_liquidityRoots` or `_dataRoots` for their respective timestamps.
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
 * ## Key Functionalities:
 *
 * 1. **App Registration**:
 *    - Applications must register to start using the contract.
 *    - During registration, their individual liquidity and data trees are initialized.
 *
 * 2. **Updating Liquidity**:
 *    - Liquidity updates are recorded in the app's liquidity tree.
 *    - The new liquidity tree root is propagated to the main liquidity tree.
 *
 * 3. **Updating Data**:
 *    - Key-value data updates are recorded in the app's data tree.
 *    - The new data tree root is propagated to the main data tree.
 *
 * 4. **Cross-Chain Settlement**:
 *    - Settlers process roots from remote chains without proof verification (trust-based).
 *    - Updates snapshots and triggers application-specific callbacks.
 *
 * 5. **Tree Root Retrieval**:
 *    - Allows querying of the current roots of the main liquidity and data trees.
 *    - Enables synchronization across chains or with off-chain systems.
 */
contract LiquidityMatrix is ReentrancyGuard, Ownable, ILiquidityMatrix {
    using ArrayLib for uint256[];
    using AddressLib for address;
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using SnapshotsLib for SnapshotsLib.Snapshots;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Represents the state of a registered application
     * @param registered Whether the application is registered
     * @param syncMappedAccountsOnly If true, only syncs liquidity for mapped accounts
     * @param useCallbacks If true, triggers callbacks to the app on state updates
     * @param settler Address authorized to settle roots for this app
     * @param totalLiquidity Snapshots tracking total liquidity over time
     * @param liquidity Account-specific liquidity snapshots
     * @param liquidityTree Merkle tree of account liquidities
     * @param dataHashes Snapshots of data value hashes
     * @param dataTree Merkle tree of data key-value pairs
     */
    struct AppState {
        bool registered;
        bool syncMappedAccountsOnly;
        bool useCallbacks;
        address settler;
        SnapshotsLib.Snapshots totalLiquidity;
        mapping(address account => SnapshotsLib.Snapshots) liquidity;
        MerkleTreeLib.Tree liquidityTree;
        mapping(bytes32 key => SnapshotsLib.Snapshots) dataHashes;
        MerkleTreeLib.Tree dataTree;
    }

    /**
     * @notice Represents the state of a remote application on another chain
     * @param app Address of the remote application
     * @param mappedAccounts Maps remote accounts to local accounts
     * @param localAccountMapped Tracks which local accounts are already mapped
     * @param totalLiquidity Snapshots tracking total liquidity from the remote chain
     * @param liquidity Account-specific liquidity snapshots from the remote chain
     * @param dataHashes Snapshots of data value hashes from the remote chain
     * @param liquiditySettled Tracks which liquidity roots have been settled
     * @param dataSettled Tracks which data roots have been settled
     */
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
        uint256 lastSettledLiquidityTimestamp;
        uint256 lastSettledDataTimestamp;
        uint256 lastFinalizedTimestamp;
    }

    mapping(address app => AppState) internal _appStates;
    MerkleTreeLib.Tree internal _mainLiquidityTree;
    MerkleTreeLib.Tree internal _mainDataTree;

    mapping(address => bool) internal _isSettlerWhitelisted;
    mapping(address app => mapping(uint32 eid => RemoteState)) internal _remoteStates;
    mapping(uint32 eid => uint256[]) internal _rootTimestamps; // TODO: make it automatically ordered
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) internal _liquidityRoots;
    mapping(uint32 eid => mapping(uint256 timestamp => bytes32)) internal _dataRoots;

    address public synchronizer;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp(address _app) {
        if (!_appStates[_app].registered) revert AppNotRegistered();
        _;
    }

    modifier onlySettler(address _account, address _app) {
        AppState storage state = _appStates[_app];
        if (!state.registered) revert AppNotRegistered();
        if (state.settler != _account && !_isSettlerWhitelisted[_account]) revert Forbidden();
        _;
    }

    modifier onlySynchronizer() {
        if (msg.sender != synchronizer) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) { }

    /*//////////////////////////////////////////////////////////////
                        LOCAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the current main tree roots and timestamp
     * @return liquidityRoot The main liquidity tree root
     * @return dataRoot The main data tree root
     * @return timestamp The current block timestamp
     */
    function getMainRoots() public view returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) {
        return (getMainLiquidityRoot(), getMainDataRoot(), block.timestamp);
    }

    /**
     * @notice Gets the current root of the main liquidity tree
     * @return The main liquidity tree root
     */
    function getMainLiquidityRoot() public view returns (bytes32) {
        return _mainLiquidityTree.root;
    }

    /**
     * @notice Gets the current root of the main data tree
     * @return The main data tree root
     */
    function getMainDataRoot() public view returns (bytes32) {
        return _mainDataTree.root;
    }

    /**
     * @notice Returns the settings for a registered application
     * @param app The application address
     * @return registered Whether the app is registered
     * @return syncMappedAccountsOnly Whether to sync only mapped accounts
     * @return useCallbacks Whether callbacks are enabled
     * @return settler The authorized settler address
     */
    function getAppSetting(address app)
        external
        view
        returns (bool registered, bool syncMappedAccountsOnly, bool useCallbacks, address settler)
    {
        AppState storage state = _appStates[app];
        return (state.registered, state.syncMappedAccountsOnly, state.useCallbacks, state.settler);
    }

    /**
     * @notice Gets the current root of an app's liquidity tree
     * @param app The application address
     * @return The liquidity tree root
     */
    function getLocalLiquidityRoot(address app) public view returns (bytes32) {
        return _appStates[app].liquidityTree.root;
    }

    /**
     * @notice Gets the current root of an app's data tree
     * @param app The application address
     * @return The data tree root
     */
    function getLocalDataRoot(address app) public view returns (bytes32) {
        return _appStates[app].dataTree.root;
    }

    /**
     * @notice Gets the current local liquidity for an account in an app
     * @param app The application address
     * @param account The account to query
     * @return The current liquidity amount
     */
    function getLocalLiquidity(address app, address account) external view returns (int256) {
        return _appStates[app].liquidity[account].getLastAsInt();
    }

    /**
     * @notice Gets the local liquidity for an account at a specific timestamp
     * @param app The application address
     * @param account The account to query
     * @param timestamp The timestamp to query
     * @return The liquidity amount at the timestamp
     */
    function getLocalLiquidityAt(address app, address account, uint256 timestamp) external view returns (int256) {
        return _appStates[app].liquidity[account].getAsInt(timestamp);
    }

    /**
     * @notice Gets the current total local liquidity for an app
     * @param app The application address
     * @return The current total liquidity
     */
    function getLocalTotalLiquidity(address app) external view returns (int256) {
        return _appStates[app].totalLiquidity.getLastAsInt();
    }

    /**
     * @notice Gets the total local liquidity for an app at a specific timestamp
     * @param app The application address
     * @param timestamp The timestamp to query
     * @return The total liquidity at the timestamp
     */
    function getLocalTotalLiquidityAt(address app, uint256 timestamp) external view returns (int256) {
        return _appStates[app].totalLiquidity.getAsInt(timestamp);
    }

    /**
     * @notice Gets the current hash of data stored under a key for an app
     * @param app The application address
     * @param key The data key
     * @return The current data hash
     */
    function getLocalDataHash(address app, bytes32 key) external view returns (bytes32) {
        return _appStates[app].dataHashes[key].getLast();
    }

    /**
     * @notice Gets the data hash for a key at a specific timestamp
     * @param app The application address
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return The data hash at the timestamp
     */
    function getLocalDataHashAt(address app, bytes32 key, uint256 timestamp) external view returns (bytes32) {
        return _appStates[app].dataHashes[key].get(timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        REMOTE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if an account is whitelisted as a settler
     * @param account The account to check
     * @return Whether the account is whitelisted
     */
    function isSettlerWhitelisted(address account) external view returns (bool) {
        return _isSettlerWhitelisted[account];
    }

    /**
     * @notice Gets the remote app address for a given chain
     * @param app The local application address
     * @param eid The endpoint ID of the remote chain
     * @return The remote application address
     */
    function getRemoteApp(address app, uint32 eid) external view returns (address) {
        return _remoteStates[app][eid].app;
    }

    /**
     * @notice Gets the local account mapped to a remote account
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param remote The remote account address
     * @return local The mapped local account address
     */
    function getMappedAccount(address app, uint32 eid, address remote) public view returns (address) {
        return _remoteStates[app][eid].mappedAccounts[remote];
    }

    function getLocalAccount(address app, uint32 eid, address remote) public view returns (address) {
        address mapped = getMappedAccount(app, eid, remote);
        if (mapped != address(0)) {
            return mapped;
        }
        return remote;
    }

    /**
     * @notice Checks if a local account is already mapped to a remote account
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param local The local account address
     * @return Whether the local account is mapped
     */
    function isLocalAccountMapped(address app, uint32 eid, address local) external view returns (bool) {
        return _remoteStates[app][eid].localAccountMapped[local];
    }

    /**
     * @notice Gets the last received liquidity root from a remote chain
     * @param eid The endpoint ID of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedLiquidityRoot(uint32 eid) public view returns (bytes32 root, uint256 timestamp) {
        uint256 length = _rootTimestamps[eid].length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = _rootTimestamps[eid][length - 1];
        if (timestamp != 0) {
            root = _liquidityRoots[eid][timestamp];
        }
    }

    /**
     * @notice Gets the last settled liquidity root for an app on a specific chain
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp of the settled root
     */
    function getLastSettledLiquidityRoot(address app, uint32 eid)
        public
        view
        returns (bytes32 root, uint256 timestamp)
    {
        timestamp = _remoteStates[app][eid].lastSettledLiquidityTimestamp;
        if (timestamp != 0) {
            root = _liquidityRoots[eid][timestamp];
        }
    }

    /**
     * @notice Gets the last finalized liquidity root (both liquidity and data settled)
     * @dev A root is finalized when both liquidity and data roots are settled for the same timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp of the finalized root
     */
    function getLastFinalizedLiquidityRoot(address app, uint32 eid)
        public
        view
        returns (bytes32 root, uint256 timestamp)
    {
        timestamp = _remoteStates[app][eid].lastFinalizedTimestamp;
        if (timestamp != 0) {
            root = _liquidityRoots[eid][timestamp];
        }
    }

    /**
     * @notice Gets the liquidity root at a specific timestamp
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to query
     * @return root The liquidity root at the timestamp
     */
    function getLiquidityRootAt(uint32 eid, uint256 timestamp) external view returns (bytes32 root) {
        return _liquidityRoots[eid][timestamp];
    }

    /**
     * @notice Gets the last received data root from a remote chain
     * @param eid The endpoint ID of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedDataRoot(uint32 eid) public view returns (bytes32 root, uint256 timestamp) {
        uint256 length = _rootTimestamps[eid].length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = _rootTimestamps[eid][length - 1];
        if (timestamp != 0) {
            root = _dataRoots[eid][timestamp];
        }
    }

    /**
     * @notice Gets the last settled data root for an app on a specific chain
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp of the settled root
     */
    function getLastSettledDataRoot(address app, uint32 eid) public view returns (bytes32 root, uint256 timestamp) {
        timestamp = _remoteStates[app][eid].lastSettledDataTimestamp;
        if (timestamp != 0) {
            root = _dataRoots[eid][timestamp];
        }
    }

    /**
     * @notice Gets the last finalized data root for an app on a specific chain
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp of the finalized root
     */
    function getLastFinalizedDataRoot(address app, uint32 eid)
        external
        view
        returns (bytes32 root, uint256 timestamp)
    {
        timestamp = _remoteStates[app][eid].lastFinalizedTimestamp;
        if (timestamp != 0) {
            root = _dataRoots[eid][timestamp];
        }
    }

    /**
     * @notice Gets the data root at a specific timestamp
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to query
     * @return root The data root at the timestamp
     */
    function getDataRootAt(uint32 eid, uint256 timestamp) external view returns (bytes32 root) {
        return _dataRoots[eid][timestamp];
    }

    /**
     * @notice Checks if a liquidity root has been settled for an app
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the liquidity root is settled
     */
    function isLiquiditySettled(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        return _remoteStates[app][eid].liquiditySettled[timestamp];
    }

    /**
     * @notice Checks if a data root has been settled for an app
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the data root is settled
     */
    function isDataSettled(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        return _remoteStates[app][eid].dataSettled[timestamp];
    }

    /**
     * @notice Checks if both roots are finalized for a given timestamp
     * @dev Returns true if both liquidity and data are settled
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the roots are finalized
     */
    function isFinalized(address app, uint32 eid, uint256 timestamp) public view returns (bool) {
        RemoteState storage state = _remoteStates[app][eid];
        return state.liquiditySettled[timestamp] && state.dataSettled[timestamp];
    }

    /**
     * @notice Gets the total liquidity across all chains where liquidity is settled
     * @dev Aggregates local liquidity and remote liquidity from all configured chains
     * @param app The application address
     * @return liquidity The total settled liquidity
     */
    function getSettledTotalLiquidity(address app) external view returns (int256 liquidity) {
        liquidity = _appStates[app].totalLiquidity.getLastAsInt();

        // Add remote liquidity from all configured chains
        ISynchronizer sync = ISynchronizer(synchronizer);
        uint256 length = sync.eidsLength();
        for (uint256 i; i < length; ++i) {
            uint32 eid = sync.eidAt(i);
            uint256 timestamp = _remoteStates[app][eid].lastSettledLiquidityTimestamp;
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][eid].totalLiquidity.getAsInt(timestamp);
        }
    }

    /**
     * @notice Gets the total liquidity across all chains where both roots are finalized
     * @dev More conservative than settled - requires both liquidity and data roots to be settled
     * @param app The application address
     * @return liquidity The total finalized liquidity
     */
    function getFinalizedTotalLiquidity(address app) external view returns (int256 liquidity) {
        liquidity = _appStates[app].totalLiquidity.getLastAsInt();

        // Add remote liquidity from all configured chains where both roots are settled
        ISynchronizer sync = ISynchronizer(synchronizer);
        uint256 length = sync.eidsLength();
        for (uint256 i; i < length; ++i) {
            uint32 eid = sync.eidAt(i);
            uint256 timestamp = _remoteStates[app][eid].lastFinalizedTimestamp;
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][eid].totalLiquidity.getAsInt(timestamp);
        }
    }

    /**
     * @notice Gets the total liquidity at the timestamp
     * @param app The application address
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity at the latest valid timestamp
     */
    function getTotalLiquidityAt(address app, uint256 timestamp) external view returns (int256 liquidity) {
        liquidity = _appStates[app].totalLiquidity.getAsInt(timestamp);

        // Add remote liquidity
        ISynchronizer sync = ISynchronizer(synchronizer);
        uint256 length = sync.eidsLength();
        for (uint256 i; i < length; ++i) {
            uint32 eid = sync.eidAt(i);
            liquidity += _remoteStates[app][eid].totalLiquidity.getAsInt(timestamp);
        }
    }

    /**
     * @notice Gets the liquidity for an account across all chains where liquidity is settled
     * @param app The application address
     * @param account The account address
     * @return liquidity The total settled liquidity for the account
     */
    function getSettledLiquidity(address app, address account) external view returns (int256 liquidity) {
        liquidity = _appStates[app].liquidity[account].getLastAsInt();

        // Add remote liquidity from all configured chains
        ISynchronizer sync = ISynchronizer(synchronizer);
        uint256 length = sync.eidsLength();
        for (uint256 i; i < length; ++i) {
            uint32 eid = sync.eidAt(i);
            uint256 timestamp = _remoteStates[app][eid].lastSettledLiquidityTimestamp;
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][eid].liquidity[account].getAsInt(timestamp);
        }
    }

    /**
     * @notice Gets the liquidity for an account across all chains where both roots are finalized
     * @param app The application address
     * @param account The account address
     * @return liquidity The total finalized liquidity for the account
     */
    function getFinalizedLiquidity(address app, address account) external view returns (int256 liquidity) {
        liquidity = _appStates[app].liquidity[account].getLastAsInt();

        // Add remote liquidity from all configured chains where both roots are settled
        ISynchronizer sync = ISynchronizer(synchronizer);
        uint256 length = sync.eidsLength();
        for (uint256 i; i < length; ++i) {
            uint32 eid = sync.eidAt(i);
            uint256 timestamp = _remoteStates[app][eid].lastFinalizedTimestamp;
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][eid].liquidity[account].getAsInt(timestamp);
        }
    }

    /**
     * @notice Gets the liquidity for an account at the timestamp
     * @param app The application address
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The liquidity at the latest valid timestamp
     */
    function getLiquidityAt(address app, address account, uint256 timestamp) external view returns (int256 liquidity) {
        liquidity = _appStates[app].liquidity[account].getAsInt(timestamp);

        // Add remote liquidity
        ISynchronizer sync = ISynchronizer(synchronizer);
        uint256 length = sync.eidsLength();
        for (uint256 i; i < length; ++i) {
            uint32 eid = sync.eidAt(i);
            liquidity += _remoteStates[app][eid].liquidity[account].getAsInt(timestamp);
        }
    }

    /**
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return liquidity The settled remote total liquidity
     */
    function getSettledRemoteTotalLiquidity(address app, uint32 eid) external view returns (int256 liquidity) {
        (, uint256 timestamp) = getLastSettledLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteTotalLiquidityAt(app, eid, timestamp);
    }

    /**
     * @notice Gets the total liquidity from a remote chain at the last finalized timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return liquidity The finalized remote total liquidity
     */
    function getFinalizedRemoteTotalLiquidity(address app, uint32 eid) external view returns (int256 liquidity) {
        (, uint256 timestamp) = getLastFinalizedLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteTotalLiquidityAt(app, eid, timestamp);
    }

    /**
     * @notice Gets the total liquidity from a remote chain at a specific timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to query
     * @return liquidity The remote total liquidity at the timestamp
     */
    function getRemoteTotalLiquidityAt(address app, uint32 eid, uint256 timestamp) public view returns (int256) {
        return _remoteStates[app][eid].totalLiquidity.getAsInt(timestamp);
    }

    /**
     * @notice Gets the liquidity for an account from a remote chain at the last settled timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param account The account address
     * @return liquidity The settled remote liquidity for the account
     */
    function getSettledRemoteLiquidity(address app, uint32 eid, address account)
        external
        view
        returns (int256 liquidity)
    {
        (, uint256 timestamp) = getLastSettledLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteLiquidityAt(app, eid, account, timestamp);
    }

    /**
     * @notice Gets the liquidity for an account from a remote chain at the last finalized timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param account The account address
     * @return liquidity The finalized remote liquidity for the account
     */
    function getFinalizedRemoteLiquidity(address app, uint32 eid, address account)
        external
        view
        returns (int256 liquidity)
    {
        (, uint256 timestamp) = getLastFinalizedLiquidityRoot(app, eid);
        if (timestamp == 0) return 0;
        return getRemoteLiquidityAt(app, eid, account, timestamp);
    }

    /**
     * @notice Gets the liquidity for an account from a remote chain at a specific timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The remote liquidity at the timestamp
     */
    function getRemoteLiquidityAt(address app, uint32 eid, address account, uint256 timestamp)
        public
        view
        returns (int256)
    {
        return _remoteStates[app][eid].liquidity[account].getAsInt(timestamp);
    }

    /**
     * @notice Gets the data hash from a remote chain at the last settled timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param key The data key
     * @return value The settled remote data hash
     */
    function getSettledRemoteDataHash(address app, uint32 eid, bytes32 key) external view returns (bytes32 value) {
        uint256 timestamp = _remoteStates[app][eid].lastSettledDataTimestamp;
        if (timestamp == 0) return 0;
        return getRemoteDataHashAt(app, eid, key, timestamp);
    }

    /**
     * @notice Gets the data hash from a remote chain at the last finalized timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param key The data key
     * @return value The finalized remote data hash
     */
    function getFinalizedRemoteDataHash(address app, uint32 eid, bytes32 key) external view returns (bytes32 value) {
        uint256 timestamp = _remoteStates[app][eid].lastFinalizedTimestamp;
        if (timestamp == 0) return 0;
        return getRemoteDataHashAt(app, eid, key, timestamp);
    }

    /**
     * @notice Gets the data hash from a remote chain at a specific timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return value The remote data hash at the timestamp
     */
    function getRemoteDataHashAt(address app, uint32 eid, bytes32 key, uint256 timestamp)
        public
        view
        returns (bytes32)
    {
        return _remoteStates[app][eid].dataHashes[key].get(timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                      LOCAL STATE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new application with the LiquidityMatrix
     * @dev Initializes the app's liquidity and data trees
     * @param syncMappedAccountsOnly If true, only syncs liquidity for mapped accounts
     * @param useCallbacks If true, triggers callbacks to the app on state updates
     * @param settler Address authorized to settle roots for this app
     */
    function registerApp(bool syncMappedAccountsOnly, bool useCallbacks, address settler) external {
        address app = msg.sender;
        if (_appStates[app].registered) revert AppAlreadyRegistered();

        AppState storage state = _appStates[app];
        state.registered = true;
        state.syncMappedAccountsOnly = syncMappedAccountsOnly;
        state.useCallbacks = useCallbacks;
        state.settler = settler;

        emit RegisterApp(app, syncMappedAccountsOnly, useCallbacks, settler);
    }

    /**
     * @notice Updates whether to sync only mapped accounts
     * @param syncMappedAccountsOnly New setting value
     */
    function updateSyncMappedAccountsOnly(bool syncMappedAccountsOnly) external onlyApp(msg.sender) {
        _appStates[msg.sender].syncMappedAccountsOnly = syncMappedAccountsOnly;
        emit UpdateSyncMappedAccountsOnly(msg.sender, syncMappedAccountsOnly);
    }

    /**
     * @notice Updates whether to use callbacks for state updates
     * @param useCallbacks New setting value
     */
    function updateUseCallbacks(bool useCallbacks) external onlyApp(msg.sender) {
        _appStates[msg.sender].useCallbacks = useCallbacks;
        emit UpdateUseCallbacks(msg.sender, useCallbacks);
    }

    /**
     * @notice Updates the authorized settler for the app
     * @param settler New settler address
     */
    function updateSettler(address settler) external onlyApp(msg.sender) {
        _appStates[msg.sender].settler = settler;
        emit UpdateSettler(msg.sender, settler);
    }

    /**
     * @notice Updates the liquidity for an account in the calling app
     * @dev Updates the app's liquidity tree and propagates to the main tree
     * @param account The account to update
     * @param liquidity The new liquidity amount
     * @return mainTreeIndex The index in the main liquidity tree
     * @return appTreeIndex The index in the app's liquidity tree
     */
    function updateLocalLiquidity(address account, int256 liquidity)
        external
        onlyApp(msg.sender)
        returns (uint256 mainTreeIndex, uint256 appTreeIndex)
    {
        address app = msg.sender;
        AppState storage state = _appStates[app];

        appTreeIndex = state.liquidityTree.update(bytes32(uint256(uint160(account))), bytes32(uint256(liquidity)));
        mainTreeIndex = _mainLiquidityTree.update(bytes32(uint256(uint160(app))), state.liquidityTree.root);

        int256 oldTotalLiquidity = state.totalLiquidity.getLastAsInt();
        int256 oldLiquidity = state.liquidity[account].getLastAsInt();
        state.liquidity[account].setAsInt(liquidity);
        int256 newTotalLiquidity = oldTotalLiquidity - oldLiquidity + liquidity;
        state.totalLiquidity.setAsInt(newTotalLiquidity);

        emit UpdateLocalLiquidity(app, mainTreeIndex, account, liquidity, appTreeIndex, block.timestamp);
    }

    /**
     * @notice Updates arbitrary data for the calling app
     * @dev Updates the app's data tree and propagates to the main tree
     * @param key The data key
     * @param value The data value
     * @return mainTreeIndex The index in the main data tree
     * @return appTreeIndex The index in the app's data tree
     */
    function updateLocalData(bytes32 key, bytes memory value)
        external
        onlyApp(msg.sender)
        returns (uint256 mainTreeIndex, uint256 appTreeIndex)
    {
        address app = msg.sender;
        AppState storage state = _appStates[app];

        bytes32 hash = keccak256(value);
        appTreeIndex = state.dataTree.update(key, hash);
        mainTreeIndex = _mainDataTree.update(bytes32(uint256(uint160(app))), state.dataTree.root);

        state.dataHashes[key].set(hash);

        emit UpdateLocalData(app, mainTreeIndex, key, value, hash, appTreeIndex, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                      REMOTE STATE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Links the calling app to a remote app on another chain
     * @param eid The endpoint ID of the remote chain
     * @param remoteApp The address of the app on the remote chain
     */
    function updateRemoteApp(uint32 eid, address remoteApp) external onlyApp(msg.sender) {
        _remoteStates[msg.sender][eid].app = remoteApp;
        emit UpdateRemoteApp(msg.sender, eid, remoteApp);
    }

    /**
     * @notice Updates the whitelist status of a settler
     * @dev Only callable by owner
     * @param account The settler account
     * @param whitelisted Whether to whitelist or remove from whitelist
     */
    function updateSettlerWhitelisted(address account, bool whitelisted) external onlyOwner {
        _isSettlerWhitelisted[account] = whitelisted;
        emit UpdateSettlerWhitelisted(account, whitelisted);
    }

    /**
     * @notice Sets the synchronizer contract address
     * @dev Only callable by owner. The synchronizer handles all cross-chain communication.
     * @param _synchronizer Address of the synchronizer contract
     */
    function setSynchronizer(address _synchronizer) external onlyOwner {
        synchronizer = _synchronizer;
        emit UpdateSynchronizer(_synchronizer);
    }

    /**
     * @notice Requests mapping of remote accounts to local accounts on another chain
     * @dev Forwards the request to the synchronizer for cross-chain messaging
     * @param eid Target chain endpoint ID
     * @param remoteApp Address of the app on the remote chain
     * @param locals Array of local account addresses to map
     * @param remotes Array of remote account addresses to map
     * @param gasLimit Gas limit for the cross-chain message
     */
    function requestMapRemoteAccounts(
        uint32 eid,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        uint128 gasLimit
    ) external payable onlyApp(msg.sender) {
        if (remotes.length != locals.length) revert InvalidLengths();
        for (uint256 i; i < locals.length; ++i) {
            (address local, address remote) = (locals[i], remotes[i]);
            if (local == address(0) || remote == address(0)) revert InvalidAddress();
        }

        // Forward to synchronizer
        ISynchronizer(synchronizer).requestMapRemoteAccounts{ value: msg.value }(
            eid, remoteApp, locals, remotes, gasLimit
        );
    }

    /**
     * @notice Receives and stores Merkle roots from remote chains
     * @dev Called by the synchronizer after successful cross-chain sync
     * @param eid The endpoint ID of the remote chain
     * @param liquidityRoot The liquidity Merkle root from the remote chain
     * @param dataRoot The data Merkle root from the remote chain
     * @param timestamp The timestamp when the roots were generated
     */
    function onReceiveRoots(uint32 eid, bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp)
        external
        onlySynchronizer
    {
        if (_rootTimestamps[eid].length == 0 || _rootTimestamps[eid][_rootTimestamps[eid].length - 1] != timestamp) {
            _rootTimestamps[eid].insertSorted(timestamp);
        }

        _liquidityRoots[eid][timestamp] = liquidityRoot;
        _dataRoots[eid][timestamp] = dataRoot;

        emit OnReceiveRoots(eid, liquidityRoot, dataRoot, timestamp);
    }

    /**
     * @notice Settles liquidity data from a remote chain for a specific app
     * @dev Trusts the settler to provide valid data without proof verification.
     *      Updates liquidity snapshots and triggers callbacks if enabled.
     * @param params Settlement parameters including app, eid, timestamp, accounts and liquidity values
     */
    function settleLiquidity(SettleLiquidityParams memory params) external onlySettler(msg.sender, params.app) {
        AppState storage localState = _appStates[params.app];
        bool syncMappedAccountsOnly = localState.syncMappedAccountsOnly;
        bool useCallbacks = localState.useCallbacks;

        RemoteState storage state = _remoteStates[params.app][params.eid];
        if (state.liquiditySettled[params.timestamp]) revert LiquidityAlreadySettled();
        state.liquiditySettled[params.timestamp] = true;
        if (params.timestamp > state.lastSettledLiquidityTimestamp) {
            state.lastSettledLiquidityTimestamp = params.timestamp;
            if (params.timestamp > state.lastFinalizedTimestamp && state.dataSettled[params.timestamp]) {
                state.lastFinalizedTimestamp = params.timestamp;
            }
        }

        int256 totalLiquidity;
        // Process each account's liquidity update
        for (uint256 i; i < params.accounts.length; i++) {
            (address account, int256 liquidity) = (params.accounts[i], params.liquidity[i]);

            // Check if account is mapped to a local account
            address _account = state.mappedAccounts[account];
            if (syncMappedAccountsOnly && _account == address(0)) continue;
            if (_account == address(0)) {
                _account = account;
            }

            // Update liquidity snapshot and track total change
            SnapshotsLib.Snapshots storage snapshots = state.liquidity[_account];
            totalLiquidity -= state.liquidity[_account].getLastAsInt();
            snapshots.setAsInt(liquidity, params.timestamp);
            totalLiquidity += liquidity;

            // Trigger callback if enabled, catching any failures
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

    /**
     * @notice Settles arbitrary data from a remote chain for a specific app
     * @dev Trusts the settler to provide valid data without proof verification.
     *      Updates data hashes and triggers callbacks if enabled.
     * @param params Settlement parameters including app, eid, timestamp, keys and values
     */
    function settleData(SettleDataParams memory params) external onlySettler(msg.sender, params.app) {
        RemoteState storage state = _remoteStates[params.app][params.eid];
        if (state.dataSettled[params.timestamp]) revert DataAlreadySettled();
        state.dataSettled[params.timestamp] = true;
        if (params.timestamp > state.lastSettledDataTimestamp) {
            state.lastSettledDataTimestamp = params.timestamp;
            if (params.timestamp > state.lastFinalizedTimestamp && state.liquiditySettled[params.timestamp]) {
                state.lastFinalizedTimestamp = params.timestamp;
            }
        }

        bool useCallbacks = _appStates[params.app].useCallbacks;
        // Process each key-value pair
        for (uint256 i; i < params.keys.length; i++) {
            (bytes32 key, bytes memory value) = (params.keys[i], params.values[i]);
            bytes32 valueHash = keccak256(value);
            state.dataHashes[key].set(valueHash, params.timestamp);

            // Trigger callback if enabled, catching any failures
            if (useCallbacks) {
                try ILiquidityMatrixCallbacks(params.app).onUpdateData(params.eid, params.timestamp, key, value) { }
                catch (bytes memory reason) {
                    emit OnUpdateDataFailure(params.eid, params.timestamp, key, value, reason);
                }
            }
        }

        emit SettleData(params.eid, params.app, _dataRoots[params.eid][params.timestamp], params.timestamp);
    }

    /**
     * @notice Processes remote account mapping requests received from other chains
     * @dev Called by synchronizer when receiving cross-chain mapping requests.
     *      Validates mappings and consolidates liquidity from remote to local accounts.
     * @param _fromEid Source chain endpoint ID
     * @param _localApp Local app address that should process this request
     * @param _message Encoded remote and local account arrays
     */
    function onReceiveMapRemoteAccountRequests(uint32 _fromEid, address _localApp, bytes memory _message)
        external
        onlySynchronizer
    {
        (address[] memory remotes, address[] memory locals) = abi.decode(_message, (address[], address[]));

        // Verify the app is registered
        if (!_appStates[_localApp].registered) revert AppNotRegistered();

        RemoteState storage state = _remoteStates[_localApp][_fromEid];

        bool[] memory shouldMap = new bool[](remotes.length);
        if (ILiquidityMatrixAccountMapper(_localApp).shouldMapAccounts.selector == bytes4(0)) {
            for (uint256 i; i < remotes.length; ++i) {
                shouldMap[i] = true;
            }
        } else {
            for (uint256 i; i < remotes.length; ++i) {
                shouldMap[i] =
                    ILiquidityMatrixAccountMapper(_localApp).shouldMapAccounts(_fromEid, remotes[i], locals[i]);
            }
        }

        for (uint256 i; i < remotes.length; ++i) {
            if (!shouldMap[i]) continue;

            address remote = remotes[i];
            address local = locals[i];

            if (state.mappedAccounts[remote] != address(0)) revert RemoteAccountAlreadyMapped(_fromEid, remote);
            if (state.localAccountMapped[local]) revert LocalAccountAlreadyMapped(_fromEid, local);

            state.mappedAccounts[remote] = local;
            state.localAccountMapped[local] = true;

            int256 remoteLiquidity = state.liquidity[remote].getLastAsInt();
            state.liquidity[remote].setAsInt(0);

            int256 currentLocalLiquidity = state.liquidity[local].getLastAsInt();
            state.liquidity[local].setAsInt(currentLocalLiquidity + remoteLiquidity);

            emit MapRemoteAccount(_localApp, _fromEid, remote, local);
        }
    }
}
