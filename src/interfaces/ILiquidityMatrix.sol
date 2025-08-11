// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IGateway } from "./IGateway.sol";

interface ILiquidityMatrix {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyRequested();
    error AppChronicleAlreadyAdded();
    error AppNotRegistered();
    error AppAlreadyRegistered();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidCmd();
    error InvalidLengths();
    error InvalidSettler();
    error InvalidTimestamp();
    error InvalidVersion();
    error Forbidden();
    error IdenticalAccounts();
    error LocalAccountAlreadyMapped(bytes32 chainUID, address local);
    error LocalAppChronicleNotSet();
    error RemoteAccountAlreadyMapped(bytes32 chainUID, address remote);
    error RemoteAppChronicleNotSet(bytes32 chainUID);

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
    event UpdateTopLiquidityTree(
        uint256 indexed version, address indexed app, bytes32 appLiquidityRoot, bytes32 topLiquidityRoot
    );
    event UpdateTopDataTree(uint256 indexed version, address indexed app, bytes32 appDataRoot, bytes32 topDataRoot);

    event UpdateSettlerWhitelisted(address indexed account, bool whitelisted);
    event UpdateRemoteApp(address indexed app, bytes32 indexed chainUID, address indexed remoteApp);
    event MapRemoteAccount(address indexed app, bytes32 indexed chainUID, address indexed remote, address local);
    event RequestMapRemoteAccounts(
        address indexed app, bytes32 indexed chainUID, address indexed remoteApp, address[] remotes, address[] locals
    );

    event OnReceiveRoots(
        bytes32 indexed chainUID,
        uint256 indexed version,
        bytes32 liquidityRoot,
        bytes32 dataRoot,
        uint64 indexed timestamp
    );

    event UpdateGateway(address indexed gateway);
    event UpdateSyncer(address indexed syncer);
    event Sync(address indexed caller);

    /*//////////////////////////////////////////////////////////////
                        LOCAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getTopRoots()
        external
        view
        returns (uint256 version, bytes32 liquidityRoot, bytes32 dataRoot, uint64 timestamp);

    /**
     * @notice Returns the settings for a registered application
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

    function getCurrentLocalAppChronicle(address app) external view returns (address);

    function getLocalAppChronicle(address app, uint256 version) external view returns (address);

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
     * @notice Gets the current local liquidity for a specific account in an app
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

    function getLocalTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256);

    function getLocalData(address app, bytes32 key) external view returns (bytes memory);

    function getLocalDataAt(address app, bytes32 key, uint64 timestamp) external view returns (bytes memory);

    /*//////////////////////////////////////////////////////////////
                        REMOTE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the gateway contract
     * @return The gateway contract
     */
    function gateway() external view returns (IGateway);

    /**
     * @notice Returns the chain configurations from the gateway
     * @dev Delegates to gateway.chainConfigs()
     * @return chainUIDs Array of chain unique identifiers
     * @return confirmations Array of confirmation requirements for each chain
     */
    function chainConfigs() external view returns (bytes32[] memory chainUIDs, uint16[] memory confirmations);

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
     * @notice Gets the local account mapped to a remote account
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param remote The remote account address
     * @return local The mapped local account address
     */
    function getMappedAccount(address app, bytes32 chainUID, address remote) external view returns (address);

    function getLocalAccount(address app, bytes32 chainUID, address remote) external view returns (address);

    /**
     * @notice Checks if a local account is already mapped to a remote account
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param local The local account address
     * @return Whether the local account is mapped
     */
    function isLocalAccountMapped(address app, bytes32 chainUID, address local) external view returns (bool);

    function getCurrentRemoteAppChronicle(address app, bytes32 chainUID) external view returns (address);

    function getRemoteAppChronicleAt(address app, bytes32 chainUID, uint64 timestamp) external view returns (address);

    function getRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                        REMOTE ROOT VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the liquidity root at a specific timestamp
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to query
     * @return root The liquidity root at the timestamp
     */
    function getLiquidityRootAt(bytes32 chainUID, uint64 timestamp) external view returns (bytes32 root);

    function getLiquidityRootAt(bytes32 chainUID, uint256 version, uint64 timestamp)
        external
        view
        returns (bytes32 root);

