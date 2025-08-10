// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { ArrayLib } from "./libraries/ArrayLib.sol";
import { AddressLib } from "./libraries/AddressLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";
import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";
import { JumpTableLib } from "./libraries/JumpTableLib.sol";
import { ILiquidityMatrix } from "./interfaces/ILiquidityMatrix.sol";
import { IGateway } from "./interfaces/IGateway.sol";
import { IGatewayApp } from "./interfaces/IGatewayApp.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILiquidityMatrixCallbacks } from "./interfaces/ILiquidityMatrixCallbacks.sol";
import { ILiquidityMatrixAccountMapper } from "./interfaces/ILiquidityMatrixAccountMapper.sol";

/**
 * @title LiquidityMatrix
 * @notice Core ledger contract managing hierarchical Merkle trees to track and synchronize liquidity and data updates across applications.
 * @dev This contract serves as the main state management layer with minimal LayerZero dependencies (only for MessagingReceipt type).
 *      Cross-chain synchronization is handled through the IGateway interface, allowing for pluggable gateway implementations.
 *      Implements IGatewayApp to handle cross-chain read operations and message reception.
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
 * 1. **App Registration & Configuration**:
 *    - Applications must register to start using the contract.
 *    - During registration, their individual liquidity and data trees are initialized.
 *    - Apps can configure sync behavior, callbacks, and authorized settlers.
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
 *    - Supports both per-app settlers and globally whitelisted settlers.
 *
 * 5. **Gateway Integration**:
 *    - Configurable gateway for cross-chain communication.
 *    - Handles cross-chain read operations via IGatewayApp interface.
 *    - Supports syncing operations across multiple chains.
 *
 * 6. **Account Mapping**:
 *    - Maps remote chain accounts to local accounts for unified liquidity tracking.
 *    - Prevents duplicate mappings and maintains bidirectional lookups.
 *
 * 7. **Tree Root Retrieval**:
 *    - Allows querying of the current roots of the main liquidity and data trees.
 *    - Enables synchronization across chains or with off-chain systems.
 */
