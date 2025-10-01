// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IGateway } from "./IGateway.sol";

/**
 * @title ILiquidityMatrix
 * @notice Interface for the core ledger contract managing cross-chain liquidity and state synchronization
 * @dev Defines the API for versioned state management through chronicle contracts with reorg protection
 */
interface ILiquidityMatrix {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyRequested();
    error AppChronicleAlreadyAdded();
    error AppNotRegistered();
    error AppAlreadyRegistered();
    error ChronicleDeploymentFailed();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidCmd();
    error InvalidLengths();
    error InvalidSettler();
    error InvalidTarget();
    error InvalidTimestamp();
    error InvalidVersion();
    error Forbidden();
    error IdenticalAccounts();
    error LocalAccountAlreadyMapped(bytes32 chainUID, address local);
    error LocalAppChronicleNotSet();
    error RemoteAccountAlreadyMapped(bytes32 chainUID, address remote);
    error RemoteAppChronicleNotSet(bytes32 chainUID);
    error StaleRoots(bytes32 chainUID);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(
        address indexed app, uint256 indexed version, bool syncMappedAccountsOnly, bool useHook, address settler
    );
    event AddLocalAppChronicle(address indexed app, uint256 indexed version, address indexed chronicle);
    event AddRemoteAppChronicle(address indexed app, bytes32 indexed chainUID, uint256 version, address chronicle);
    event UpdateSyncMappedAccountsOnly(address indexed app, bool syncMappedAccountsOnly);
    event UpdateUseHook(address indexed app, bool useHook);
    event UpdateSettler(address indexed app, address settler);
    event UpdateRemoteApp(address indexed app, bytes32 indexed chainUID, address indexed remoteApp, uint256 appIndex);
    event UpdateTopLiquidityTree(
        uint256 indexed version, address indexed app, bytes32 appLiquidityRoot, bytes32 topLiquidityRoot
    );
    event UpdateTopDataTree(uint256 indexed version, address indexed app, bytes32 appDataRoot, bytes32 topDataRoot);

    event UpdateSettlerWhitelisted(address indexed account, bool whitelisted);
    event MapRemoteAccount(address indexed app, bytes32 indexed chainUID, address indexed remote, address local);
    event RequestMapRemoteAccounts(
        address indexed app, bytes32 indexed chainUID, address indexed remoteApp, address[] remotes, address[] locals
    );
    event OnReceiveMapRemoteAccountRequestsFailure(
        bytes32 indexed sourceChainUID, address indexed app, address[] remotes, address[] locals, bytes reason
    );

    event ReceiveRoots(
        bytes32 indexed chainUID,
        uint256 indexed version,
        bytes32 liquidityRoot,
        bytes32 dataRoot,
        uint64 indexed timestamp
    );
    event OnReceiveRootFailure(
        bytes32 indexed chainUID,
        uint256 indexed version,
        bytes32 liquidityRoot,
        bytes32 dataRoot,
        uint64 indexed timestamp,
        bytes reason
    );

    event UpdateGateway(address indexed gateway);
    event UpdateSyncer(address indexed syncer);
    event UpdateReadTarget(bytes32 indexed chainUID, bytes32 indexed target);
    event Sync(address indexed caller);
    event AddVersion(uint256 indexed version, uint64 indexed timestamp);
    event ReadChainsConfigured(bytes32[] chainUIDs);
    event UpdateLocalAppChronicleDeployer(address indexed deployer);
    event UpdateRemoteAppChronicleDeployer(address indexed deployer);

    /*//////////////////////////////////////////////////////////////
                        VERSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current version number for state management
     * @dev Version increments when a new version is added via addVersion
     * @return The current version number
     */
    function currentVersion() external view returns (uint256);

    /**
     * @notice Returns the version number at a specific timestamp
     * @dev Used to determine which version's state to query for historical lookups
     * @param timestamp The timestamp to query
     * @return version The version number active at that timestamp
     */
    function getVersion(uint64 timestamp) external view returns (uint256 version);

    /**
     * @notice Gets the current top-level roots for the current version
     * @dev These are the roots of the aggregated liquidity and data trees
     * @return version The current version number
     * @return liquidityRoot The top liquidity tree root
     * @return dataRoot The top data tree root
     * @return timestamp The timestamp of the roots
     */
    function getTopRoots()
        external
        view
        returns (uint256 version, bytes32 liquidityRoot, bytes32 dataRoot, uint64 timestamp);

