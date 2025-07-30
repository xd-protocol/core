// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

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
     * @notice Returns the configured chain endpoints and their confirmations.
     * @return eids Array of endpoint IDs.
     * @return confirmations Array of confirmation requirements for each endpoint.
     */
    function chainConfigs() external view returns (uint32[] memory eids, uint16[] memory confirmations);

    /**
     * @notice Quotes the messaging fee for syncing all configured chains.
     * @param gasLimit The gas limit to allocate for the executor.
     * @param calldataSize The size of the calldata in bytes.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteSync(uint128 gasLimit, uint32 calldataSize) external view returns (uint256 fee);

    /**
     * @notice Quotes the messaging fee for syncing specific chains.
     * @param eids Array of endpoint IDs to synchronize.
     * @param gasLimit The gas limit to allocate for the executor.
     * @param calldataSize The size of the calldata in bytes.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteSync(uint32[] memory eids, uint128 gasLimit, uint32 calldataSize)
        external
        view
        returns (uint256 fee);

    /**
     * @notice Quotes the messaging fee for requesting remote account mapping.
     * @param eid The endpoint ID of the target chain.
     * @param app The address of the local application.
     * @param remoteApp The address of the remote application.
     * @param remotes Array of remote account addresses.
     * @param locals Array of local account addresses.
     * @param gasLimit The gas limit for the operation.
     * @return fee The estimated messaging fee.
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
     * @notice Initiates a sync operation for all configured chains.
     * @param gasLimit The gas limit to allocate for the executor.
     * @param calldataSize The size of the calldata for the request, in bytes.
     * @return receipt The messaging receipt from LayerZero.
     */
    function sync(uint128 gasLimit, uint32 calldataSize) external payable returns (MessagingReceipt memory receipt);

    /**
     * @notice Initiates a sync operation for specific chains.
     * @param eids Array of endpoint IDs to synchronize.
     * @param gasLimit The gas limit to allocate for the executor.
     * @param calldataSize The size of the calldata for the request, in bytes.
     * @return receipt The messaging receipt from LayerZero.
     */
    function sync(uint32[] memory eids, uint128 gasLimit, uint32 calldataSize)
        external
        payable
        returns (MessagingReceipt memory receipt);

    /**
     * @notice Requests mapping of remote accounts to local accounts.
     * @param eid The endpoint ID of the target chain.
     * @param remoteApp The address of the remote application.
     * @param locals Array of local account addresses.
     * @param remotes Array of remote account addresses.
     * @param gasLimit The gas limit for the operation.
     */
    function requestMapRemoteAccounts(
        uint32 eid,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        uint128 gasLimit
    ) external payable;

    /**
     * @notice Updates the configuration for target chains.
     * @param eids Array of endpoint IDs.
     * @param confirmations Array of confirmation requirements for each endpoint.
     */
    function configChains(uint32[] memory eids, uint16[] memory confirmations) external;

    /**
     * @notice Updates the syncer address.
     * @param syncer The new syncer address.
     */
    function updateSyncer(address syncer) external;

    /**
     * @notice Returns the number of configured endpoint IDs.
     * @return The length of the eids array.
     */
    function eidsLength() external view returns (uint256);

    /**
     * @notice Returns the endpoint ID at the specified index.
     * @param index The index in the eids array.
     * @return The endpoint ID at the given index.
     */
    function eidAt(uint256 index) external view returns (uint32);

    /**
     * @notice Constructs and encodes the read command for LayerZero's read protocol.
     * @return The encoded command with all configured chain requests.
     */
    function getSyncCmd() external view returns (bytes memory);

    /**
     * @notice Processes the responses from LayerZero's read protocol.
     * @param _cmd The encoded command specifying the request details.
     * @param _responses An array of responses corresponding to each read request.
     * @return The aggregated result.
     */
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory);
}
