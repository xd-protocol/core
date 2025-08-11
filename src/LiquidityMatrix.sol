// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { LocalAppChronicle } from "./LocalAppChronicle.sol";
import { RemoteAppChronicle } from "./RemoteAppChronicle.sol";
import { ArrayLib } from "./libraries/ArrayLib.sol";
import { AddressLib } from "./libraries/AddressLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";
import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";
import { ILiquidityMatrix } from "./interfaces/ILiquidityMatrix.sol";
import { IGateway } from "./interfaces/IGateway.sol";
import { IGatewayApp } from "./interfaces/IGatewayApp.sol";
import { ILiquidityMatrixHook } from "./interfaces/ILiquidityMatrixHook.sol";
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
 * This contract maintains two top Merkle trees:
 * - **Top Liquidity Tree**: Tracks liquidity data for all registered applications.
 * - **Top Data Tree**: Tracks arbitrary key-value data for all registered applications.
 *
 * Each application maintains its own pair of Merkle trees:
 * - **Liquidity Tree**: Tracks account-specific liquidity data within the application.
 * - **Data Tree**: Tracks key-value pairs specific to the application.
 *
 * ## Relationship Between Top and App Trees:
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
 *    - The new liquidity tree root is propagated to the top liquidity tree.
 *
 * 3. **Updating Data**:
 *    - Key-value data updates are recorded in the app's data tree.
 *    - The new data tree root is propagated to the top data tree.
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
 *    - Allows querying of the current roots of the top liquidity and data trees.
 *    - Enables synchronization across chains or with off-chain systems.
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
        mapping(uint64 timestamp => bytes32) liquidityRoots;
        mapping(uint64 timestamp => bytes32) dataRoots;
    }

    struct AppState {
        bool registered;
        bool syncMappedAccountsOnly;
        bool useHook;
        address settler;
        mapping(uint256 version => address) chronicles;
    }

    struct RemoteAppState {
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
    uint64 internal _lastSyncRequestTimestamp;

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

    constructor(address _owner) Ownable(_owner) {
        _versions.push(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function currentVersion() public view returns (uint256) {
        return _versions.length;
    }

    /**
     * @notice Gets the version for a given timestamp
     * @param timestamp The timestamp to query
     * @return version The version number for the timestamp
     */
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

    /**
     * @notice Gets the current top tree roots and timestamp
     * @return version The version of the state
     * @return liquidityRoot The top liquidity tree root
     * @return dataRoot The top data tree root
     * @return timestamp The current block timestamp
     */
    function getTopRoots()
        public
        view
        returns (uint256 version, bytes32 liquidityRoot, bytes32 dataRoot, uint64 timestamp)
    {
        version = currentVersion();
        State storage state = _states[version];
        return (version, state.topLiquidityTree.root, state.topDataTree.root, uint64(block.timestamp));
    }

    /**
     * @notice Returns the settings for a registered application
     * @param app The application address
     * @return registered Whether the app is registered
     * @return syncMappedAccountsOnly Whether to sync only mapped accounts
     * @return useHook Whether callbacks are enabled
     * @return settler The authorized settler address
     */
    function getAppSetting(address app)
        external
        view
        returns (bool registered, bool syncMappedAccountsOnly, bool useHook, address settler)
    {
        AppState storage state = _appStates[app];
        return (state.registered, state.syncMappedAccountsOnly, state.useHook, state.settler);
    }

    function getCurrentLocalAppChronicle(address app) public view returns (address) {
        return getLocalAppChronicle(app, currentVersion());
    }

    function _getCurrentLocalAppChronicleOrRevert(address app) public view returns (LocalAppChronicle) {
        address chronicle = getCurrentLocalAppChronicle(app);
        if (chronicle == address(0)) revert LocalAppChronicleNotSet();
        return LocalAppChronicle(chronicle);
    }

    function getLocalAppChronicleAt(address app, uint64 timestamp) public view returns (address) {
        return getLocalAppChronicle(app, getVersion(timestamp));
    }

    function getLocalAppChronicle(address app, uint256 version) public view returns (address) {
        return _appStates[app].chronicles[version];
    }

    /**
     * @notice Gets the current root of an app's liquidity tree
     * @param app The application address
     * @return The liquidity tree root
     */
    function getLocalLiquidityRoot(address app) public view returns (bytes32) {
        return _getCurrentLocalAppChronicleOrRevert(app).getLiquidityRoot();
    }

    /**
     * @notice Gets the current root of an app's data tree
     * @param app The application address
     * @return The data tree root
     */
    function getLocalDataRoot(address app) public view returns (bytes32) {
        return _getCurrentLocalAppChronicleOrRevert(app).getDataRoot();
    }

    /**
     * @notice Gets the current local liquidity for an account in an app
     * @param app The application address
     * @param account The account address
     * @return liquidity The current liquidity for the account
     */
    function getLocalLiquidity(address app, address account) external view returns (int256) {
        return _getCurrentLocalAppChronicleOrRevert(app).getLiquidity(account);
    }

    /**
     * @notice Gets the local liquidity for an account at a specific timestamp
     * @param app The application address
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The liquidity at the timestamp
     */
    function getLocalLiquidityAt(address app, address account, uint64 timestamp) external view returns (int256) {
        return _getCurrentLocalAppChronicleOrRevert(app).getLiquidityAt(account, timestamp);
    }

    /**
     * @notice Gets the current total local liquidity for an app
     * @param app The application address
     * @return liquidity The current total liquidity
     */
    function getLocalTotalLiquidity(address app) external view returns (int256) {
        return _getCurrentLocalAppChronicleOrRevert(app).getTotalLiquidity();
    }

    function getLocalTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256) {
        return _getCurrentLocalAppChronicleOrRevert(app).getTotalLiquidityAt(timestamp);
    }

    function getLocalData(address app, bytes32 key) external view returns (bytes memory) {
        return _getCurrentLocalAppChronicleOrRevert(app).getData(key);
    }

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
        return _remoteAppStates[app][chainUID].localAccountMapped[local];
    }

    function getCurrentRemoteAppChronicle(address app, bytes32 chainUID) public view returns (address) {
        return getRemoteAppChronicle(app, chainUID, currentVersion());
    }

    function _getCurrentRemoteAppChronicleOrRevert(address app, bytes32 chainUID)
        internal
        view
        returns (RemoteAppChronicle)
    {
        address chronicle = getRemoteAppChronicle(app, chainUID, currentVersion());
        if (chronicle == address(0)) revert RemoteAppChronicleNotSet(chainUID);
        return RemoteAppChronicle(chronicle);
    }

    function getRemoteAppChronicleAt(address app, bytes32 chainUID, uint64 timestamp) public view returns (address) {
        return getRemoteAppChronicle(app, chainUID, getVersion(timestamp));
    }

    function getRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) public view returns (address) {
        return _remoteAppStates[app][chainUID].chronicles[version];
    }

    function _getRemoteAppChronicleOrRevert(address app, bytes32 chainUID, uint256 version)
        internal
        view
        returns (RemoteAppChronicle)
    {
        address chronicle = getRemoteAppChronicle(app, chainUID, version);
        if (chronicle == address(0)) revert RemoteAppChronicleNotSet(chainUID);
        return RemoteAppChronicle(chronicle);
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
        return _remoteStates[chainUID][version].liquidityRoots[uint64(timestamp)];
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
            root = state.liquidityRoots[timestamp];
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
            root = _remoteStates[chainUID][version].liquidityRoots[timestamp];
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
            root = _remoteStates[chainUID][version].liquidityRoots[timestamp];
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
        return _remoteStates[chainUID][version].dataRoots[uint64(timestamp)];
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
            root = state.dataRoots[timestamp];
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
            root = _remoteStates[chainUID][version].dataRoots[timestamp];
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
            root = _remoteStates[chainUID][version].dataRoots[timestamp];
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
            RemoteAppChronicle chronicle = _getCurrentRemoteAppChronicleOrRevert(app, chainUID);
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
            RemoteAppChronicle chronicle = _getCurrentRemoteAppChronicleOrRevert(app, chainUID);
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
            liquidity += _getCurrentRemoteAppChronicleOrRevert(app, chainUID).getTotalLiquidityAt(timestamp);
        }
    }

    function getTotalLiquidityAt(address app, bytes32 chainUID, uint64 timestamp)
        external
        view
        returns (int256 liquidity)
    {
        return _getCurrentRemoteAppChronicleOrRevert(app, chainUID).getTotalLiquidityAt(timestamp);
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
            RemoteAppChronicle chronicle = _getCurrentRemoteAppChronicleOrRevert(app, chainUID);
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
            RemoteAppChronicle chronicle = _getCurrentRemoteAppChronicleOrRevert(app, chainUID);
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
            liquidity += _getCurrentRemoteAppChronicleOrRevert(app, chainUID).getLiquidityAt(account, timestamp);
        }
    }

    function getLiquidityAt(address app, bytes32 chainUID, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity)
    {
        return _getCurrentRemoteAppChronicleOrRevert(app, chainUID).getLiquidityAt(account, timestamp);
    }

    function getDataAt(address app, bytes32 chainUID, bytes32 key, uint64 timestamp)
        public
        view
        returns (bytes memory value)
    {
        return _getCurrentRemoteAppChronicleOrRevert(app, chainUID).getDataAt(key, timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new reorg timestamp
     * @dev Only callable by settler. The timestamp must be greater than the last reorg timestamp.
     * @param timestamp The timestamp of the reorg
     */
    function addReorg(uint64 timestamp) external onlySettler {
        uint64 lastTimestamp = uint64(_versions.last());
        if (timestamp <= lastTimestamp) {
            revert InvalidTimestamp();
        }

        _versions.push(timestamp);
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

        address chronicle = address(new LocalAppChronicle{ salt: bytes32(version) }(address(this), app, version));
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
     * @param settler New settler address
     */
    function updateSettler(address settler) external onlyApp {
        _appStates[msg.sender].settler = settler;
        emit UpdateSettler(msg.sender, settler);
    }

    function addLocalAppChronicle(address app, uint256 version) external onlyAppSettler(app) {
        if (version > currentVersion()) revert InvalidVersion();

        AppState storage appState = _appStates[app];
        if (!appState.registered) revert AppNotRegistered();
        if (appState.chronicles[version] != address(0)) revert AppChronicleAlreadyAdded();

        address chronicle = address(new LocalAppChronicle{ salt: bytes32(version) }(address(this), app, version));
        appState.chronicles[version] = chronicle;

        emit AddLocalAppChronicle(app, version, chronicle);
    }

    function addRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) external onlyAppSettler(app) {
        if (version > currentVersion()) revert InvalidVersion();

        AppState storage appState = _appStates[app];
        if (!appState.registered) revert AppNotRegistered();

        RemoteAppState storage remoteState = _remoteAppStates[app][chainUID];
        if (remoteState.chronicles[version] != address(0)) revert AppChronicleAlreadyAdded();

        address chronicle =
            address(new RemoteAppChronicle{ salt: bytes32(version) }(address(this), app, chainUID, version));
        remoteState.chronicles[version] = chronicle;

        emit AddRemoteAppChronicle(app, chainUID, version, chronicle);
    }

    function updateTopLiquidityTree(uint256 version, address app, bytes32 appLiquidityRoot)
        external
        onlyLocalAppChronicle(app, version)
        returns (uint256 treeIndex)
    {
        State storage state = _states[version];
        treeIndex = state.topLiquidityTree.update(bytes32(uint256(uint160(app))), appLiquidityRoot);

        emit UpdateTopLiquidityTree(version, app, appLiquidityRoot, state.topLiquidityTree.root);
    }

    function updateTopDataTree(uint256 version, address app, bytes32 appDataRoot)
        external
        onlyLocalAppChronicle(app, version)
        returns (uint256 treeIndex)
    {
        State storage state = _states[version];
        treeIndex = state.topDataTree.update(bytes32(uint256(uint160(app))), appDataRoot);

        emit UpdateTopDataTree(version, app, appDataRoot, state.topDataTree.root);
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
     * @dev Called by the synchronizer after successful cross-chain sync
     * @param chainUID The chain unique identifier of the remote chain
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
        // Allow calls from gateway or from this contract (via onRead)
        if (msg.sender != address(gateway) && msg.sender != address(this)) revert Forbidden();

        RemoteState storage state = _remoteStates[chainUID][version];
        if (state.rootTimestamps.length == 0 || state.rootTimestamps.last() != timestamp) {
            state.rootTimestamps.push(timestamp);
        }

        state.liquidityRoots[timestamp] = liquidityRoot;
        state.dataRoots[timestamp] = dataRoot;

        emit OnReceiveRoots(chainUID, version, liquidityRoot, dataRoot, timestamp);
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

        RemoteAppState storage state = _remoteAppStates[_localApp][_fromChainUID];

        for (uint256 i; i < remotes.length; ++i) {
            if (!shouldMap[i]) continue;

            address remote = remotes[i];
            address local = locals[i];
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
        if (block.timestamp <= _lastSyncRequestTimestamp) revert AlreadyRequested();
        _lastSyncRequestTimestamp = uint64(block.timestamp);

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
                this.onReceiveRoots(chainUIDs[i], versions[i], liquidityRoots[i], dataRoots[i], uint64(timestamps[i]));
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
