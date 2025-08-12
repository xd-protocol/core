// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGateway {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(address indexed app, uint16 indexed cmdLabel);
    event UpdateTransferDelay(uint32 indexed eid, uint64 delay);
    event UpdateReadTarget(address indexed app, uint32 indexed eid, bytes32 indexed target);
    event MessageSent(uint32 indexed eid, bytes32 indexed guid, bytes message);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();
    error InvalidApp();
    error InvalidTarget();
    error InvalidLengths();
    error InvalidChainUID();
    error InvalidLzReadOptions();
    error InvalidGuid();
    error InvalidCmdLabel();
    error InvalidRequests();
    error DuplicateTargetEid();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Gets the current chain configuration
     * @return chainUIDs Array of configured chain UIDs
     * @return confirmations Array of confirmation requirements for each chain
     */
    function chainConfigs() external view returns (bytes32[] memory chainUIDs, uint16[] memory confirmations);

    /**
     * @notice Configures the chains and confirmation requirements
     * @param chainUIDs Array of chain UIDs to configure
     * @param confirmations Array of confirmation requirements for each chain
     */
    function configChains(bytes32[] memory chainUIDs, uint16[] memory confirmations) external;

    /**
     * @notice Returns the number of configured chains
     * @return The length of configured chains
     */
    function chainUIDsLength() external view returns (uint256);

    /**
     * @notice Gets the chain UID at a specific index
     * @param index The index to query
     * @return The chain UID at the index
     */
    function chainUIDAt(uint256 index) external view returns (bytes32);

    /**
     * @notice Registers an application with the gateway
     * @param app The application address to register
     */
    function registerApp(address app) external;

    /**
     * @notice Updates transfer delays for specific chains
     * @param chainUIDs Array of chain UIDs to update
     * @param delays Array of delay values for each chain
     */
    function updateTransferDelays(bytes32[] memory chainUIDs, uint64[] memory delays) external;

    /**
     * @notice Processes and aggregates responses from cross-chain read protocol
     * @param _cmd The encoded command from the underlying protocol
     * @param _responses Array of responses from each chain
     * @return The aggregated result from the callback contract
     */
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external view returns (bytes memory);
    /**
     * @notice Quotes the messaging fee for a cross-chain read request
     * @param app The application requesting the read
     * @param callData The function call data to execute on remote chains
     * @param returnDataSize Expected size of return data per chain
     * @param gasLimit Gas limit for the operation
     * @return fee The estimated messaging fee
     */
    function quoteRead(address app, bytes memory callData, uint32 returnDataSize, uint128 gasLimit)
        external
        view
        returns (uint256 fee);

    /**
     * @notice Updates the read target address for a specific chain
     * @param chainUID The chain unique identifier
     * @param target The target address on the remote chain
     */
    function updateReadTarget(bytes32 chainUID, bytes32 target) external;

    /**
     * @notice Executes a cross-chain read operation
     * @param callData The function call data to execute on remote chains
     * @param extra Additional data for the operation
     * @param returnDataSize Expected size of return data per chain
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     * @return guid The unique identifier for this read operation
     */
    function read(bytes memory callData, bytes memory extra, uint32 returnDataSize, bytes memory data)
        external
        payable
        returns (bytes32 guid);

    /**
     * @notice Quotes the messaging fee for sending a message to a specific chain
     * @param chainUID The destination chain unique identifier
     * @param app The application sending the message
     * @param message The message to send
     * @param gasLimit Gas limit for the operation
     * @return fee The estimated messaging fee
     */
    function quoteSendMessage(bytes32 chainUID, address app, bytes memory message, uint128 gasLimit)
        external
        view
        returns (uint256 fee);

    /**
     * @notice Sends a message to a specific chain
     * @param chainUID The destination chain unique identifier
     * @param message The message to send
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     * @return guid The unique identifier for this message
     */
    function sendMessage(bytes32 chainUID, bytes memory message, bytes memory data)
        external
        payable
        returns (bytes32 guid);
}
