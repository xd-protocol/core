// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGateway {
    // Configuration
    function chainConfigs() external view returns (uint32[] memory eids, uint16[] memory confirmations);

    function configChains(uint32[] memory eids, uint16[] memory confirmations) external;

    function eidsLength() external view returns (uint256);

    function eidAt(uint256 index) external view returns (uint32);

    // Reading
    function quoteRead(address app, bytes memory callData, uint32 returnDataSize, uint128 gasLimit)
        external
        view
        returns (uint256 fee);

    function updateReadTarget(bytes32 chainIdentifier, bytes32 target) external;

    function read(bytes memory callData, bytes memory extra, uint32 returnDataSize, bytes memory data)
        external
        payable
        returns (bytes32 guid);

    // Messaging
    function quoteSendMessage(uint32 eid, address app, bytes memory message, uint128 gasLimit)
        external
        view
        returns (uint256 fee);

    function sendMessage(uint32 eid, bytes memory message, bytes memory data) external payable returns (bytes32 guid);
}