    /**
     * @notice Gets the configuration settings for an application
     * @param app The application address
     * @return registered Whether the app is registered
     * @return syncMappedAccountsOnly Whether to sync only mapped accounts
     * @return useHook Whether hooks are enabled
     * @return settler The authorized settler address
     */
    function getAppSetting(address app)
        external
        view
        returns (bool registered, bool syncMappedAccountsOnly, bool useHook, address settler);

    /*//////////////////////////////////////////////////////////////
                        LOCAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the current local app chronicle for an application
     * @param app The application address
     * @return The address of the current LocalAppChronicle contract
     */
    function getCurrentLocalAppChronicle(address app) external view returns (address);

    /**
     * @notice Gets the local app chronicle for a specific version
     * @param app The application address
     * @param version The version number
     * @return The address of the LocalAppChronicle contract for that version
     */
    function getLocalAppChronicle(address app, uint256 version) external view returns (address);

    /**
     * @notice Gets the local app chronicle at a specific timestamp
     * @param app The application address
     * @param timestamp The timestamp to query
     * @return The address of the LocalAppChronicle contract at that timestamp
     */
    function getLocalAppChronicleAt(address app, uint64 timestamp) external view returns (address);

    /**
     * @notice Gets the current root of an app's liquidity tree
     * @param app The application address
     * @return The liquidity tree root
     */
    function getLocalLiquidityRoot(address app) external view returns (bytes32);

    /**
     * @notice Gets the current root of an app's data tree
     * @param app The application address
     * @return The data tree root
     */
    function getLocalDataRoot(address app) external view returns (bytes32);

    /**
     * @notice Gets the current local liquidity for an account in an app
     * @param app The application address
     * @param account The account address
     * @return liquidity The current liquidity for the account
     */
    function getLocalLiquidity(address app, address account) external view returns (int256 liquidity);

    /**
     * @notice Gets the local liquidity for an account at a specific timestamp
     * @param app The application address
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The liquidity at the timestamp
     */
    function getLocalLiquidityAt(address app, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the current total local liquidity for an app
     * @param app The application address
     * @return liquidity The current total liquidity
     */
    function getLocalTotalLiquidity(address app) external view returns (int256 liquidity);

    /**
     * @notice Gets the total local liquidity for an app at a specific timestamp
     * @param app The application address
     * @param timestamp The timestamp to query
     * @return The total liquidity at the timestamp
     */
    function getLocalTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256);

    /**
     * @notice Gets the current local data for a key
     * @param app The application address
     * @param key The data key
     * @return The data value
     */
    function getLocalData(address app, bytes32 key) external view returns (bytes memory);

    /**
     * @notice Gets the local data for a key at a specific timestamp
     * @param app The application address
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return The data value at the timestamp
     */
    function getLocalDataAt(address app, bytes32 key, uint64 timestamp) external view returns (bytes memory);

    /*//////////////////////////////////////////////////////////////
                        REMOTE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the owner of the LiquidityMatrix contract
     * @return The owner address
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the gateway contract
     * @return The gateway contract
     */
    function gateway() external view returns (IGateway);

    /**
     * @notice Returns the syncer address
     * @return The syncer address
     */
    function syncer() external view returns (address);

    /**
     * @notice Returns the local app chronicle deployer address
     * @return The local app chronicle deployer address
     */
    function localAppChronicleDeployer() external view returns (address);

    /**
     * @notice Returns the remote app chronicle deployer address
     * @return The remote app chronicle deployer address
     */
    function remoteAppChronicleDeployer() external view returns (address);

    // Note: chainConfigs() has been removed. Each component should manage its own chain configuration.
    // Use configureReadChains() to set chains and getReadTargets() to retrieve them.

    /**
     * @notice Quotes the fee for mapping remote accounts
     * @param chainUID Target chain unique identifier
     * @param localApp Address of the local app
     * @param remoteApp Address of the app on the remote chain
     * @param remotes Array of remote account addresses
     * @param locals Array of local account addresses to map to
     * @param gasLimit Gas limit for the cross-chain message
     * @return fee The estimated messaging fee
     */
    function quoteRequestMapRemoteAccounts(
        bytes32 chainUID,
        address localApp,
        address remoteApp,
        address[] memory remotes,
        address[] memory locals,
        uint128 gasLimit
    ) external view returns (uint256 fee);

