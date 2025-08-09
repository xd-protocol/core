// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGateway {
    // Configuration
    function chainConfigs() external view returns (bytes32[] memory chainUIDs, uint16[] memory confirmations);

    function configChains(bytes32[] memory chainUIDs, uint16[] memory confirmations) external;

    function chainUIDsLength() external view returns (uint256);

    function chainUIDAt(uint256 index) external view returns (bytes32);

    // Reading
    function quoteRead(address app, bytes memory callData, uint32 returnDataSize, uint128 gasLimit)
        external
        view
        returns (uint256 fee);

    function updateReadTarget(bytes32 chainUID, bytes32 target) external;

    function read(bytes memory callData, bytes memory extra, uint32 returnDataSize, bytes memory data)
        external
        payable
        returns (bytes32 guid);

    // Messaging
    function quoteSendMessage(bytes32 chainUID, address app, bytes memory message, uint128 gasLimit)
        external
        view
        returns (uint256 fee);

    function sendMessage(bytes32 chainUID, bytes memory message, bytes memory data)
        external
        payable
        returns (bytes32 guid);
}
