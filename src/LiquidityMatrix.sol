// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { ILocalAppChronicleDeployer } from "./interfaces/ILocalAppChronicleDeployer.sol";
import { IRemoteAppChronicleDeployer } from "./interfaces/IRemoteAppChronicleDeployer.sol";
import { ArrayLib } from "./libraries/ArrayLib.sol";
import { AddressLib } from "./libraries/AddressLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";
import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";
import { ILiquidityMatrix } from "./interfaces/ILiquidityMatrix.sol";
import { IGateway } from "./interfaces/IGateway.sol";
import { IGatewayApp } from "./interfaces/IGatewayApp.sol";
import { ILiquidityMatrixHook } from "./interfaces/ILiquidityMatrixHook.sol";
import { ILiquidityMatrixAccountMapper } from "./interfaces/ILiquidityMatrixAccountMapper.sol";
import { ILocalAppChronicle } from "./interfaces/ILocalAppChronicle.sol";
import { IRemoteAppChronicle } from "./interfaces/IRemoteAppChronicle.sol";

/**
 * @title LiquidityMatrix
 * @notice Core ledger contract managing versioned state through chronicle contracts for blockchain reorganization protection.
 * @dev This contract serves as the main coordination layer for cross-chain liquidity tracking with version-based state isolation.
 *      Cross-chain synchronization is handled through the IGateway interface, allowing for pluggable gateway implementations.
 *      Implements IGatewayApp to handle cross-chain read operations and message reception.
 *
 * ## Architecture Overview:
 *
 * This contract coordinates versioned state management through chronicle contracts:
 * - **LocalAppChronicle**: Manages local state (liquidity, data) for each app version
 * - **RemoteAppChronicle**: Manages remote state settlements for each app/chain/version combination
 * - **Version System**: Isolates state changes to protect against blockchain reorganizations
 *
 * Each version maintains its own set of Merkle trees:
 * - **Top Liquidity Tree**: Aggregates liquidity roots from all apps in that version
 * - **Top Data Tree**: Aggregates data roots from all apps in that version
 *
 * ## Relationship Between Chronicles and Trees:
 *
 * The roots of application-specific trees (liquidity and data) are added as nodes to their respective top trees.
 * This hierarchical structure allows efficient propagation of changes:
 * - When an application's liquidity or data tree is updated, its root is recalculated.
 * - The new root is propagated to the corresponding top tree, ensuring global consistency.
 *
 * ## ASCII Diagram:
 *
 *                         +--------------------------+
 *                         |    Top Liquidity Tree    |
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
 *                         |      Top Data Tree       |
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
 * ## Version Management and Reorganization Protection:
 *
 * The system uses versions to isolate state during blockchain reorganizations:
 *
 * 1. **Version Creation**:
 *    - Initial version 1 created at deployment
 *    - New versions created via `addVersion(timestamp)` by whitelisted settlers
 *    - Each version has its own set of chronicle contracts
 *
 * 2. **Chronicle Lifecycle**:
 *    - LocalAppChronicle: Created per app/version via `addLocalAppChronicle`
 *    - RemoteAppChronicle: Created per app/chain/version via `addRemoteAppChronicle`
 *    - Chronicles manage all state operations for their specific version
 *
 * 3. **State Isolation**:
 *    - Each version's data is completely isolated from other versions
 *    - After a reorg, previous version's state is preserved but inaccessible from new version
 *    - Historical queries use `getVersion(timestamp)` to access correct version's data
 *
 * 4. **Settlement Flow**:
 *    - Roots received via `onReceiveRoots` are stored per version
 *    - RemoteAppChronicle handles settlement of liquidity and data
 *    - Settlement triggers optional hooks for application callbacks
 *
 * ## Key Functionalities:
 *
 * 1. **App Registration & Configuration**:
 *    - Applications register via `registerApp` to initialize state tracking
 *    - Configuration includes sync behavior (mapped accounts only), hook callbacks, and authorized settler
 *    - Apps must create chronicle contracts for each version they use
 *
 * 2. **Local State Management**:
 *    - Liquidity updates via `updateLocalLiquidity` are delegated to LocalAppChronicle
 *    - Data updates via `updateLocalData` are delegated to LocalAppChronicle
 *    - LocalAppChronicle maintains app-specific Merkle trees and updates top-level trees
 *
 * 3. **Remote State Management**:
 *    - Remote roots received via `onReceiveRoots` from gateway or internal calls
 *    - Settlement handled by RemoteAppChronicle via `settleLiquidity` and `settleData`
 *    - Supports finalization when both liquidity and data roots are settled
 *
 * 4. **Cross-Chain Operations**:
 *    - Sync operation fetches roots from all configured chains via gateway
 *    - Account mapping requests sent cross-chain via `requestMapRemoteAccounts`
 *    - Implements IGatewayApp for read result aggregation via `reduce` and `onRead`
 *
 * 5. **Settler System**:
 *    - Per-app settlers configured during registration
 *    - Global settler whitelist maintained via `updateSettlerWhitelisted`
 *    - Settlers authorized to add reorgs and create chronicle contracts
 *
 * 6. **Query Functions**:
 *    - Local state queries via LocalAppChronicle (current and historical)
 *    - Remote state queries via RemoteAppChronicle (settled and finalized)
 *    - Aggregated queries combine local and remote liquidity across chains
 *
 * 7. **Version-Aware Historical Access**:
 *    - `getVersion(timestamp)` determines which version was active at a given time
 *    - Root queries like `getLiquidityRootAt` automatically use correct version
 *    - Chronicle contracts provide point-in-time state snapshots
 */