    /**
     * @notice Gets the last received liquidity root from a remote chain
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedLiquidityRoot(bytes32 chainUID) external view returns (bytes32 root, uint64 timestamp);

    function getLastReceivedLiquidityRoot(bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last settled liquidity root for an app on a specific chain
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp of the settled root
     */
    function getLastSettledLiquidityRoot(address app, bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    function getLastSettledLiquidityRoot(address app, bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last finalized liquidity root (both liquidity and data settled)
     * @dev A root is finalized when both liquidity and data roots are settled for the same timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp of the finalized root
     */
    function getLastFinalizedLiquidityRoot(address app, bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    function getLastFinalizedLiquidityRoot(address app, bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the data root at a specific timestamp
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to query
     * @return root The data root at the timestamp
     */
    function getDataRootAt(bytes32 chainUID, uint64 timestamp) external view returns (bytes32 root);

    function getDataRootAt(bytes32 chainUID, uint256 version, uint64 timestamp) external view returns (bytes32 root);

    /**
     * @notice Gets the last received data root from a remote chain
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedDataRoot(bytes32 chainUID) external view returns (bytes32 root, uint64 timestamp);

    function getLastReceivedDataRoot(bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /**
     * @notice Gets the last settled data root for an app on a specific chain
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp of the settled root
     */
    function getLastSettledDataRoot(address app, bytes32 chainUID)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    function getLastSettledDataRoot(address app, bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

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
        returns (bytes32 root, uint64 timestamp);

    function getLastFinalizedDataRoot(address app, bytes32 chainUID, uint256 version)
        external
        view
        returns (bytes32 root, uint64 timestamp);

    /*//////////////////////////////////////////////////////////////
                        REMOTE STATE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAggregatedSettledTotalLiquidity(address app) external view returns (int256 liquidity);

    function getAggregatedSettledTotalLiquidity(address app, bytes32[] memory chainUIDs)
        external
        view
        returns (int256 liquidity);

    function getAggregatedFinalizedTotalLiquidity(address app) external view returns (int256 liquidity);

    function getAggregatedFinalizedTotalLiquidity(address app, bytes32[] memory chainUIDs)
        external
        view
        returns (int256 liquidity);

    function getAggregatedTotalLiquidityAt(address app, uint64 timestamp) external view returns (int256 liquidity);

    function getAggregatedTotalLiquidityAt(address app, bytes32[] memory chainUIDs, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the total liquidity at the timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity at the latest valid timestamp
     */
    function getTotalLiquidityAt(address app, bytes32 chainUID, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    function getAggregatedSettledLiquidityAt(address app, address account) external view returns (int256 liquidity);

    function getAggregatedSettledLiquidityAt(address app, bytes32[] memory chainUIDs, address account)
        external
        view
        returns (int256 liquidity);

    function getAggregatedFinalizedLiquidityAt(address app, address account) external view returns (int256 liquidity);

    function getAggregatedFinalizedLiquidityAt(address app, bytes32[] memory chainUIDs, address account)
        external
        view
        returns (int256 liquidity);

    function getAggregatedLiquidityAt(address app, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    function getAggregatedLiquidityAt(address app, bytes32[] memory chainUIDs, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    function getLiquidityAt(address app, bytes32 chainUID, address account, uint64 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the data from a remote chain at a specific timestamp
     * @param app The application address
     * @param chainUID The chain unique identifier of the remote chain
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return value The remote data hash at the timestamp
     */
    function getDataAt(address app, bytes32 chainUID, bytes32 key, uint64 timestamp)
        external
        view
        returns (bytes memory value);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function addReorg(uint64 timestamp) external;

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

    function addLocalAppChronicle(address app, uint256 version) external;

    function addRemoteAppChronicle(address app, bytes32 chainUID, uint256 version) external;

    function updateTopLiquidityTree(uint256 version, address app, bytes32 appLiquidityRoot)
        external
        returns (uint256 treeIndex);

    function updateTopDataTree(uint256 version, address app, bytes32 appDataRoot)
        external
        returns (uint256 treeIndex);

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
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

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
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

    /*//////////////////////////////////////////////////////////////
                        REMOTE STATE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates whether an account is whitelisted as a settler
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
     * @notice Updates the read target for a specific chain
     * @dev Updates where to read from on the remote chain
     * @param chainUID The chain unique identifier
     * @param target The target address on the remote chain
     */
    function updateReadTarget(bytes32 chainUID, bytes32 target) external;

    /**
     * @notice Initiates a sync operation to fetch roots from all configured chains
     * @dev Only callable by the authorized syncer. Rate limited to once per block.
     * @param data Encoded (uint128 gasLimit, address refundTo) for the cross-chain operation
     * @return receipt The messaging receipt from the gateway
     */
    function sync(bytes memory data) external payable returns (MessagingReceipt memory receipt);

    /**
     * @notice Quotes the messaging fee for syncing all configured chains
     * @param gasLimit The gas limit for the operation
     * @return fee The estimated messaging fee in native token
     */
    function quoteSync(uint128 gasLimit) external view returns (uint256 fee);

    /**
     * @notice Requests to map remote accounts to local accounts
     * @dev Sends a cross-chain message via the synchronizer
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
     * @notice Receives and stores roots from a remote chain
     * @dev Only callable by the synchronizer
     * @param chainUID The chain unique identifier of the remote chain
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
     * @param _message Encoded remote and local account arrays
     */
    function onReceiveMapRemoteAccountRequests(bytes32 _fromChainUID, address _localApp, bytes memory _message)
        external;
}
