// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidityMatrix {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AppNotRegistered();
    error AppAlreadyRegistered();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidLengths();
    error Forbidden();
    error RemoteAccountAlreadyMapped(uint32 eid, address remote);
    error LocalAccountAlreadyMapped(uint32 eid, address local);
    error LiquidityAlreadySettled();
    error DataAlreadySettled();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(address indexed app, bool syncMappedAccountsOnly, bool useCallbacks, address settler);
    event UpdateSyncMappedAccountsOnly(address indexed app, bool syncMappedAccountsOnly);
    event UpdateUseCallbacks(address indexed app, bool useCallbacks);
    event UpdateSettler(address indexed app, address settler);
    event UpdateSettlerWhitelisted(address indexed account, bool whitelisted);

    event UpdateLocalLiquidity(
        address indexed app,
        uint256 mainTreeIndex,
        address indexed account,
        int256 liquidity,
        uint256 appTreeIndex,
        uint256 indexed timestamp
    );

    event UpdateLocalData(
        address indexed app,
        uint256 mainTreeIndex,
        bytes32 indexed key,
        bytes value,
        bytes32 hash,
        uint256 appTreeIndex,
        uint256 indexed timestamp
    );

    event UpdateRemoteApp(address indexed app, uint32 indexed eid, address indexed remoteApp);
    event MapRemoteAccount(address indexed app, uint32 indexed eid, address indexed remote, address local);

    event OnReceiveRoots(
        uint32 indexed eid, bytes32 indexed liquidityRoot, bytes32 indexed dataRoot, uint256 timestamp
    );

    event UpdateSynchronizer(address indexed synchronizer);

    event SettleLiquidity(uint32 indexed eid, address indexed app, bytes32 indexed liquidityRoot, uint256 timestamp);
    event SettleData(uint32 indexed eid, address indexed app, bytes32 indexed dataRoot, uint256 timestamp);

    event OnUpdateLiquidityFailure(
        uint32 indexed eid, uint256 indexed timestamp, address indexed account, int256 liquidity, bytes reason
    );
    event OnUpdateTotalLiquidityFailure(
        uint32 indexed eid, uint256 indexed timestamp, int256 totalLiquidity, bytes reason
    );
    event OnUpdateDataFailure(
        uint32 indexed eid, uint256 indexed timestamp, bytes32 indexed key, bytes value, bytes reason
    );

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct SettleLiquidityParams {
        address app;
        uint32 eid;
        uint256 timestamp;
        address[] accounts;
        int256[] liquidity;
    }

    struct SettleDataParams {
        address app;
        uint32 eid;
        uint256 timestamp;
        bytes32[] keys;
        bytes[] values;
    }

    /*//////////////////////////////////////////////////////////////
                        LOCAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the synchronizer contract
     * @dev The synchronizer handles all cross-chain communication
     * @return The synchronizer contract address
     */
    function synchronizer() external view returns (address);

    /**
     * @notice Gets the current main tree roots and timestamp
     * @return liquidityRoot The main liquidity tree root
     * @return dataRoot The main data tree root
     * @return timestamp The current block timestamp
     */
    function getMainRoots() external view returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp);

    /**
     * @notice Gets the current root of the main liquidity tree
     * @return The main liquidity tree root
     */
    function getMainLiquidityRoot() external view returns (bytes32);

    /**
     * @notice Gets the current root of the main data tree
     * @return The main data tree root
     */
    function getMainDataRoot() external view returns (bytes32);

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
        returns (bool registered, bool syncMappedAccountsOnly, bool useCallbacks, address settler);

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
    function getLocalLiquidityAt(address app, address account, uint256 timestamp)
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
     * @return liquidity The total liquidity at the timestamp
     */
    function getLocalTotalLiquidityAt(address app, uint256 timestamp) external view returns (int256 liquidity);

    /**
     * @notice Gets the current hash of data stored under a key for an app
     * @param app The application address
     * @param key The data key
     * @return hash The current data hash
     */
    function getLocalDataHash(address app, bytes32 key) external view returns (bytes32 hash);

    /**
     * @notice Gets the data hash for a key at a specific timestamp
     * @param app The application address
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return hash The data hash at the timestamp
     */
    function getLocalDataHashAt(address app, bytes32 key, uint256 timestamp) external view returns (bytes32 hash);

    /*//////////////////////////////////////////////////////////////
                        REMOTE VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if an account is whitelisted as a settler
     * @param account The account to check
     * @return Whether the account is whitelisted
     */
    function isSettlerWhitelisted(address account) external view returns (bool);

    /**
     * @notice Gets the remote app address for a given chain
     * @param app The local application address
     * @param eid The endpoint ID of the remote chain
     * @return The remote application address
     */
    function getRemoteApp(address app, uint32 eid) external view returns (address);

    /**
     * @notice Gets the local account mapped to a remote account
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param remote The remote account address
     * @return local The mapped local account address
     */
    function getMappedAccount(address app, uint32 eid, address remote) external view returns (address);

    function getLocalAccount(address app, uint32 eid, address remote) external view returns (address);

    /**
     * @notice Checks if a local account is already mapped to a remote account
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param local The local account address
     * @return Whether the local account is mapped
     */
    function isLocalAccountMapped(address app, uint32 eid, address local) external view returns (bool);

    /**
     * @notice Gets the last received liquidity root from a remote chain
     * @param eid The endpoint ID of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedLiquidityRoot(uint32 eid) external view returns (bytes32 root, uint256 timestamp);

    /**
     * @notice Gets the last settled liquidity root for an app on a specific chain
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp of the settled root
     */
    function getLastSettledLiquidityRoot(address app, uint32 eid)
        external
        view
        returns (bytes32 root, uint256 timestamp);

    /**
     * @notice Gets the last finalized liquidity root (both liquidity and data settled)
     * @dev A root is finalized when both liquidity and data roots are settled for the same timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return root The liquidity root hash
     * @return timestamp The timestamp of the finalized root
     */
    function getLastFinalizedLiquidityRoot(address app, uint32 eid)
        external
        view
        returns (bytes32 root, uint256 timestamp);

    /**
     * @notice Gets the liquidity root at a specific timestamp
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to query
     * @return root The liquidity root at the timestamp
     */
    function getLiquidityRootAt(uint32 eid, uint256 timestamp) external view returns (bytes32 root);

    /**
     * @notice Gets the last received data root from a remote chain
     * @param eid The endpoint ID of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp when the root was received
     */
    function getLastReceivedDataRoot(uint32 eid) external view returns (bytes32 root, uint256 timestamp);

    /**
     * @notice Gets the last settled data root for an app on a specific chain
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return root The data root hash
     * @return timestamp The timestamp of the settled root
     */
    function getLastSettledDataRoot(address app, uint32 eid) external view returns (bytes32 root, uint256 timestamp);

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
        returns (bytes32 root, uint256 timestamp);

    /**
     * @notice Gets the data root at a specific timestamp
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to query
     * @return root The data root at the timestamp
     */
    function getDataRootAt(uint32 eid, uint256 timestamp) external view returns (bytes32 root);

    /**
     * @notice Checks if a liquidity root has been settled for an app
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the liquidity root is settled
     */
    function isLiquiditySettled(address app, uint32 eid, uint256 timestamp) external view returns (bool);

    /**
     * @notice Checks if a data root has been settled for an app
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the data root is settled
     */
    function isDataSettled(address app, uint32 eid, uint256 timestamp) external view returns (bool);

    /**
     * @notice Checks if both roots are finalized for a given timestamp
     * @dev Returns true if both liquidity and data are settled
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to check
     * @return Whether the roots are finalized
     */
    function isFinalized(address app, uint32 eid, uint256 timestamp) external view returns (bool);

    /**
     * @notice Gets the total liquidity across all chains where liquidity is settled
     * @dev Aggregates local liquidity and remote liquidity from all configured chains
     * @param app The application address
     * @return liquidity The total settled liquidity
     */
    function getSettledTotalLiquidity(address app) external view returns (int256 liquidity);
    /**
     * @notice Gets the total liquidity across all chains where both roots are finalized
     * @dev More conservative than settled - requires both liquidity and data roots to be settled
     * @param app The application address
     * @return liquidity The total finalized liquidity
     */
    function getFinalizedTotalLiquidity(address app) external view returns (int256 liquidity);

    /**
     * @notice Gets the total liquidity at the timestamp
     * @param app The application address
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity at the latest valid timestamp
     */
    function getTotalLiquidityAt(address app, uint256 timestamp) external view returns (int256 liquidity);

    /**
     * @notice Gets the liquidity for an account across all chains where liquidity is settled
     * @param app The application address
     * @param account The account address
     * @return liquidity The total settled liquidity for the account
     */
    function getSettledLiquidity(address app, address account) external view returns (int256 liquidity);

    /**
     * @notice Gets the liquidity for an account across all chains where both roots are finalized
     * @param app The application address
     * @param account The account address
     * @return liquidity The total finalized liquidity for the account
     */
    function getFinalizedLiquidity(address app, address account) external view returns (int256 liquidity);

    /**
     * @notice Gets the liquidity for an account at the timestamp
     * @param app The application address
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The liquidity at the latest valid timestamp
     */
    function getLiquidityAt(address app, address account, uint256 timestamp) external view returns (int256 liquidity);

    /**
     * @notice Gets the total liquidity from a remote chain at the last settled timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return liquidity The settled remote total liquidity
     */
    function getSettledRemoteTotalLiquidity(address app, uint32 eid) external view returns (int256 liquidity);

    /**
     * @notice Gets the total liquidity from a remote chain at the last finalized timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @return liquidity The finalized remote total liquidity
     */
    function getFinalizedRemoteTotalLiquidity(address app, uint32 eid) external view returns (int256 liquidity);

    /**
     * @notice Gets the total liquidity from a remote chain at a specific timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp to query
     * @return liquidity The remote total liquidity at the timestamp
     */
    function getRemoteTotalLiquidityAt(address app, uint32 eid, uint256 timestamp)
        external
        view
        returns (int256 liquidity);

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
        returns (int256 liquidity);

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
        returns (int256 liquidity);

    /**
     * @notice Gets the liquidity for an account from a remote chain at a specific timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The remote liquidity at the timestamp
     */
    function getRemoteLiquidityAt(address app, uint32 eid, address account, uint256 timestamp)
        external
        view
        returns (int256 liquidity);

    /**
     * @notice Gets the data hash from a remote chain at the last settled timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param key The data key
     * @return value The settled remote data hash
     */
    function getSettledRemoteDataHash(address app, uint32 eid, bytes32 key) external view returns (bytes32 value);

    /**
     * @notice Gets the data hash from a remote chain at the last finalized timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param key The data key
     * @return value The finalized remote data hash
     */
    function getFinalizedRemoteDataHash(address app, uint32 eid, bytes32 key) external view returns (bytes32 value);

    /**
     * @notice Gets the data hash from a remote chain at a specific timestamp
     * @param app The application address
     * @param eid The endpoint ID of the remote chain
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return value The remote data hash at the timestamp
     */
    function getRemoteDataHashAt(address app, uint32 eid, bytes32 key, uint256 timestamp)
        external
        view
        returns (bytes32 value);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new application with the LiquidityMatrix
     * @dev Initializes the app's liquidity and data trees
     * @param syncMappedAccountsOnly If true, only syncs liquidity for mapped accounts
     * @param useCallbacks If true, triggers callbacks to the app on state updates
     * @param settler Address authorized to settle roots for this app
     */
    function registerApp(bool syncMappedAccountsOnly, bool useCallbacks, address settler) external;

    /**
     * @notice Updates whether the app syncs only mapped accounts
     * @param syncMappedAccountsOnly New setting value
     */
    function updateSyncMappedAccountsOnly(bool syncMappedAccountsOnly) external;

    /**
     * @notice Updates whether callbacks are enabled for the app
     * @param useCallbacks New setting value
     */
    function updateUseCallbacks(bool useCallbacks) external;

    /**
     * @notice Updates the authorized settler for the app
     * @param settler New settler address
     */
    function updateSettler(address settler) external;

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

    /**
     * @notice Sets the remote app address for cross-chain communication
     * @param eid The endpoint ID of the remote chain
     * @param remoteApp The app address on the remote chain
     */
    function updateRemoteApp(uint32 eid, address remoteApp) external;

    /**
     * @notice Settles liquidity data from a remote chain
     * @dev Only callable by whitelisted settlers or app's designated settler
     * @param params Settlement parameters including app, chain, timestamp, accounts and liquidity
     */
    function settleLiquidity(SettleLiquidityParams memory params) external;

    /**
     * @notice Settles data from a remote chain
     * @dev Only callable by whitelisted settlers or app's designated settler
     * @param params Settlement parameters including app, chain, timestamp, keys and values
     */
    function settleData(SettleDataParams memory params) external;

    /**
     * @notice Updates whether an account is whitelisted as a settler
     * @dev Only callable by owner
     * @param account The account to update
     * @param whitelisted Whether to whitelist the account
     */
    function updateSettlerWhitelisted(address account, bool whitelisted) external;

    /**
     * @notice Sets the synchronizer contract address
     * @dev Only callable by owner. The synchronizer handles all cross-chain communication
     * @param _synchronizer The new synchronizer address
     */
    function setSynchronizer(address _synchronizer) external;

    /**
     * @notice Requests to map remote accounts to local accounts
     * @dev Sends a cross-chain message via the synchronizer
     * @param eid Target chain endpoint ID
     * @param remoteApp Address of the app on the remote chain
     * @param remotes Array of remote account addresses
     * @param locals Array of local account addresses to map to
     * @param gasLimit Gas limit for the cross-chain message
     */
    function requestMapRemoteAccounts(
        uint32 eid,
        address remoteApp,
        address[] memory remotes,
        address[] memory locals,
        uint128 gasLimit
    ) external payable;

    /**
     * @notice Receives and stores roots from a remote chain
     * @dev Only callable by the synchronizer
     * @param eid The endpoint ID of the remote chain
     * @param liquidityRoot The liquidity tree root from the remote chain
     * @param dataRoot The data tree root from the remote chain
     * @param timestamp The timestamp of the roots
     */
    function onReceiveRoots(uint32 eid, bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) external;

    /**
     * @notice Processes remote account mapping requests received from other chains
     * @dev Called by synchronizer when receiving cross-chain mapping requests.
     *      Validates mappings and consolidates liquidity from remote to local accounts.
     * @param _fromEid Source chain endpoint ID
     * @param _localApp Local app address that should process this request
     * @param _message Encoded remote and local account arrays
     */
    function onReceiveMapRemoteAccountRequests(uint32 _fromEid, address _localApp, bytes memory _message) external;
}
