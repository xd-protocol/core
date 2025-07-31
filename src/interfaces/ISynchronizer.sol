// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/**
 * @title ISynchronizer
 * @notice Interface for cross-chain synchronization of liquidity and data roots
 * @dev Implements LayerZero's read and messaging protocols to synchronize state across multiple chains.
 *      This interface is pluggable and can be implemented with different interoperability solutions.
 *
 * The Synchronizer serves as a bridge between LiquidityMatrix and cross-chain infrastructure:
 * - Fetches roots from multiple chains using read protocols
 * - Handles cross-chain account mapping requests
 * - Enforces rate limiting (one sync per block)
 * - Manages configurable target chains and confirmations
 */
interface ISynchronizer {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Sync(address indexed caller);
    event UpdateSyncer(address indexed syncer);
    event RequestMapRemoteAccounts(
        address indexed app, uint32 indexed eid, address indexed remoteApp, address[] remotes, address[] locals
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();
    error AlreadyRequested();
    error InvalidLengths();
    error DuplicateTargetEid();
    error InvalidCmd();
    error InvalidAddress();
    error InvalidMsgType();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the configured chain endpoints and their confirmations
     * @dev Used to query which chains are configured for synchronization
     * @return eids Array of endpoint IDs configured for syncing
     * @return confirmations Array of block confirmation requirements for each endpoint
     */
    function chainConfigs() external view returns (uint32[] memory eids, uint16[] memory confirmations);

    /**
     * @notice Quotes the messaging fee for syncing all configured chains
     * @dev Uses LayerZero's quote mechanism to estimate cross-chain messaging costs
     * @param gasLimit The amount of gas to allocate for the executor
     * @param calldataSize The size of the calldata in bytes
     * @return fee The estimated messaging fee in native token
     */
    function quoteSync(uint128 gasLimit, uint32 calldataSize) external view returns (uint256 fee);

    /**
     * @notice Quotes the messaging fee for syncing specific chains
     * @dev Allows selective syncing of specific chains instead of all configured ones
     * @param eids Array of endpoint IDs to synchronize
     * @param gasLimit The amount of gas to allocate for the executor
     * @param calldataSize The size of the calldata in bytes
     * @return fee The estimated messaging fee in native token
     */
    function quoteSync(uint32[] memory eids, uint128 gasLimit, uint32 calldataSize)
        external
        view
        returns (uint256 fee);

    /**
     * @notice Quotes the messaging fee for requesting remote account mapping
     * @dev Estimates cost for cross-chain account mapping requests
     * @param eid The endpoint ID of the target chain
     * @param app The address of the local application (not used in quote)
     * @param remoteApp The address of the remote application
     * @param remotes Array of remote account addresses to map
     * @param locals Array of local account addresses to map to
     * @param gasLimit The gas limit for the operation
     * @return fee The estimated messaging fee in native token
     */
    function quoteRequestMapRemoteAccounts(
        uint32 eid,
        address app,
        address remoteApp,
        address[] memory remotes,
        address[] memory locals,
        uint128 gasLimit
    ) external view returns (uint256 fee);

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initiates a sync operation for all configured chains
     * @dev Sends cross-chain read requests to fetch main roots from all target chains.
     *      Enforces rate limiting to prevent spam (one request per block).
     *      Only callable by the authorized syncer.
     * @param gasLimit The gas limit to allocate for the executor
     * @param calldataSize The size of the calldata for the request, in bytes
     * @return receipt The messaging receipt from LayerZero (includes guid and fee details)
     */
    function sync(uint128 gasLimit, uint32 calldataSize) external payable returns (MessagingReceipt memory receipt);

    /**
     * @notice Initiates a sync operation for specific chains
     * @dev Allows selective syncing of specific chains. Enforces same rate limiting.
     *      Only callable by the authorized syncer.
     * @param eids Array of endpoint IDs to synchronize
     * @param gasLimit The gas limit to allocate for the executor
     * @param calldataSize The size of the calldata for the request, in bytes
     * @return receipt The messaging receipt from LayerZero (includes guid and fee details)
     */
    function sync(uint32[] memory eids, uint128 gasLimit, uint32 calldataSize)
        external
        payable
        returns (MessagingReceipt memory receipt);

    /**
     * @notice Requests mapping of remote accounts to local accounts on another chain
     * @dev Sends a cross-chain message to map accounts between chains.
     *      The remote chain will validate the mapping via shouldMapAccounts callback.
     *      Arrays must have matching lengths and no zero addresses.
     * @param eid Target chain endpoint ID
     * @param remoteApp Address of the app on the remote chain
     * @param locals Array of local account addresses to map
     * @param remotes Array of remote account addresses to map
     * @param gasLimit Gas limit for the cross-chain message execution
     */
    function requestMapRemoteAccounts(
        uint32 eid,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        uint128 gasLimit
    ) external payable;

    /**
     * @notice Updates the configuration for target chains used in sync operations
     * @dev Clears existing configuration and sets new target chains with their confirmation requirements.
     *      Validates for duplicate endpoint IDs. Only callable by owner.
     * @param eids Array of endpoint IDs to sync with
     * @param confirmations Array of block confirmation requirements for each endpoint
     */
    function configChains(uint32[] memory eids, uint16[] memory confirmations) external;

    /**
     * @notice Updates the authorized syncer address
     * @dev Only the syncer can initiate cross-chain sync operations. Only callable by owner.
     * @param syncer New syncer address
     */
    function updateSyncer(address syncer) external;

    /**
     * @notice Returns the number of configured endpoint IDs
     * @dev Used by LiquidityMatrix to iterate through all configured chains.
     *      This count changes when configChains() is called with a new configuration.
     * @return The length of the target endpoints array
     */
    function eidsLength() external view returns (uint256);

    /**
     * @notice Returns the endpoint ID at the specified index
     * @dev Used by LiquidityMatrix to access specific endpoint IDs during iteration.
     *      Reverts if index is out of bounds.
     * @param index The index in the target endpoints array
     * @return The endpoint ID at the given index
     */
    function eidAt(uint256 index) external view returns (uint32);

    /**
     * @notice Constructs and encodes the read command for LayerZero's read protocol
     * @dev Creates EVMCallRequestV1 structures for each configured target chain to fetch their main roots.
     *      Uses current block timestamp for consistency across chains.
     *      The command includes:
     *      - Target endpoint IDs and their confirmation requirements
     *      - Call to getMainRoots() on each remote LiquidityMatrix
     *      - Compute settings for aggregation via lzReduce()
     * @return The encoded command with all configured chain requests
     */
    function getSyncCmd() external view returns (bytes memory);

    /**
     * @notice Processes the responses from LayerZero's read protocol
     * @dev Called by LayerZero's OAppRead infrastructure to reduce multiple chain responses into a single result.
     *      This aggregation happens on the READ_CHANNEL before forwarding to the target chain.
     *      The function:
     *      - Decodes the command to verify it's a CMD_SYNC request
     *      - Extracts endpoint IDs from the original requests
     *      - Decodes each response to get liquidityRoot, dataRoot, and timestamp
     *      - Aggregates all results into a single encoded response
     * @param _cmd The encoded command specifying the request details
     * @param _responses An array of responses corresponding to each read request
     * @return The aggregated result containing all chain roots and timestamps
     */
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory);
}
