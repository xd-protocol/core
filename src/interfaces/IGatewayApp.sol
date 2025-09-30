// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGatewayApp {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    struct Request {
        bytes32 chainUID;
        uint64 timestamp;
        address target;
    }

    /**
     * @notice Maps ChainUIDs to target addresses for cross-chain communication
     * @dev Returns an empty array if app has no read targets configured
     * @return chainUIDs The chain UIDs the app reads from
     * @return targets The target address on each chain
     */
    function getReadTargets() external view returns (bytes32[] memory chainUIDs, address[] memory targets);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Aggregates responses from multiple chains into a single result
     * @dev Called by the gateway to combine responses from cross-chain read requests
     * @param requests Array of request information for each chain queried
     * @param callData The original callData that was sent to each chain
     * @param responses Array of encoded responses from each chain
     * @return The aggregated result as encoded bytes
     */
    function reduce(Request[] calldata requests, bytes calldata callData, bytes[] calldata responses)
        external
        view
        returns (bytes memory);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Callback for receiving aggregated results from cross-chain reads
     * @dev Called by the gateway after reduce() processes all responses
     * @param _message The aggregated message from reduce()
     * @param _extra Additional data passed with the original read request
     */
    function onRead(bytes calldata _message, bytes calldata _extra) external;

    /**
     * @notice Callback for receiving direct messages from other chains
     * @dev Called by the gateway when receiving cross-chain messages
     * @param sourceChainId The unique identifier of the source chain
     * @param message The message payload sent from the source chain
     */
    function onReceive(bytes32 sourceChainId, bytes calldata message) external;
}