    /**
     * @notice Checks if an account is whitelisted as a settler
     * @param account The account to check
     * @return Whether the account is whitelisted
     */
    function isSettlerWhitelisted(address account) external view returns (bool);

    /**
     * @notice Gets the remote app address and index for a specific chain
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @return remoteApp The remote app address on the specified chain
     * @return remoteAppIndex The index of the app on the remote chain
     */
    function getRemoteApp(address app, bytes32 chainUID)
        external
        view
        returns (address remoteApp, uint256 remoteAppIndex);

    /**
     * @notice Gets the local account mapped to a remote account
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param remote The remote account address
     * @return local The mapped local account address
     */
    function getMappedAccount(address app, bytes32 chainUID, address remote) external view returns (address local);

    /**
     * @notice Gets the local account mapped to a remote account (alias for getMappedAccount)
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param remote The remote account address
     * @return local The mapped local account address
     */
    function getLocalAccount(address app, bytes32 chainUID, address remote) external view returns (address local);

    /**
     * @notice Checks if a local account is already mapped for a specific chain
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param local The local account address to check
     * @return Whether the local account is already mapped
     */
    function isLocalAccountMapped(address app, bytes32 chainUID, address local) external view returns (bool);

    /**
     * @notice Gets the current remote app chronicle for an app and chain
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @return The address of the current RemoteAppChronicle contract
     */
    function getCurrentRemoteAppChronicle(address app, bytes32 chainUID) external view returns (address);

    /**
     * @notice Gets the remote app chronicle at a specific timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param timestamp The timestamp to query
     * @return The address of the RemoteAppChronicle contract at that timestamp
     */
    function getRemoteAppChronicleAt(address app, bytes32 chainUID, uint64 timestamp) external view returns (address);

    /**
     * @notice Gets the remote app chronicle for a specific version
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @return The address of the RemoteAppChronicle contract for that version
     */
    function getRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                    REMOTE ROOT VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the liquidity root from a remote chain at a specific timestamp
     * @param chainUID The chain unique identifier
     * @param timestamp The timestamp to query
     * @return root The liquidity root at the timestamp
     */
    function getRemoteLiquidityRootAt(bytes32 chainUID, uint64 timestamp) external view returns (bytes32 root);

    /**
     * @notice Gets the liquidity root from a remote chain for a specific version and timestamp
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @param timestamp The timestamp to query
     * @return root The liquidity root at the timestamp for the version
     */
    function getRemoteLiquidityRootAt(bytes32 chainUID, uint256 version, uint64 timestamp)
        external
        view
        returns (bytes32 root);