contract LiquidityMatrix is ReentrancyGuard, Ownable, ILiquidityMatrix, IGatewayApp {
    using ArrayLib for uint256[];
    using AddressLib for address;
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using SnapshotsLib for SnapshotsLib.Snapshots;

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    struct State {
        MerkleTreeLib.Tree topLiquidityTree;
        MerkleTreeLib.Tree topDataTree;
    }

    struct RemoteState {
        uint256[] rootTimestamps;
        SnapshotsLib.Snapshots liquidityRoots;
        SnapshotsLib.Snapshots dataRoots;
    }

    struct AppState {
        bool registered;
        bool syncMappedAccountsOnly;
        bool useHook;
        address settler;
        mapping(uint256 version => address) chronicles;
    }

    struct RemoteAppState {
        address app;
        uint256 appIndex;
        mapping(address remote => address local) mappedAccounts;
        mapping(address local => bool) localAccountMapped;
        mapping(uint256 version => address) chronicles;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => bool) internal _isSettlerWhitelisted;

    uint256[] internal _versions;

    mapping(uint256 version => State) internal _states;
    mapping(bytes32 chainUID => mapping(uint256 version => RemoteState)) internal _remoteStates;

    mapping(address app => AppState) internal _appStates;
    mapping(address app => mapping(bytes32 chainUID => RemoteAppState)) internal _remoteAppStates;

    // Command identifiers for different message types
    uint16 internal constant CMD_SYNC = 1;
    uint16 internal constant MAP_REMOTE_ACCOUNTS = 1;

    // Gateway for cross-chain operations
    IGateway public gateway;
    // Address authorized to initiate sync operations
    address public syncer;
    // Rate limiting: timestamp of last sync request
    mapping(uint256 version => uint64) internal _lastSyncRequestTimestamp;
    // Deployers for chronicle contracts
    address public localAppChronicleDeployer;
    address public remoteAppChronicleDeployer;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp() {
        if (!_appStates[msg.sender].registered) revert Forbidden();
        _;
    }

    modifier onlySettler() {
        if (!_isSettlerWhitelisted[msg.sender]) revert Forbidden();
        _;
    }

    modifier onlyAppSettler(address _app) {
        AppState storage state = _appStates[_app];
        if (!state.registered) revert AppNotRegistered();
        if (state.settler != msg.sender && !_isSettlerWhitelisted[msg.sender]) revert Forbidden();
        _;
    }

    modifier onlyLocalAppChronicle(address app, uint256 version) {
        if (msg.sender != _appStates[app].chronicles[version]) revert Forbidden();
        _;
    }

    modifier onlyRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) {
        if (msg.sender != _remoteAppStates[app][chainUID].chronicles[version]) revert Forbidden();
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

    constructor(address _owner, uint256 _timestamp, address _localDeployer, address _remoteDeployer) Ownable(_owner) {
        _versions.push(_timestamp);
        localAppChronicleDeployer = _localDeployer;
        remoteAppChronicleDeployer = _remoteDeployer;

        emit AddVersion(1, uint64(_timestamp));
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILiquidityMatrix
    function currentVersion() public view returns (uint256) {
        return _versions.length;
    }

    /// @inheritdoc ILiquidityMatrix
    function getVersion(uint64 timestamp) public view returns (uint256 version) {
        for (uint256 i = _versions.length; i > 0;) {
            unchecked {
                --i;
            }
            if (_versions[i] <= timestamp) {
                return i + 1;
            }
        }
        return 1;
    }

    /*//////////////////////////////////////////////////////////////
                        LOCAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILiquidityMatrix
    function getTopRoots()
        public
        view
        override
        returns (uint256 version, bytes32 liquidityRoot, bytes32 dataRoot, uint64 timestamp)
    {
        version = currentVersion();
        State storage state = _states[version];
        return (version, state.topLiquidityTree.getRoot(), state.topDataTree.getRoot(), uint64(block.timestamp));
    }

    /// @inheritdoc ILiquidityMatrix
    function getAppSetting(address app)
        external
        view
        override
        returns (bool registered, bool syncMappedAccountsOnly, bool useHook, address settler)
    {
        AppState storage state = _appStates[app];
        return (state.registered, state.syncMappedAccountsOnly, state.useHook, state.settler);
    }

    /// @inheritdoc ILiquidityMatrix
    function getCurrentLocalAppChronicle(address app) public view returns (address) {
        return getLocalAppChronicle(app, currentVersion());
    }

    /**
     * @notice Gets the current local app chronicle, reverting if not set
     * @param app The application address
     * @return The LocalAppChronicle contract
     */
    function _getCurrentLocalAppChronicleOrRevert(address app) internal view returns (ILocalAppChronicle) {
        address chronicle = getCurrentLocalAppChronicle(app);
        if (chronicle == address(0)) revert LocalAppChronicleNotSet();
        return ILocalAppChronicle(chronicle);
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalAppChronicleAt(address app, uint64 timestamp) public view returns (address) {
        return getLocalAppChronicle(app, getVersion(timestamp));
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalAppChronicle(address app, uint256 version) public view returns (address) {
        return _appStates[app].chronicles[version];
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalLiquidityRoot(address app) external view returns (bytes32) {
        return _getCurrentLocalAppChronicleOrRevert(app).getLiquidityRoot();
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalDataRoot(address app) external view returns (bytes32) {
        return _getCurrentLocalAppChronicleOrRevert(app).getDataRoot();
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalLiquidity(address app, address account) external view returns (int256) {
        return _getCurrentLocalAppChronicleOrRevert(app).getLiquidity(account);
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalLiquidityAt(address app, address account, uint64 timestamp) external view returns (int256) {
        return _getCurrentLocalAppChronicleOrRevert(app).getLiquidityAt(account, timestamp);
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalTotalLiquidity(address app) external view returns (int256) {
        return _getCurrentLocalAppChronicleOrRevert(app).getTotalLiquidity();
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256) {
        return _getCurrentLocalAppChronicleOrRevert(app).getTotalLiquidityAt(timestamp);
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalData(address app, bytes32 key) external view returns (bytes memory) {
        return _getCurrentLocalAppChronicleOrRevert(app).getData(key);
    }

    /// @inheritdoc ILiquidityMatrix
    function getLocalDataAt(address app, bytes32 key, uint64 timestamp) external view returns (bytes memory) {
        return _getCurrentLocalAppChronicleOrRevert(app).getDataAt(key, timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        REMOTE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the chain configurations from the gateway
     * @dev Delegates to gateway.chainConfigs()
     * @return chainUIDs Array of chain unique identifiers
     * @return confirmations Array of confirmation requirements for each chain
     */
    function chainConfigs() public view returns (bytes32[] memory chainUIDs, uint16[] memory confirmations) {
        return gateway.chainConfigs();
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
     * @notice Checks if an account is whitelisted as a settler
     * @param account The account to check
     * @return Whether the account is whitelisted
     */
    function isSettlerWhitelisted(address account) external view returns (bool) {
        return _isSettlerWhitelisted[account];
    }

    /// @inheritdoc ILiquidityMatrix
    function getRemoteApp(address app, bytes32 chainUID)
        external
        view
        returns (address remoteApp, uint256 remoteAppIndex)
    {
        RemoteAppState storage state = _remoteAppStates[app][chainUID];
        return (state.app, state.appIndex);
    }

    /**
     * @notice Gets the local account mapped to a remote account
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param remote The remote account address
     * @return local The mapped local account address
     */
    function getMappedAccount(address app, bytes32 chainUID, address remote) public view returns (address) {
        return _remoteAppStates[app][chainUID].mappedAccounts[remote];
    }

    function getLocalAccount(address app, bytes32 chainUID, address remote) external view returns (address) {
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
        return _remoteAppStates[app][chainUID].localAccountMapped[local];
    }

    function getCurrentRemoteAppChronicle(address app, bytes32 chainUID) public view returns (address) {
        return getRemoteAppChronicle(app, chainUID, currentVersion());
    }

    /**
     * @notice Gets the current remote app chronicle, reverting if not set
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @return The RemoteAppChronicle contract
     */
    function _getCurrentRemoteAppChronicleOrRevert(address app, bytes32 chainUID)
        internal
        view
        returns (IRemoteAppChronicle)
    {
        address chronicle = getRemoteAppChronicle(app, chainUID, currentVersion());
        if (chronicle == address(0)) revert RemoteAppChronicleNotSet(chainUID);
        return IRemoteAppChronicle(chronicle);
    }

    function getRemoteAppChronicleAt(address app, bytes32 chainUID, uint64 timestamp) public view returns (address) {
        return getRemoteAppChronicle(app, chainUID, getVersion(timestamp));
    }

    function getRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) public view returns (address) {
        return _remoteAppStates[app][chainUID].chronicles[version];
    }

    /**
     * @notice Gets the remote app chronicle for a version, reverting if not set
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @return The RemoteAppChronicle contract
     */
    function _getRemoteAppChronicleOrRevert(address app, bytes32 chainUID, uint256 version)
        internal
        view
        returns (IRemoteAppChronicle)
    {
        address chronicle = getRemoteAppChronicle(app, chainUID, version);
        if (chronicle == address(0)) revert RemoteAppChronicleNotSet(chainUID);
        return IRemoteAppChronicle(chronicle);
    }

    /*//////////////////////////////////////////////////////////////
                        REMOTE ROOT VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the liquidity root at a specific timestamp
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to query
     * @return root The liquidity root at the timestamp
     */
    function getLiquidityRootAt(bytes32 chainUID, uint64 timestamp) external view returns (bytes32 root) {
        return getLiquidityRootAt(chainUID, getVersion(timestamp), timestamp);
    }

    function getLiquidityRootAt(bytes32 chainUID, uint256 version, uint64 timestamp)
        public
        view
        returns (bytes32 root)
    {
        return _remoteStates[chainUID][version].liquidityRoots.get(timestamp);
    }

    /**
     * @notice Gets the last received liquidity root from a remote chain
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedLiquidityRoot(bytes32 chainUID) external view returns (bytes32 root, uint64 timestamp) {
        return getLastReceivedLiquidityRoot(chainUID, currentVersion());
    }

    function getLastReceivedLiquidityRoot(bytes32 chainUID, uint256 version)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        RemoteState storage state = _remoteStates[chainUID][version];
        uint256 length = state.rootTimestamps.length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = uint64(state.rootTimestamps[length - 1]);
        if (timestamp != 0) {
            root = state.liquidityRoots.get(timestamp);
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
        return getLastSettledLiquidityRoot(app, chainUID, currentVersion());
    }

    function getLastSettledLiquidityRoot(address app, bytes32 chainUID, uint256 version)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        timestamp = _getRemoteAppChronicleOrRevert(app, chainUID, version).getLastSettledLiquidityTimestamp();
        if (timestamp != 0) {
            root = _remoteStates[chainUID][version].liquidityRoots.get(timestamp);
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
        return getLastFinalizedLiquidityRoot(app, chainUID, currentVersion());
    }

    function getLastFinalizedLiquidityRoot(address app, bytes32 chainUID, uint256 version)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        timestamp = _getRemoteAppChronicleOrRevert(app, chainUID, version).getLastFinalizedTimestamp();
        if (timestamp != 0) {
            root = _remoteStates[chainUID][version].liquidityRoots.get(timestamp);
        }
    }

    /**
     * @notice Gets the data root at a specific timestamp
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to query
     * @return root The data root at the timestamp
     */
    function getDataRootAt(bytes32 chainUID, uint64 timestamp) external view returns (bytes32 root) {
        return getDataRootAt(chainUID, getVersion(timestamp), timestamp);
    }

    function getDataRootAt(bytes32 chainUID, uint256 version, uint64 timestamp) public view returns (bytes32 root) {
        return _remoteStates[chainUID][version].dataRoots.get(timestamp);
    }

    /**
     * @notice Gets the last received data root from a remote chain
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedDataRoot(bytes32 chainUID) external view returns (bytes32 root, uint64 timestamp) {
        return getLastReceivedDataRoot(chainUID, currentVersion());
    }

    function getLastReceivedDataRoot(bytes32 chainUID, uint256 version)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        RemoteState storage state = _remoteStates[chainUID][version];
        uint256 length = state.rootTimestamps.length;
        if (length == 0) return (bytes32(0), 0);

        timestamp = uint64(state.rootTimestamps[length - 1]);
        if (timestamp != 0) {
            root = state.dataRoots.get(timestamp);
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
        return getLastSettledDataRoot(app, chainUID, currentVersion());
    }

    function getLastSettledDataRoot(address app, bytes32 chainUID, uint256 version)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        timestamp = _getRemoteAppChronicleOrRevert(app, chainUID, version).getLastSettledDataTimestamp();
        if (timestamp != 0) {
            root = _remoteStates[chainUID][version].dataRoots.get(timestamp);
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
        return getLastFinalizedDataRoot(app, chainUID, currentVersion());
    }

    function getLastFinalizedDataRoot(address app, bytes32 chainUID, uint256 version)
        public
        view
        returns (bytes32 root, uint64 timestamp)
    {
        timestamp = _getRemoteAppChronicleOrRevert(app, chainUID, version).getLastFinalizedTimestamp();
        if (timestamp != 0) {
            root = _remoteStates[chainUID][version].dataRoots.get(timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        REMOTE STATE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAggregatedSettledTotalLiquidity(address app) external view returns (int256 liquidity) {
        (bytes32[] memory chainUIDs,) = chainConfigs();
        return getAggregatedSettledTotalLiquidity(app, chainUIDs);
    }

    function getAggregatedSettledTotalLiquidity(address app, bytes32[] memory chainUIDs)
        public
        view
        returns (int256 liquidity)
    {
        liquidity = _getCurrentLocalAppChronicleOrRevert(app).getTotalLiquidity();

        for (uint256 i; i < chainUIDs.length; ++i) {
            bytes32 chainUID = chainUIDs[i];
            IRemoteAppChronicle chronicle = _getCurrentRemoteAppChronicleOrRevert(app, chainUID);
            uint64 timestamp = chronicle.getLastSettledLiquidityTimestamp();
            liquidity += chronicle.getTotalLiquidityAt(timestamp);
        }
    }

    function getAggregatedFinalizedTotalLiquidity(address app) external view returns (int256 liquidity) {
        (bytes32[] memory chainUIDs,) = chainConfigs();
        return getAggregatedFinalizedTotalLiquidity(app, chainUIDs);
    }

    function getAggregatedFinalizedTotalLiquidity(address app, bytes32[] memory chainUIDs)
        public
        view
        returns (int256 liquidity)
    {
        liquidity = _getCurrentLocalAppChronicleOrRevert(app).getTotalLiquidity();

        for (uint256 i; i < chainUIDs.length; ++i) {
            bytes32 chainUID = chainUIDs[i];
            IRemoteAppChronicle chronicle = _getCurrentRemoteAppChronicleOrRevert(app, chainUID);
            uint64 timestamp = chronicle.getLastFinalizedTimestamp();
            liquidity += chronicle.getTotalLiquidityAt(timestamp);
        }
    }

    /**
     * @notice Gets the total liquidity at the timestamp
     * @param app The application address
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity at the latest valid timestamp
     */
    function getAggregatedTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256 liquidity) {
        (bytes32[] memory chainUIDs,) = chainConfigs();
        return getAggregatedTotalLiquidityAt(app, chainUIDs, timestamp);
    }

    function getAggregatedTotalLiquidityAt(address app, bytes32[] memory chainUIDs, uint64 timestamp)
        public
        view
        returns (int256 liquidity)
    {
        liquidity = _getCurrentLocalAppChronicleOrRevert(app).getTotalLiquidityAt(timestamp);

        for (uint256 i; i < chainUIDs.length; ++i) {
            bytes32 chainUID = chainUIDs[i];
            liquidity +=
                _getRemoteAppChronicleOrRevert(app, chainUID, getVersion(timestamp)).getTotalLiquidityAt(timestamp);
        }
    }

    function getTotalLiquidityAt(address app, bytes32 chainUID, uint64 timestamp)
        external
        view
        returns (int256 liquidity)
    {
        return _getRemoteAppChronicleOrRevert(app, chainUID, getVersion(timestamp)).getTotalLiquidityAt(timestamp);
    }

    function getAggregatedSettledLiquidityAt(address app, address account) external view returns (int256 liquidity) {
        (bytes32[] memory chainUIDs,) = chainConfigs();
        return getAggregatedSettledLiquidityAt(app, chainUIDs, account);
    }

    function getAggregatedSettledLiquidityAt(address app, bytes32[] memory chainUIDs, address account)
        public
        view
        returns (int256 liquidity)
    {
        liquidity = _getCurrentLocalAppChronicleOrRevert(app).getLiquidity(account);

        for (uint256 i; i < chainUIDs.length; ++i) {
            bytes32 chainUID = chainUIDs[i];
            IRemoteAppChronicle chronicle = _getCurrentRemoteAppChronicleOrRevert(app, chainUID);
            uint64 timestamp = chronicle.getLastSettledLiquidityTimestamp();
            liquidity += chronicle.getLiquidityAt(account, timestamp);
        }
    }

    function getAggregatedFinalizedLiquidityAt(address app, address account) external view returns (int256 liquidity) {
        (bytes32[] memory chainUIDs,) = chainConfigs();
        return getAggregatedFinalizedLiquidityAt(app, chainUIDs, account);
    }

    function getAggregatedFinalizedLiquidityAt(address app, bytes32[] memory chainUIDs, address account)
        public
        view
        returns (int256 liquidity)
    {
        liquidity = _getCurrentLocalAppChronicleOrRevert(app).getLiquidity(account);

        for (uint256 i; i < chainUIDs.length; ++i) {
            bytes32 chainUID = chainUIDs[i];
            IRemoteAppChronicle chronicle = _getCurrentRemoteAppChronicleOrRevert(app, chainUID);
            uint64 timestamp = chronicle.getLastFinalizedTimestamp();
            liquidity += chronicle.getLiquidityAt(account, timestamp);
        }
    }

    /**
     * @notice Gets the total liquidity at the timestamp
     * @param app The application address
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity at the latest valid timestamp
     */
    function getAggregatedLiquidityAt(address app, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity)
    {
        (bytes32[] memory chainUIDs,) = chainConfigs();
        return getAggregatedLiquidityAt(app, chainUIDs, account, timestamp);
    }

    function getAggregatedLiquidityAt(address app, bytes32[] memory chainUIDs, address account, uint64 timestamp)
        public
        view
        returns (int256 liquidity)
    {
        liquidity = _getCurrentLocalAppChronicleOrRevert(app).getLiquidityAt(account, timestamp);

        for (uint256 i; i < chainUIDs.length; ++i) {
            bytes32 chainUID = chainUIDs[i];
            liquidity +=
                _getRemoteAppChronicleOrRevert(app, chainUID, getVersion(timestamp)).getLiquidityAt(account, timestamp);
        }
    }

    function getLiquidityAt(address app, bytes32 chainUID, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity)
    {
        return _getRemoteAppChronicleOrRevert(app, chainUID, getVersion(timestamp)).getLiquidityAt(account, timestamp);
    }

    function getDataAt(address app, bytes32 chainUID, bytes32 key, uint64 timestamp)
        public
        view
        returns (bytes memory value)
    {
        return _getRemoteAppChronicleOrRevert(app, chainUID, getVersion(timestamp)).getDataAt(key, timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new version for state isolation
     * @dev Only callable by settler. The timestamp must be greater than the last version timestamp.
     * @param timestamp The timestamp of the new version
     */
    function addVersion(uint64 timestamp) external onlySettler {
        uint64 lastTimestamp = uint64(_versions.last());
        if (timestamp <= lastTimestamp) {
            revert InvalidTimestamp();
        }

        _versions.push(timestamp);
        emit AddVersion(currentVersion(), timestamp);
    }

    /**
     * @notice Updates the LocalAppChronicle deployer
     * @dev Only callable by owner. Used to upgrade chronicle creation logic.
     * @param deployer The new LocalAppChronicle deployer contract
     */
    function updateLocalAppChronicleDeployer(address deployer) external onlyOwner {
        localAppChronicleDeployer = deployer;
        emit UpdateLocalAppChronicleDeployer(deployer);
    }

    /**
     * @notice Updates the RemoteAppChronicle deployer
     * @dev Only callable by owner. Used to upgrade chronicle creation logic.
     * @param deployer The new RemoteAppChronicle deployer contract
     */
    function updateRemoteAppChronicleDeployer(address deployer) external onlyOwner {
        remoteAppChronicleDeployer = deployer;
        emit UpdateRemoteAppChronicleDeployer(deployer);
    }

    /*//////////////////////////////////////////////////////////////
                        LOCAL STATE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new application with the LiquidityMatrix
     * @dev Initializes the app's liquidity and data trees
     * @param syncMappedAccountsOnly If true, only syncs liquidity for mapped accounts
     * @param useHook If true, triggers callbacks to the app on state updates
     * @param settler Address authorized to settle roots for this app
     */
    function registerApp(bool syncMappedAccountsOnly, bool useHook, address settler) external {
        if (!_isSettlerWhitelisted[settler]) revert InvalidSettler();

        address app = msg.sender;
        if (_appStates[app].registered) revert AppAlreadyRegistered();

        uint256 version = currentVersion();

        AppState storage state = _appStates[app];
        state.registered = true;
        state.syncMappedAccountsOnly = syncMappedAccountsOnly;
        state.useHook = useHook;
        state.settler = settler;

        address chronicle = ILocalAppChronicleDeployer(localAppChronicleDeployer).deploy(address(this), app, version);
        if (chronicle == address(0)) revert ChronicleDeploymentFailed();
        state.chronicles[version] = chronicle;

        emit AddLocalAppChronicle(app, version, chronicle);
        emit RegisterApp(app, version, syncMappedAccountsOnly, useHook, settler);
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
     * @param useHook New setting value
     */
    function updateUseHook(bool useHook) external onlyApp {
        _appStates[msg.sender].useHook = useHook;
        emit UpdateUseHook(msg.sender, useHook);
    }

    /**
     * @notice Updates the authorized settler for the app
     *  ett/ * @param settler New settler address
     */
    function updateSettler(address settler) external onlyApp {
        _appStates[msg.sender].settler = settler;
        emit UpdateSettler(msg.sender, settler);
    }

    /// @inheritdoc ILiquidityMatrix
    function updateRemoteApp(bytes32 chainUID, address app, uint256 appIndex) external onlyApp {
        RemoteAppState storage state = _remoteAppStates[msg.sender][chainUID];
        state.app = app;
        state.appIndex = appIndex;
        emit UpdateRemoteApp(msg.sender, chainUID, app, appIndex);
    }

    /**
     * @notice Creates a new LocalAppChronicle for an app at a specific version
     * @dev Only callable by the app's settler. Required after a reorg to enable local state tracking.
     * @param app The application address
     * @param version The version number for the chronicle
     */
    function addLocalAppChronicle(address app, uint256 version) external onlyAppSettler(app) {
        if (version > currentVersion()) revert InvalidVersion();

        AppState storage appState = _appStates[app];
        if (!appState.registered) revert AppNotRegistered();
        if (appState.chronicles[version] != address(0)) revert AppChronicleAlreadyAdded();

        address chronicle = ILocalAppChronicleDeployer(localAppChronicleDeployer).deploy(address(this), app, version);
        if (chronicle == address(0)) revert ChronicleDeploymentFailed();

        appState.chronicles[version] = chronicle;

        emit AddLocalAppChronicle(app, version, chronicle);
    }

    /**
     * @notice Creates a new RemoteAppChronicle for an app and chain at a specific version
     * @dev Only callable by the app's settler. Required after a reorg to enable remote state tracking.
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param version The version number for the chronicle
     */
    function addRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) external onlyAppSettler(app) {
        if (version > currentVersion()) revert InvalidVersion();

        AppState storage appState = _appStates[app];
        if (!appState.registered) revert AppNotRegistered();

        RemoteAppState storage remoteState = _remoteAppStates[app][chainUID];
        if (remoteState.chronicles[version] != address(0)) revert AppChronicleAlreadyAdded();

        address chronicle =
            IRemoteAppChronicleDeployer(remoteAppChronicleDeployer).deploy(address(this), app, chainUID, version);
        if (chronicle == address(0)) revert ChronicleDeploymentFailed();

        remoteState.chronicles[version] = chronicle;

        emit AddRemoteAppChronicle(app, chainUID, version, chronicle);
    }

    /**
     * @notice Updates the top-level liquidity tree with an app's liquidity root
     * @dev Only callable by LocalAppChronicle contracts
     * @param version The version number
     * @param app The application address
     * @param appLiquidityRoot The app's liquidity tree root
     * @return treeIndex The index in the top liquidity tree
     */
    function updateTopLiquidityTree(uint256 version, address app, bytes32 appLiquidityRoot)
        external
        onlyLocalAppChronicle(app, version)
        returns (uint256 treeIndex)
    {
        State storage state = _states[version];
        treeIndex = state.topLiquidityTree.update(bytes32(uint256(uint160(app))), appLiquidityRoot);

        emit UpdateTopLiquidityTree(version, app, appLiquidityRoot, state.topLiquidityTree.getRoot());
    }

    /**
     * @notice Updates the top-level data tree with an app's data root
     * @dev Only callable by LocalAppChronicle contracts
     * @param version The version number
     * @param app The application address
     * @param appDataRoot The app's data tree root
     * @return treeIndex The index in the top data tree
     */
    function updateTopDataTree(uint256 version, address app, bytes32 appDataRoot)
        external
        onlyLocalAppChronicle(app, version)
        returns (uint256 treeIndex)
    {
        State storage state = _states[version];
        treeIndex = state.topDataTree.update(bytes32(uint256(uint160(app))), appDataRoot);

        emit UpdateTopDataTree(version, app, appDataRoot, state.topDataTree.getRoot());
    }

    /**
     * @notice Updates the local liquidity for an account
     * @dev Only callable by registered apps. Updates both app and main trees
     * @param account The account to update
     * @param liquidity The new liquidity value (replaces current value)
     * @return mainTreeIndex The index in the main liquidity tree
     * @return appTreeIndex The index in the app's liquidity tree
     */
    function updateLocalLiquidity(address account, int256 liquidity)
        external
        onlyApp
        returns (uint256 mainTreeIndex, uint256 appTreeIndex)
    {
        return _getCurrentLocalAppChronicleOrRevert(msg.sender).updateLiquidity(account, liquidity);
    }

    /**
     * @notice Updates local data for a key
     * @dev Only callable by registered apps. Updates both app and main data trees
     * @param key The data key to update
     * @param value The data value to store
     * @return mainTreeIndex The index in the main data tree
     * @return appTreeIndex The index in the app's data tree
     */
    function updateLocalData(bytes32 key, bytes memory value)
        external
        onlyApp
        returns (uint256 mainTreeIndex, uint256 appTreeIndex)
    {
        return _getCurrentLocalAppChronicleOrRevert(msg.sender).updateData(key, value);
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
    function updateGateway(address _gateway) external onlyOwner {
        gateway = IGateway(_gateway);
        emit UpdateGateway(_gateway);
    }

    /**
     * @notice Sets the syncer address
     * @dev Only callable by owner. Syncer is authorized to initiate sync operations.
     * @param _syncer Address authorized to sync
     */
    function updateSyncer(address _syncer) external onlyOwner {
        syncer = _syncer;
        emit UpdateSyncer(_syncer);
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
     * @notice Receives and stores Merkle roots from remote chains
     * @dev Only callable by the gateway or this contract (via onRead)
     * @param chainUID The chain unique identifier of the remote chain
     * @param version The version number from the remote chain
     * @param liquidityRoot The liquidity Merkle root from the remote chain
     * @param dataRoot The data Merkle root from the remote chain
     * @param timestamp The timestamp when the roots were generated
     */
    function onReceiveRoots(
        bytes32 chainUID,
        uint256 version,
        bytes32 liquidityRoot,
        bytes32 dataRoot,
        uint64 timestamp
    ) external {
        // Allow calls from this contract only (via onRead)
        if (msg.sender != address(this)) revert Forbidden();

        RemoteState storage state = _remoteStates[chainUID][version];
        if (timestamp <= state.rootTimestamps.last()) revert StaleRoots(chainUID);

        state.rootTimestamps.push(timestamp);
        state.liquidityRoots.set(liquidityRoot, timestamp);
        state.dataRoots.set(dataRoot, timestamp);

        emit ReceiveRoots(chainUID, version, liquidityRoot, dataRoot, timestamp);
    }

    /**
     * @notice Processes remote account mapping requests received from other chains
     * @dev Called by synchronizer when receiving cross-chain mapping requests.
     *      Validates mappings and consolidates liquidity from remote to local accounts.
     * @param _fromChainUID Source chain unique identifier
     * @param _localApp Local app address that should process this request
     */
    function onReceiveMapRemoteAccountRequests(
        bytes32 _fromChainUID,
        address _localApp,
        address[] memory _remotes,
        address[] memory _locals
    ) external {
        // Allow calls from this contract only (via onReceive)
        if (msg.sender != address(this)) revert Forbidden();

        // Verify the app is registered
        if (!_appStates[_localApp].registered) revert AppNotRegistered();

        bool[] memory shouldMap = new bool[](_remotes.length);
        if (ILiquidityMatrixAccountMapper(_localApp).shouldMapAccounts.selector == bytes4(0)) {
            for (uint256 i; i < _remotes.length; ++i) {
                shouldMap[i] = true;
            }
        } else {
            for (uint256 i; i < _remotes.length; ++i) {
                shouldMap[i] =
                    ILiquidityMatrixAccountMapper(_localApp).shouldMapAccounts(_fromChainUID, _remotes[i], _locals[i]);
            }
        }

        RemoteAppState storage state = _remoteAppStates[_localApp][_fromChainUID];

        for (uint256 i; i < _remotes.length; ++i) {
            if (!shouldMap[i]) continue;

            address remote = _remotes[i];
            address local = _locals[i];
            if (remote == local) revert IdenticalAccounts();

            if (state.mappedAccounts[remote] != address(0)) revert RemoteAccountAlreadyMapped(_fromChainUID, remote);
            if (state.localAccountMapped[local]) revert LocalAccountAlreadyMapped(_fromChainUID, local);

            state.mappedAccounts[remote] = local;
            state.localAccountMapped[local] = true;

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
        uint256 version = currentVersion();
        if (block.timestamp <= _lastSyncRequestTimestamp[version]) revert AlreadyRequested();
        _lastSyncRequestTimestamp[version] = uint64(block.timestamp);

        // Build callData for getTopRoots
        bytes memory callData = abi.encodeWithSelector(ILiquidityMatrix.getTopRoots.selector);

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
        bytes memory callData = abi.encodeWithSelector(ILiquidityMatrix.getTopRoots.selector);
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
        if (selector == ILiquidityMatrix.getTopRoots.selector) {
            bytes32[] memory chainUIDs = new bytes32[](requests.length);
            uint256[] memory versions = new uint256[](requests.length);
            bytes32[] memory liquidityRoots = new bytes32[](requests.length);
            bytes32[] memory dataRoots = new bytes32[](requests.length);
            uint256[] memory timestamps = new uint256[](requests.length);

            for (uint256 i; i < chainUIDs.length; ++i) {
                chainUIDs[i] = requests[i].chainUID;
                (versions[i], liquidityRoots[i], dataRoots[i], timestamps[i]) =
                    abi.decode(responses[i], (uint256, bytes32, bytes32, uint256));
            }

            return abi.encode(CMD_SYNC, chainUIDs, versions, liquidityRoots, dataRoots, timestamps);
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
                uint256[] memory versions,
                bytes32[] memory liquidityRoots,
                bytes32[] memory dataRoots,
                uint256[] memory timestamps
            ) = abi.decode(message, (uint16, bytes32[], uint256[], bytes32[], bytes32[], uint256[]));

            // Process each chain's roots
            for (uint256 i; i < chainUIDs.length; ++i) {
                bytes32 chainUID = chainUIDs[i];
                uint256 version = versions[i];
                bytes32 liquidityRoot = liquidityRoots[i];
                bytes32 dataRoot = dataRoots[i];
                uint64 timestamp = uint64(timestamps[i]);
                try this.onReceiveRoots(chainUID, version, liquidityRoot, dataRoot, timestamp) { }
                catch (bytes memory reason) {
                    emit OnReceiveRootFailure(chainUID, version, liquidityRoot, dataRoot, timestamp, reason);
                }
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
            (,, address app, address[] memory remotes, address[] memory locals) =
                abi.decode(message, (uint16, address, address, address[], address[]));

            // Process account mapping request
            try this.onReceiveMapRemoteAccountRequests(sourceChainId, app, remotes, locals) { }
            catch (bytes memory reason) {
                emit OnReceiveMapRemoteAccountRequestsFailure(sourceChainId, app, remotes, locals, reason);
            }
        }
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