contract LiquidityMatrix is ReentrancyGuard, Ownable, ILiquidityMatrix, IGatewayApp {
    using ArrayLib for uint256[];
    using AddressLib for address;
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using SnapshotsLib for SnapshotsLib.Snapshots;
    using JumpTableLib for JumpTableLib.JumpTable;

    /*//////////////////////////////////////////////////////////////
                                TYPES
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
     * @param mappedAccounts Maps remote accounts to local accounts
     * @param localAccountMapped Tracks which local accounts are already mapped
     * @param totalLiquidity Snapshots tracking total liquidity from the remote chain
     * @param liquidity Account-specific liquidity snapshots from the remote chain
     * @param dataHashes Snapshots of data value hashes from the remote chain
     * @param liquiditySettled Tracks which liquidity roots have been settled
     * @param dataSettled Tracks which data roots have been settled
     * @param lastSettledLiquidityTimestamp Timestamp of the last settled liquidity root
     * @param lastSettledDataTimestamp Timestamp of the last settled data root
     * @param lastFinalizedTimestamp Timestamp when both liquidity and data roots were last finalized
     */
    struct RemoteState {
        mapping(address remote => address local) mappedAccounts;
        mapping(address local => bool) localAccountMapped;
        mapping(uint256 version => RemoteVersionedState) versioned;
    }

    struct RemoteVersionedState {
        SnapshotsLib.Snapshots totalLiquidity;
        mapping(address account => SnapshotsLib.Snapshots) liquidity;
        mapping(bytes32 key => SnapshotsLib.Snapshots) dataHashes;
        // settlement
        mapping(uint64 timestamp => bool) liquiditySettled;
        mapping(uint64 timestamp => bool) dataSettled;
        uint64 lastSettledLiquidityTimestamp;
        uint64 lastSettledDataTimestamp;
        uint64 lastFinalizedTimestamp;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    // Binary lifting table for efficient reorg timestamp lookups
    JumpTableLib.JumpTable internal _reorgTable;

    mapping(address app => AppState) internal _appStates;
    MerkleTreeLib.Tree internal _mainLiquidityTree;
    MerkleTreeLib.Tree internal _mainDataTree;

    mapping(address => bool) internal _isSettlerWhitelisted;
    mapping(address app => mapping(bytes32 chainUID => RemoteState)) internal _remoteStates;
    mapping(bytes32 chainUID => uint64[]) internal _rootTimestamps;
    mapping(bytes32 chainUID => mapping(uint256 version => mapping(uint64 timestamp => bytes32))) internal
        _liquidityRoots;
    mapping(bytes32 chainUID => mapping(uint256 version => mapping(uint64 timestamp => bytes32))) internal _dataRoots;

    // Command identifiers for different message types
    uint16 internal constant CMD_SYNC = 1;
    uint16 internal constant MAP_REMOTE_ACCOUNTS = 1;

    // Gateway for cross-chain operations
    IGateway public gateway;
    // Address authorized to initiate sync operations
    address public syncer;
    // Rate limiting: timestamp of last sync request
    uint64 internal _lastSyncRequestTimestamp;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp() {
        if (!_appStates[msg.sender].registered) revert Forbidden();
        _;
    }

    modifier onlySettler(address _app) {
        AppState storage state = _appStates[_app];
        if (!state.registered) revert AppNotRegistered();
        if (state.settler != msg.sender && !_isSettlerWhitelisted[msg.sender]) revert Forbidden();
        _;
    }

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Forbidden();
        _;
    }

    modifier onlySyncer() {
        if (msg.sender != syncer) revert Forbidden();
        _;
    }

    modifier onlyAppOrMatrix() {
        // Direct calls must be from registered apps
        (bool registered,,,) = this.getAppSetting(msg.sender);
        if (!registered) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) { }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function reorgTimestampsLength() external view returns (uint256) {
        return _reorgTable.length();
    }

    function reorgTimestamps(uint256 index) external view returns (uint64) {
        return _reorgTable.valueAt(index);
    }

    function currentVersion() public view returns (uint256) {
        return _reorgTable.length() + 1;
    }

    /**
     * @notice Gets the version for a given timestamp
     * @dev Uses the binary lifting table to find which version a timestamp belongs to
     * @param timestamp The timestamp to query
     * @return The version number for the timestamp
     */
    function getVersionForTimestamp(uint64 timestamp) public view returns (uint256) {
        // findUpperBound returns the index of first reorg timestamp > target timestamp
        // This index + 1 gives us the version number
        uint256 upperBoundIndex = _reorgTable.findUpperBound(timestamp);
        return upperBoundIndex + 1;
    }

    /*//////////////////////////////////////////////////////////////
                        LOCAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the current main tree roots and timestamp
     * @return liquidityRoot The main liquidity tree root
     * @return dataRoot The main data tree root
     * @return timestamp The current block timestamp
     */
    function getMainRoots() public view returns (bytes32 liquidityRoot, bytes32 dataRoot, uint64 timestamp) {
        return (getMainLiquidityRoot(), getMainDataRoot(), uint64(block.timestamp));
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
    function getLocalLiquidityAt(address app, address account, uint64 timestamp) external view returns (int256) {
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
    function getLocalTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256) {
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
    function getLocalDataHashAt(address app, bytes32 key, uint64 timestamp) external view returns (bytes32) {
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
     * @notice Gets the local account mapped to a remote account
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param remote The remote account address
     * @return local The mapped local account address
     */
    function getMappedAccount(address app, bytes32 chainUID, address remote) public view returns (address) {
        return _remoteStates[app][chainUID].mappedAccounts[remote];
    }

    function getLocalAccount(address app, bytes32 chainUID, address remote) public view returns (address) {
        address mapped = getMappedAccount(app, chainUID, remote);
        if (mapped != address(0)) {
            return mapped;
        }
        return remote;
    }

    /**
     * @notice Checks if a local account is already mapped to a remote account
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param local The local account address
     * @return Whether the local account is mapped
     */
    function isLocalAccountMapped(address app, bytes32 chainUID, address local) external view returns (bool) {
        return _remoteStates[app][chainUID].localAccountMapped[local];
    }

    /**
     * @notice Gets the last received liquidity root from a remote chain
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedLiquidityRoot(bytes32 chainUID) public view returns (bytes32 root, uint64 timestamp) {
        uint256 length = _rootTimestamps[chainUID].length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = _rootTimestamps[chainUID][length - 1];
        if (timestamp != 0) {
            root = _liquidityRoots[chainUID][currentVersion()][timestamp];
        }
    }

    /**
     * @notice Gets the last settled liquidity root for an app on a specific chain
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp of the settled root
     */
    function getLastSettledLiquidityRoot(address app, bytes32 chainUID)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        uint256 version = currentVersion();
        timestamp = _remoteStates[app][chainUID].versioned[version].lastSettledLiquidityTimestamp;
        if (timestamp != 0) {
            root = _liquidityRoots[chainUID][version][timestamp];
        }
    }

    /**
     * @notice Gets the last finalized liquidity root (both liquidity and data settled)
     * @dev A root is finalized when both liquidity and data roots are settled for the same timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp of the finalized root
     */
    function getLastFinalizedLiquidityRoot(address app, bytes32 chainUID)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        uint256 version = currentVersion();
        timestamp = _remoteStates[app][chainUID].versioned[version].lastFinalizedTimestamp;
        if (timestamp != 0) {
            root = _liquidityRoots[chainUID][version][timestamp];
        }
    }

    /**
     * @notice Gets the liquidity root at a specific timestamp
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to query
     * @return root The liquidity root at the timestamp
     */
    function getLiquidityRootAt(bytes32 chainUID, uint64 timestamp) external view returns (bytes32 root) {
        uint256 version = getVersionForTimestamp(uint64(timestamp));
        return _liquidityRoots[chainUID][version][uint64(timestamp)];
    }

    /**
     * @notice Gets the last received data root from a remote chain
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedDataRoot(bytes32 chainUID) public view returns (bytes32 root, uint64 timestamp) {
        uint256 length = _rootTimestamps[chainUID].length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = _rootTimestamps[chainUID][length - 1];
        if (timestamp != 0) {
            root = _dataRoots[chainUID][currentVersion()][timestamp];
        }
    }

    /**
     * @notice Gets the last settled data root for an app on a specific chain
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp of the settled root
     */
    function getLastSettledDataRoot(address app, bytes32 chainUID)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        uint256 version = currentVersion();
        timestamp = _remoteStates[app][chainUID].versioned[version].lastSettledDataTimestamp;
        if (timestamp != 0) {
            root = _dataRoots[chainUID][version][timestamp];
        }
    }

    /**
     * @notice Gets the last finalized data root for an app on a specific chain
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp of the finalized root
     */
    function getLastFinalizedDataRoot(address app, bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp)
    {
        uint256 version = currentVersion();
        timestamp = _remoteStates[app][chainUID].versioned[version].lastFinalizedTimestamp;
        if (timestamp != 0) {
            root = _dataRoots[chainUID][version][timestamp];
        }
    }

    /**
     * @notice Gets the data root at a specific timestamp
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to query
     * @return root The data root at the timestamp
     */
    function getDataRootAt(bytes32 chainUID, uint64 timestamp) external view returns (bytes32 root) {
        uint256 version = getVersionForTimestamp(uint64(timestamp));
        return _dataRoots[chainUID][version][uint64(timestamp)];
    }

    /**
     * @notice Checks if a liquidity root has been settled for an app
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the liquidity root is settled
     */
    function isLiquiditySettled(address app, bytes32 chainUID, uint64 timestamp) public view returns (bool) {
        uint256 version = getVersionForTimestamp(uint64(timestamp));
        return _remoteStates[app][chainUID].versioned[version].liquiditySettled[uint64(timestamp)];
    }

    /**
     * @notice Checks if a data root has been settled for an app
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the data root is settled
     */
    function isDataSettled(address app, bytes32 chainUID, uint64 timestamp) public view returns (bool) {
        uint256 version = getVersionForTimestamp(uint64(timestamp));
        return _remoteStates[app][chainUID].versioned[version].dataSettled[uint64(timestamp)];
    }

    /**
     * @notice Checks if both roots are finalized for a given timestamp
     * @dev Returns true if both liquidity and data are settled
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the roots are finalized
     */
    function isFinalized(address app, bytes32 chainUID, uint64 timestamp) public view returns (bool) {
        uint256 version = getVersionForTimestamp(uint64(timestamp));
        RemoteState storage state = _remoteStates[app][chainUID];
        return state.versioned[version].liquiditySettled[uint64(timestamp)]
            && state.versioned[version].dataSettled[uint64(timestamp)];
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
        uint256 length = gateway.chainUIDsLength();
        for (uint256 i; i < length; ++i) {
            bytes32 chainUID = gateway.chainUIDAt(i);
            uint256 version = currentVersion();
            uint64 timestamp = _remoteStates[app][chainUID].versioned[version].lastSettledLiquidityTimestamp;
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][chainUID].versioned[version].totalLiquidity.getAsInt(timestamp);
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
        uint256 length = gateway.chainUIDsLength();
        for (uint256 i; i < length; ++i) {
            bytes32 chainUID = gateway.chainUIDAt(i);
            uint256 version = currentVersion();
            uint64 timestamp = _remoteStates[app][chainUID].versioned[version].lastFinalizedTimestamp;
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][chainUID].versioned[version].totalLiquidity.getAsInt(timestamp);
        }
    }

    /**
     * @notice Gets the total liquidity at the timestamp
     * @param app The application address
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity at the latest valid timestamp
     */
    function getTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256 liquidity) {
        liquidity = _appStates[app].totalLiquidity.getAsInt(timestamp);

        // Add remote liquidity
        uint256 length = gateway.chainUIDsLength();
        uint256 version = getVersionForTimestamp(timestamp);
        for (uint256 i; i < length; ++i) {
            bytes32 chainUID = gateway.chainUIDAt(i);
            liquidity += _remoteStates[app][chainUID].versioned[version].totalLiquidity.getAsInt(timestamp);
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
        uint256 length = gateway.chainUIDsLength();
        for (uint256 i; i < length; ++i) {
            bytes32 chainUID = gateway.chainUIDAt(i);
            uint256 version = currentVersion();
            uint64 timestamp = _remoteStates[app][chainUID].versioned[version].lastSettledLiquidityTimestamp;
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][chainUID].versioned[version].liquidity[account].getAsInt(timestamp);
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
        uint256 length = gateway.chainUIDsLength();
        for (uint256 i; i < length; ++i) {
            bytes32 chainUID = gateway.chainUIDAt(i);
            uint256 version = currentVersion();
            uint64 timestamp = _remoteStates[app][chainUID].versioned[version].lastFinalizedTimestamp;
            if (timestamp == 0) continue;
            liquidity += _remoteStates[app][chainUID].versioned[version].liquidity[account].getAsInt(timestamp);
        }
    }

    /**
     * @notice Gets the liquidity for an account at the timestamp
     * @param app The application address
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The liquidity at the latest valid timestamp
     */
    function getLiquidityAt(address app, address account, uint64 timestamp) external view returns (int256 liquidity) {
        liquidity = _appStates[app].liquidity[account].getAsInt(timestamp);

        // Add remote liquidity
        uint256 length = gateway.chainUIDsLength();
        uint256 version = getVersionForTimestamp(timestamp);
        for (uint256 i; i < length; ++i) {
            bytes32 chainUID = gateway.chainUIDAt(i);
            liquidity += _remoteStates[app][chainUID].versioned[version].liquidity[account].getAsInt(timestamp);
        }
    }

    /**
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return liquidity The settled remote total liquidity
     */
    function getSettledRemoteTotalLiquidity(address app, bytes32 chainUID) external view returns (int256 liquidity) {
        (, uint64 timestamp) = getLastSettledLiquidityRoot(app, chainUID);
        if (timestamp == 0) return 0;
        return getRemoteTotalLiquidityAt(app, chainUID, timestamp);
    }

    /**
     * @notice Gets the total liquidity from a remote chain at the last finalized timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return liquidity The finalized remote total liquidity
     */
    function getFinalizedRemoteTotalLiquidity(address app, bytes32 chainUID) external view returns (int256 liquidity) {
        (, uint64 timestamp) = getLastFinalizedLiquidityRoot(app, chainUID);
        if (timestamp == 0) return 0;
        return getRemoteTotalLiquidityAt(app, chainUID, timestamp);
    }

    /**
     * @notice Gets the total liquidity from a remote chain at a specific timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to query
     * @return liquidity The remote total liquidity at the timestamp
     */
    function getRemoteTotalLiquidityAt(address app, bytes32 chainUID, uint64 timestamp) public view returns (int256) {
        uint256 version = getVersionForTimestamp(timestamp);
        return _remoteStates[app][chainUID].versioned[version].totalLiquidity.getAsInt(timestamp);
    }

    /**
     * @notice Gets the liquidity for an account from a remote chain at the last settled timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param account The account address
     * @return liquidity The settled remote liquidity for the account
     */
    function getSettledRemoteLiquidity(address app, bytes32 chainUID, address account)
        external
        view
        returns (int256 liquidity)
    {
        (, uint64 timestamp) = getLastSettledLiquidityRoot(app, chainUID);
        if (timestamp == 0) return 0;
        return getRemoteLiquidityAt(app, chainUID, account, timestamp);
    }

    /**
     * @notice Gets the liquidity for an account from a remote chain at the last finalized timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param account The account address
     * @return liquidity The finalized remote liquidity for the account
     */
    function getFinalizedRemoteLiquidity(address app, bytes32 chainUID, address account)
        external
        view
        returns (int256 liquidity)
    {
        (, uint64 timestamp) = getLastFinalizedLiquidityRoot(app, chainUID);
        if (timestamp == 0) return 0;
        return getRemoteLiquidityAt(app, chainUID, account, timestamp);
    }

    /**
     * @notice Gets the liquidity for an account from a remote chain at a specific timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The remote liquidity at the timestamp
     */
    function getRemoteLiquidityAt(address app, bytes32 chainUID, address account, uint64 timestamp)
        public
        view
        returns (int256)
    {
        uint256 version = getVersionForTimestamp(timestamp);
        return _remoteStates[app][chainUID].versioned[version].liquidity[account].getAsInt(timestamp);
    }

    /**
     * @notice Gets the data hash from a remote chain at the last settled timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param key The data key
     * @return value The settled remote data hash
     */
    function getSettledRemoteDataHash(address app, bytes32 chainUID, bytes32 key)
        external
        view
        returns (bytes32 value)
    {
        uint256 version = currentVersion();
        uint64 timestamp = _remoteStates[app][chainUID].versioned[version].lastSettledDataTimestamp;
        if (timestamp == 0) return 0;
        return getRemoteDataHashAt(app, chainUID, key, timestamp);
    }

    /**
     * @notice Gets the data hash from a remote chain at the last finalized timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param key The data key
     * @return value The finalized remote data hash
     */
    function getFinalizedRemoteDataHash(address app, bytes32 chainUID, bytes32 key)
        external
        view
        returns (bytes32 value)
    {
        uint256 version = currentVersion();
        uint64 timestamp = _remoteStates[app][chainUID].versioned[version].lastFinalizedTimestamp;
        if (timestamp == 0) return 0;
        return getRemoteDataHashAt(app, chainUID, key, timestamp);
    }

    /**
     * @notice Gets the data hash from a remote chain at a specific timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return value The remote data hash at the timestamp
     */
    function getRemoteDataHashAt(address app, bytes32 chainUID, bytes32 key, uint64 timestamp)
        public
        view
        returns (bytes32)
    {
        uint256 version = getVersionForTimestamp(timestamp);
        return _remoteStates[app][chainUID].versioned[version].dataHashes[key].get(timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new reorg timestamp
     * @dev Only callable by owner. The timestamp must be greater than the last reorg timestamp.
     * @param timestamp The timestamp of the reorg
     */
    function addReorg(uint64 timestamp) external onlyOwner {
        // Check if timestamp is valid (must be greater than last reorg timestamp)
        uint256 length = _reorgTable.length();
        if (length > 0) {
            uint64 lastTimestamp = _reorgTable.valueAt(length - 1);
            if (timestamp <= lastTimestamp) {
                revert InvalidTimestamp();
            }
        }

        _reorgTable.append(timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        LOCAL STATE LOGIC
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
    function updateSyncMappedAccountsOnly(bool syncMappedAccountsOnly) external onlyApp {
        _appStates[msg.sender].syncMappedAccountsOnly = syncMappedAccountsOnly;
        emit UpdateSyncMappedAccountsOnly(msg.sender, syncMappedAccountsOnly);
    }

    /**
     * @notice Updates whether to use callbacks for state updates
     * @param useCallbacks New setting value
     */
    function updateUseCallbacks(bool useCallbacks) external onlyApp {
        _appStates[msg.sender].useCallbacks = useCallbacks;
        emit UpdateUseCallbacks(msg.sender, useCallbacks);
    }

    /**
     * @notice Updates the authorized settler for the app
     * @param settler New settler address
     */
    function updateSettler(address settler) external onlyApp {
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
        onlyApp
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

        emit UpdateLocalLiquidity(app, mainTreeIndex, account, liquidity, appTreeIndex, uint64(block.timestamp));
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
        onlyApp
        returns (uint256 mainTreeIndex, uint256 appTreeIndex)
    {
        address app = msg.sender;
        AppState storage state = _appStates[app];

        bytes32 hash = keccak256(value);
        appTreeIndex = state.dataTree.update(key, hash);
        mainTreeIndex = _mainDataTree.update(bytes32(uint256(uint160(app))), state.dataTree.root);

        state.dataHashes[key].set(hash);

        emit UpdateLocalData(app, mainTreeIndex, key, value, hash, appTreeIndex, uint64(block.timestamp));
    }

    /*//////////////////////////////////////////////////////////////
                        REMOTE STATE LOGIC
    //////////////////////////////////////////////////////////////*/

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
     * @notice Sets the gateway contract address
     * @dev Only callable by owner. The gateway handles all cross-chain communication.
     * @param _gateway Address of the gateway contract
     */
    function setGateway(address _gateway) external onlyOwner {
        gateway = IGateway(_gateway);
        emit SetGateway(_gateway);
    }

    /**
     * @notice Sets the syncer address
     * @dev Only callable by owner. Syncer is authorized to initiate sync operations.
     * @param _syncer Address authorized to sync
     */
    function setSyncer(address _syncer) external onlyOwner {
        syncer = _syncer;
        emit SetSyncer(_syncer);
    }

    /**
     * @notice Updates the read target for a specific chain
     * @dev Updates where to read from on the remote chain
     * @param chainUID The chain UID
     * @param target The target address on the remote chain
     */
    function updateReadTarget(bytes32 chainUID, bytes32 target) external onlyOwner {
        gateway.updateReadTarget(chainUID, target);
    }

    /**
     * @notice Returns the configured chains from the gateway
     * @return Array of configured chain UIDs
     */
    function getConfiguredChains() external view returns (bytes32[] memory) {
        uint256 length = gateway.chainUIDsLength();
        bytes32[] memory chains = new bytes32[](length);
        for (uint256 i; i < length; ++i) {
            chains[i] = gateway.chainUIDAt(i);
        }
        return chains;
    }

    /**
     * @notice Returns the chain configurations from the gateway
     * @dev Delegates to gateway.chainConfigs()
     * @return chainUIDs Array of chain unique identifiers
     * @return confirmations Array of confirmation requirements for each chain
     */
    function chainConfigs() external view returns (bytes32[] memory chainUIDs, uint16[] memory confirmations) {
        return gateway.chainConfigs();
    }

    /**
     * @notice Receives and stores Merkle roots from remote chains
     * @dev Called by the synchronizer after successful cross-chain sync
     * @param chainUID The chain unique identifier of the remote chain
     * @param liquidityRoot The liquidity Merkle root from the remote chain
     * @param dataRoot The data Merkle root from the remote chain
     * @param timestamp The timestamp when the roots were generated
     */
    function onReceiveRoots(bytes32 chainUID, bytes32 liquidityRoot, bytes32 dataRoot, uint64 timestamp) external {
        // Allow calls from gateway or from this contract (via onRead)
        if (msg.sender != address(gateway) && msg.sender != address(this)) revert Forbidden();
        if (
            _rootTimestamps[chainUID].length == 0
                || _rootTimestamps[chainUID][_rootTimestamps[chainUID].length - 1] != timestamp
        ) {
            _rootTimestamps[chainUID].push(timestamp);
        }

        uint256 version = currentVersion();
        _liquidityRoots[chainUID][version][timestamp] = liquidityRoot;
        _dataRoots[chainUID][version][timestamp] = dataRoot;

        emit OnReceiveRoots(chainUID, liquidityRoot, dataRoot, timestamp);
    }

    /**
     * @notice Settles liquidity data from a remote chain for a specific app
     * @dev Trusts the settler to provide valid data without proof verification.
     *      Updates liquidity snapshots and triggers callbacks if enabled.
     * @param params Settlement parameters including app, chainUID, timestamp, accounts and liquidity values
     */
    function settleLiquidity(SettleLiquidityParams memory params) external onlySettler(params.app) {
        AppState storage localState = _appStates[params.app];
        bool syncMappedAccountsOnly = localState.syncMappedAccountsOnly;
        bool useCallbacks = localState.useCallbacks;

        RemoteState storage state = _remoteStates[params.app][params.chainUID];
        if (state.versioned[params.version].liquiditySettled[params.timestamp]) {
            revert LiquidityAlreadySettled();
        }
        state.versioned[params.version].liquiditySettled[params.timestamp] = true;
        if (params.timestamp > state.versioned[params.version].lastSettledLiquidityTimestamp) {
            state.versioned[params.version].lastSettledLiquidityTimestamp = params.timestamp;
            if (
                params.timestamp > state.versioned[params.version].lastFinalizedTimestamp
                    && state.versioned[params.version].dataSettled[params.timestamp]
            ) {
                state.versioned[params.version].lastFinalizedTimestamp = params.timestamp;
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
            SnapshotsLib.Snapshots storage snapshots = state.versioned[params.version].liquidity[_account];
            totalLiquidity -= state.versioned[params.version].liquidity[_account].getLastAsInt();
            snapshots.setAsInt(liquidity, params.timestamp);
            totalLiquidity += liquidity;

            // Trigger callback if enabled, catching any failures
            if (useCallbacks) {
                try ILiquidityMatrixCallbacks(params.app).onSettleLiquidity(
                    params.chainUID, params.timestamp, _account, liquidity
                ) { } catch (bytes memory reason) {
                    emit OnSettleLiquidityFailure(params.chainUID, params.timestamp, _account, liquidity, reason);
                }
            }
        }

        state.versioned[params.version].totalLiquidity.setAsInt(totalLiquidity, params.timestamp);
        if (useCallbacks) {
            try ILiquidityMatrixCallbacks(params.app).onSettleTotalLiquidity(
                params.chainUID, params.timestamp, totalLiquidity
            ) { } catch (bytes memory reason) {
                emit OnSettleTotalLiquidityFailure(params.chainUID, params.timestamp, totalLiquidity, reason);
            }
        }

        emit SettleLiquidity(
            params.chainUID,
            params.app,
            _liquidityRoots[params.chainUID][params.version][params.timestamp],
            params.timestamp
        );
    }

    /**
     * @notice Settles arbitrary data from a remote chain for a specific app
     * @dev Trusts the settler to provide valid data without proof verification.
     *      Updates data hashes and triggers callbacks if enabled.
     * @param params Settlement parameters including app, chainUID, timestamp, keys and values
     */
    function settleData(SettleDataParams memory params) external onlySettler(params.app) {
        RemoteState storage state = _remoteStates[params.app][params.chainUID];
        if (state.versioned[params.version].dataSettled[params.timestamp]) revert DataAlreadySettled();
        state.versioned[params.version].dataSettled[params.timestamp] = true;
        if (params.timestamp > state.versioned[params.version].lastSettledDataTimestamp) {
            state.versioned[params.version].lastSettledDataTimestamp = params.timestamp;
            if (
                params.timestamp > state.versioned[params.version].lastFinalizedTimestamp
                    && state.versioned[params.version].liquiditySettled[params.timestamp]
            ) {
                state.versioned[params.version].lastFinalizedTimestamp = params.timestamp;
            }
        }

        bool useCallbacks = _appStates[params.app].useCallbacks;
        // Process each key-value pair
        for (uint256 i; i < params.keys.length; i++) {
            (bytes32 key, bytes memory value) = (params.keys[i], params.values[i]);
            bytes32 valueHash = keccak256(value);
            state.versioned[params.version].dataHashes[key].set(valueHash, params.timestamp);

            // Trigger callback if enabled, catching any failures
            if (useCallbacks) {
                try ILiquidityMatrixCallbacks(params.app).onSettleData(params.chainUID, params.timestamp, key, value) {
                } catch (bytes memory reason) {
                    emit OnSettleDataFailure(params.chainUID, params.timestamp, key, value, reason);
                }
            }
        }

        emit SettleData(
            params.chainUID, params.app, _dataRoots[params.chainUID][params.version][params.timestamp], params.timestamp
        );
    }

    /**
     * @notice Processes remote account mapping requests received from other chains
     * @dev Called by synchronizer when receiving cross-chain mapping requests.
     *      Validates mappings and consolidates liquidity from remote to local accounts.
     * @param _fromChainUID Source chain unique identifier
     * @param _localApp Local app address that should process this request
     * @param _message Encoded remote and local account arrays
     */
    function onReceiveMapRemoteAccountRequests(bytes32 _fromChainUID, address _localApp, bytes memory _message)
        external
    {
        // Allow calls from gateway or from this contract (via onReceive)
        if (msg.sender != address(gateway) && msg.sender != address(this)) revert Forbidden();
        (address[] memory remotes, address[] memory locals) = abi.decode(_message, (address[], address[]));

        // Verify the app is registered
        if (!_appStates[_localApp].registered) revert AppNotRegistered();

        RemoteState storage state = _remoteStates[_localApp][_fromChainUID];

        bool[] memory shouldMap = new bool[](remotes.length);
        if (ILiquidityMatrixAccountMapper(_localApp).shouldMapAccounts.selector == bytes4(0)) {
            for (uint256 i; i < remotes.length; ++i) {
                shouldMap[i] = true;
            }
        } else {
            for (uint256 i; i < remotes.length; ++i) {
                shouldMap[i] =
                    ILiquidityMatrixAccountMapper(_localApp).shouldMapAccounts(_fromChainUID, remotes[i], locals[i]);
            }
        }

        for (uint256 i; i < remotes.length; ++i) {
            if (!shouldMap[i]) continue;

            address remote = remotes[i];
            address local = locals[i];

            if (state.mappedAccounts[remote] != address(0)) revert RemoteAccountAlreadyMapped(_fromChainUID, remote);
            if (state.localAccountMapped[local]) revert LocalAccountAlreadyMapped(_fromChainUID, local);

            state.mappedAccounts[remote] = local;
            state.localAccountMapped[local] = true;

            uint256 version = currentVersion();
            int256 remoteLiquidity = state.versioned[version].liquidity[remote].getLastAsInt();
            state.versioned[version].liquidity[remote].setAsInt(0);

            int256 currentLocalLiquidity = state.versioned[version].liquidity[local].getLastAsInt();
            state.versioned[version].liquidity[local].setAsInt(currentLocalLiquidity + remoteLiquidity);

            emit MapRemoteAccount(_localApp, _fromChainUID, remote, local);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SYNC LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initiates a sync operation to fetch roots from all configured chains
     * @dev Only callable by the authorized syncer. Rate limited to once per block.
     * @param data Encoded (uint128 gasLimit, address refundTo) for the cross-chain operation
     * @return receipt The messaging receipt from the gateway
     */
    function sync(bytes memory data) external payable onlySyncer returns (MessagingReceipt memory receipt) {
        // Rate limiting: only one sync per block
        if (block.timestamp <= _lastSyncRequestTimestamp) revert AlreadyRequested();
        _lastSyncRequestTimestamp = uint64(block.timestamp);

        // Build callData for getMainRoots
        bytes memory callData = abi.encodeWithSelector(ILiquidityMatrix.getMainRoots.selector);

        // Store command type in extra for callback
        bytes memory extra = abi.encode(CMD_SYNC);

        // Use gateway.read() for the sync operation
        bytes32 guid = gateway.read{ value: msg.value }(callData, extra, 256 * 3, data);

        emit Sync(msg.sender);

        // Return a receipt with the guid for compatibility
        receipt.guid = guid;
        return receipt;
    }

    /**
     * @notice Quotes the messaging fee for syncing all configured chains
     * @param gasLimit The gas limit for the operation
     * @return fee The estimated messaging fee in native token
     */
    function quoteSync(uint128 gasLimit) external view returns (uint256 fee) {
        bytes memory callData = abi.encodeWithSelector(ILiquidityMatrix.getMainRoots.selector);
        return gateway.quoteRead(address(this), callData, 256 * 3, gasLimit);
    }

    /*//////////////////////////////////////////////////////////////
                      IGatewayApp IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Processes responses from the gateway's read protocol
     * @dev Implementation of IGatewayApp.reduce
     * @param requests Array of request information for each chain
     * @param callData The original callData sent in the read request
     * @param responses Array of responses from each chain
     * @return The aggregated result containing synced chain roots and timestamps
     */
    function reduce(IGatewayApp.Request[] calldata requests, bytes calldata callData, bytes[] calldata responses)
        external
        pure
        returns (bytes memory)
    {
        // Only process if this is a sync command (check callData selector)
        bytes4 selector = bytes4(callData);
        if (selector == ILiquidityMatrix.getMainRoots.selector) {
            bytes32[] memory chainUIDs = new bytes32[](requests.length);
            bytes32[] memory liquidityRoots = new bytes32[](requests.length);
            bytes32[] memory dataRoots = new bytes32[](requests.length);
            uint256[] memory timestamps = new uint256[](requests.length);

            for (uint256 i; i < chainUIDs.length; ++i) {
                chainUIDs[i] = requests[i].chainUID;
                (liquidityRoots[i], dataRoots[i], timestamps[i]) = abi.decode(responses[i], (bytes32, bytes32, uint256));
            }

            return abi.encode(CMD_SYNC, chainUIDs, liquidityRoots, dataRoots, timestamps);
        } else {
            revert InvalidCmd();
        }
    }

    /**
     * @notice Receives the aggregated result from the gateway after a read operation
     * @dev Implementation of IGatewayApp.onRead
     * @param message The aggregated message containing roots from all chains
     * @param extra Extra data passed during the read request (contains command type)
     */
    function onRead(bytes calldata message, bytes calldata extra) external onlyGateway {
        uint16 cmdType = abi.decode(extra, (uint16));
        if (cmdType == CMD_SYNC) {
            (
                ,
                bytes32[] memory chainUIDs,
                bytes32[] memory liquidityRoots,
                bytes32[] memory dataRoots,
                uint256[] memory timestamps
            ) = abi.decode(message, (uint16, bytes32[], bytes32[], bytes32[], uint256[]));

            // Process each chain's roots
            for (uint256 i; i < chainUIDs.length; ++i) {
                this.onReceiveRoots(chainUIDs[i], liquidityRoots[i], dataRoots[i], uint64(timestamps[i]));
            }
        }
    }

    /**
     * @notice Handles incoming messages from the gateway
     * @dev Implementation of IGatewayApp.onReceive
     * @param sourceChainId The source chain identifier
     * @param message The message payload
     */
    function onReceive(bytes32 sourceChainId, bytes calldata message) external onlyGateway {
        // Decode message type
        uint16 msgType = abi.decode(message, (uint16));

        if (msgType == MAP_REMOTE_ACCOUNTS) {
            (,, address toApp, address[] memory remotes, address[] memory locals) =
                abi.decode(message, (uint16, address, address, address[], address[]));

            // Process account mapping request
            this.onReceiveMapRemoteAccountRequests(sourceChainId, toApp, abi.encode(remotes, locals));
        }
    }

    /**
     * @notice Quotes the fee for mapping remote accounts
     * @param chainUID Target chain unique identifier
     * @param localAccount Address of the local account
     * @param remoteApp Address of the app on the remote chain
     * @param remotes Array of remote account addresses
     * @param locals Array of local account addresses to map to
     * @param gasLimit Gas limit for the cross-chain message
     * @return fee The estimated messaging fee
     */
    function quoteRequestMapRemoteAccounts(
        bytes32 chainUID,
        address localAccount,
        address remoteApp,
        address[] memory remotes,
        address[] memory locals,
        uint128 gasLimit
    ) external view returns (uint256 fee) {
        // Encode message
        bytes memory message = abi.encode(MAP_REMOTE_ACCOUNTS, localAccount, remoteApp, remotes, locals);

        // Quote the fee from gateway
        return gateway.quoteSendMessage(chainUID, address(this), message, gasLimit);
    }

    /**
     * @notice Requests mapping of remote accounts to local accounts on another chain
     * @dev Uses the gateway to send cross-chain messages
     * @param chainUID Target chain unique identifier
     * @param remoteApp Address of the app on the remote chain
     * @param locals Array of local account addresses to map
     * @param remotes Array of remote account addresses to map
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters for cross-chain messaging
     * @return guid The unique identifier for this cross-chain request
     */
    function requestMapRemoteAccounts(
        bytes32 chainUID,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        bytes memory data
    ) external payable onlyAppOrMatrix returns (bytes32 guid) {
        // Validate input arrays
        if (remotes.length != locals.length) revert InvalidLengths();
        for (uint256 i; i < locals.length; ++i) {
            (address local, address remote) = (locals[i], remotes[i]);
            if (local == address(0) || remote == address(0)) revert InvalidAddress();
        }

        // Send cross-chain message via gateway
        bytes memory message = abi.encode(MAP_REMOTE_ACCOUNTS, msg.sender, remoteApp, locals, remotes);
        guid = gateway.sendMessage{ value: msg.value }(chainUID, message, data);

        emit RequestMapRemoteAccounts(msg.sender, chainUID, remoteApp, remotes, locals);
    }
}