    /**
     * @notice Gets the last received liquidity root from a remote chain
     * @param chainUID The chain unique identifier
     * @return root The last received liquidity root
     * @return timestamp The timestamp when it was received
     */
    function getLastReceivedRemoteLiquidityRoot(bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last received liquidity root from a remote chain for a specific version
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @return root The last received liquidity root for the version
     * @return timestamp The timestamp when it was received
     */
    function getLastReceivedRemoteLiquidityRoot(bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last settled liquidity root from a remote chain for an app
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @return root The last settled liquidity root
     * @return timestamp The timestamp when it was settled
     */
    function getLastSettledRemoteLiquidityRoot(address app, bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last settled liquidity root from a remote chain for an app and version
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @return root The last settled liquidity root for the version
     * @return timestamp The timestamp when it was settled
     */
    function getLastSettledRemoteLiquidityRoot(address app, bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last finalized liquidity root from a remote chain for an app
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @return root The last finalized liquidity root
     * @return timestamp The timestamp when it was finalized
     */
    function getLastFinalizedRemoteLiquidityRoot(address app, bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last finalized liquidity root from a remote chain for an app and version
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @return root The last finalized liquidity root for the version
     * @return timestamp The timestamp when it was finalized
     */
    function getLastFinalizedRemoteLiquidityRoot(address app, bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the data root from a remote chain at a specific timestamp
     * @param chainUID The chain unique identifier
     * @param timestamp The timestamp to query
     * @return root The data root at the timestamp
     */
    function getRemoteDataRootAt(bytes32 chainUID, uint64 timestamp) external view returns (bytes32 root);

    /**
     * @notice Gets the data root from a remote chain for a specific version and timestamp
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @param timestamp The timestamp to query
     * @return root The data root at the timestamp for the version
     */
    function getRemoteDataRootAt(bytes32 chainUID, uint256 version, uint64 timestamp)
        external
        view
        returns (bytes32 root);

    /**
     * @notice Gets the last received data root from a remote chain
     * @param chainUID The chain unique identifier
     * @return root The last received data root
     * @return timestamp The timestamp when it was received
     */
    function getLastReceivedRemoteDataRoot(bytes32 chainUID) external view returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last received data root from a remote chain for a specific version
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @return root The last received data root for the version
     * @return timestamp The timestamp when it was received
     */
    function getLastReceivedRemoteDataRoot(bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last settled data root from a remote chain for an app
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @return root The last settled data root
     * @return timestamp The timestamp when it was settled
     */
    function getLastSettledRemoteDataRoot(address app, bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last settled data root from a remote chain for an app and version
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @return root The last settled data root for the version
     * @return timestamp The timestamp when it was settled
     */
    function getLastSettledRemoteDataRoot(address app, bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last finalized data root from a remote chain for an app
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @return root The last finalized data root
     * @return timestamp The timestamp when it was finalized
     */
    function getLastFinalizedRemoteDataRoot(address app, bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last finalized data root from a remote chain for an app and version
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param version The version number
     * @return root The last finalized data root for the version
     * @return timestamp The timestamp when it was finalized
     */
    function getLastFinalizedRemoteDataRoot(address app, bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /*//////////////////////////////////////////////////////////////
                    REMOTE STATE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the aggregated total liquidity across all chains (latest settled)
     * @param app The application address
     * @return liquidity The sum of local and all settled remote total liquidity
     */
    function getAggregatedSettledTotalLiquidity(address app) external view returns (int256 liquidity);

    /**
     * @notice Gets the aggregated total liquidity across specified chains (latest settled)
     * @param app The application address
     * @param chainUIDs Array of chain unique identifiers to aggregate
     * @return liquidity The sum of local and specified settled remote total liquidity
     */
    function getAggregatedSettledTotalLiquidity(address app, bytes32[] memory chainUIDs)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the aggregated total liquidity across all chains (latest finalized)
     * @param app The application address
     * @return liquidity The sum of local and all finalized remote total liquidity
     */
    function getAggregatedFinalizedTotalLiquidity(address app) external view returns (int256 liquidity);

    /**
     * @notice Gets the aggregated total liquidity across specified chains (latest finalized)
     * @param app The application address
     * @param chainUIDs Array of chain unique identifiers to aggregate
     * @return liquidity The sum of local and specified finalized remote total liquidity
     */
    function getAggregatedFinalizedTotalLiquidity(address app, bytes32[] memory chainUIDs)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the aggregated total liquidity across all chains at a specific timestamp
     * @param app The application address
     * @param timestamp The timestamp to query
     * @return liquidity The sum of local and all remote total liquidity at the timestamp
     */
    function getAggregatedTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256 liquidity);

    /**
     * @notice Gets the aggregated total liquidity across specified chains at a specific timestamp
     * @param app The application address
     * @param chainUIDs Array of chain unique identifiers to aggregate
     * @param timestamp The timestamp to query
     * @return liquidity The sum of local and specified remote total liquidity at the timestamp
     */
    function getAggregatedTotalLiquidityAt(address app, bytes32[] memory chainUIDs, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the total liquidity from a specific remote chain at a timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity from the specified chain at the timestamp
     */
    function getRemoteTotalLiquidityAt(address app, bytes32 chainUID, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the aggregated account liquidity across all chains (latest settled)
     * @param app The application address
     * @param account The account address
     * @return liquidity The sum of local and all settled remote liquidity for the account
     */
    function getAggregatedSettledLiquidityAt(address app, address account) external view returns (int256 liquidity);

    /**
     * @notice Gets the aggregated account liquidity across specified chains (latest settled)
     * @param app The application address
     * @param chainUIDs Array of chain unique identifiers to aggregate
     * @param account The account address
     * @return liquidity The sum of local and specified settled remote liquidity for the account
     */
    function getAggregatedSettledLiquidityAt(address app, bytes32[] memory chainUIDs, address account)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the aggregated account liquidity across all chains (latest finalized)
     * @param app The application address
     * @param account The account address
     * @return liquidity The sum of local and all finalized remote liquidity for the account
     */
    function getAggregatedFinalizedLiquidityAt(address app, address account) external view returns (int256 liquidity);

    /**
     * @notice Gets the aggregated account liquidity across specified chains (latest finalized)
     * @param app The application address
     * @param chainUIDs Array of chain unique identifiers to aggregate
     * @param account The account address
     * @return liquidity The sum of local and specified finalized remote liquidity for the account
     */
    function getAggregatedFinalizedLiquidityAt(address app, bytes32[] memory chainUIDs, address account)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the aggregated account liquidity across all chains at a specific timestamp
     * @param app The application address
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The sum of local and all remote liquidity for the account at the timestamp
     */
    function getAggregatedLiquidityAt(address app, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the aggregated account liquidity across specified chains at a specific timestamp
     * @param app The application address
     * @param chainUIDs Array of chain unique identifiers to aggregate
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The sum of local and specified remote liquidity for the account at the timestamp
     */
    function getAggregatedLiquidityAt(address app, bytes32[] memory chainUIDs, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the account liquidity from a specific remote chain at a timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The liquidity from the specified chain at the timestamp
     */
    function getRemoteLiquidityAt(address app, bytes32 chainUID, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets data from a specific remote chain at a timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return value The remote data hash at the timestamp
     */
    function getRemoteDataAt(address app, bytes32 chainUID, bytes32 key, uint64 timestamp)
        external
        view
        returns (bytes memory value);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new version for state isolation
     * @dev Only callable by whitelisted settlers. Used for handling reorganizations
     *      or other state isolation requirements.
     * @param timestamp The timestamp of the new version
     */
    function addVersion(uint64 timestamp) external;

    /**
     * @notice Updates the LocalAppChronicle deployer
     * @dev Only callable by owner. Used to upgrade chronicle creation logic.
     * @param deployer The new LocalAppChronicle deployer contract
     */
    function updateLocalAppChronicleDeployer(address deployer) external;

    /**
     * @notice Updates the RemoteAppChronicle deployer
     * @dev Only callable by owner. Used to upgrade chronicle creation logic.
     * @param deployer The new RemoteAppChronicle deployer contract
     */
    function updateRemoteAppChronicleDeployer(address deployer) external;

    /**
     * @notice Registers an application with the LiquidityMatrix
     * @dev Creates a LocalAppChronicle for the app in the current version
     * @param syncMappedAccountsOnly If true, only syncs liquidity for mapped accounts
     * @param useHook If true, triggers callbacks to the app on state updates
     * @param settler Address authorized to settle roots for this app
     */
    function registerApp(bool syncMappedAccountsOnly, bool useHook, address settler) external;

    /**
     * @notice Updates whether the app syncs only mapped accounts
     * @param syncMappedAccountsOnly New setting value
     */
    function updateSyncMappedAccountsOnly(bool syncMappedAccountsOnly) external;

    /**
     * @notice Updates whether callbacks are enabled for the app
     * @param useHook New setting value
     */
    function updateUseHook(bool useHook) external;

    /**
     * @notice Updates the authorized settler for the app
     * @param settler New settler address
     */
    function updateSettler(address settler) external;

    /**
     * @notice Updates the remote app address and index for a specific chain
     * @param chainUID The chain unique identifier
     * @param app The remote app address on the specified chain
     * @param appIndex The index of the app on the remote chain
     */
    function updateRemoteApp(bytes32 chainUID, address app, uint256 appIndex) external;

    /**
     * @notice Adds a LocalAppChronicle for an app at a specific version
     * @dev Only callable by the app's settler. Required after a reorg to enable local state tracking.
     * @param app The application address
     * @param version The version number for the chronicle
     */
    function addLocalAppChronicle(address app, uint256 version) external;

    /**
     * @notice Adds a RemoteAppChronicle for an app on a specific chain and version
     * @dev Only callable by the app's settler. Required to enable remote state settlement.
     * @param app The application address
     * @param chainUID The chain unique identifier
     * @param version The version number for the chronicle
     */
    function addRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) external;

    /**
     * @notice Updates the top liquidity tree with an app's liquidity root
     * @dev Only callable by LocalAppChronicle. Propagates app tree changes to top tree.
     * @param version The version number
     * @param app The application address
     * @param appLiquidityRoot The app's liquidity tree root
     * @return treeIndex The index in the top liquidity tree
     */
    function updateTopLiquidityTree(uint256 version, address app, bytes32 appLiquidityRoot)
        external
        returns (uint256 treeIndex);

    /**
     * @notice Updates the top data tree with an app's data root
     * @dev Only callable by LocalAppChronicle. Propagates app tree changes to top tree.
     * @param version The version number
     * @param app The application address
     * @param appDataRoot The app's data tree root
     * @return treeIndex The index in the top data tree
     */
    function updateTopDataTree(uint256 version, address app, bytes32 appDataRoot)
        external
        returns (uint256 treeIndex);

    /**
     * @notice Updates the local liquidity for an account
     * @dev Only callable by registered apps. Delegates to the app's LocalAppChronicle.
     * @param account The account to update
     * @param liquidity The new liquidity value (replaces current value)
     * @return mainTreeIndex The index in the main liquidity tree
     * @return appTreeIndex The index in the app's liquidity tree
     */
    function updateLocalLiquidity(address account, int256 liquidity)
        external
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

    /**
     * @notice Updates local data for a key
     * @dev Only callable by registered apps. Delegates to the app's LocalAppChronicle.
     * @param key The data key to update
     * @param value The data value to store
     * @return mainTreeIndex The index in the main data tree
     * @return appTreeIndex The index in the app's data tree
     */
    function updateLocalData(bytes32 key, bytes memory value)
        external
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

    /**
     * @notice Updates the whitelist status of a settler account
     * @dev Only callable by owner
     * @param account The account to update
     * @param whitelisted Whether to whitelist the account
     */
    function updateSettlerWhitelisted(address account, bool whitelisted) external;

    /**
     * @notice Sets the gateway contract address
     * @dev Only callable by owner. The gateway handles all cross-chain communication.
     * @param _gateway Address of the gateway contract
     */
    function updateGateway(address _gateway) external;

    /**
     * @notice Sets the syncer address
     * @dev Only callable by owner. The syncer can initiate sync operations.
     * @param _syncer Address of the syncer
     */
    function updateSyncer(address _syncer) external;

    /**
     * @notice Configures which chains to read from and their target addresses for sync operations
     * @dev Only callable by owner. These chains must be configured in the gateway.
     * @param chainUIDs Array of chain UIDs to read from
     * @param targets Array of target addresses for each chain
     */
    function configureReadChains(bytes32[] memory chainUIDs, address[] memory targets) external;

    /**
     * @notice Initiates a sync operation to fetch roots from all configured chains
     * @dev Only callable by the authorized syncer. Rate limited to once per block.
     * @param data Encoded (uint128 gasLimit, address refundTo) for the cross-chain operation
     * @return guid The messaging receipt from the gateway
     */
    function sync(bytes memory data) external payable returns (bytes32 guid);

    /**
     * @notice Quotes the messaging fee for syncing all configured chains
     * @param gasLimit The gas limit for the operation
     * @return fee The estimated messaging fee in native token
     */
    function quoteSync(uint128 gasLimit) external view returns (uint256 fee);

    /**
     * @notice Requests mapping of remote accounts to local accounts on another chain
     * @dev Only callable by registered apps. Sends a cross-chain message to map accounts.
     * @param chainUID Target chain unique identifier
     * @param remoteApp Address of the app on the remote chain
     * @param remotes Array of remote account addresses
     * @param locals Array of local account addresses to map to
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     */
    function requestMapRemoteAccounts(
        bytes32 chainUID,
        address remoteApp,
        address[] memory remotes,
        address[] memory locals,
        bytes memory data
    ) external payable returns (bytes32 guid);

    /**
     * @notice Processes roots received from remote chains
     * @dev Only callable internally by the contract itself (via onRead)
     * @param chainUID The chain unique identifier
     * @param version The version number from the remote chain
     * @param liquidityRoot The liquidity tree root from the remote chain
     * @param dataRoot The data tree root from the remote chain
     * @param timestamp The timestamp of the roots
     */
    function onReceiveRoots(
        bytes32 chainUID,
        uint256 version,
        bytes32 liquidityRoot,
        bytes32 dataRoot,
        uint64 timestamp
    ) external;

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
    ) external;
}
