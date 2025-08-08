// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGateway {
    function chainConfigs() external view returns (uint32[] memory eids, uint16[] memory confirmations);

    function quoteRead(address app, bytes memory callData, uint128 gasLimit) external view returns (uint256 fee);

    function updateReadTarget(bytes32 chainIdentifier, bytes32 target) external;

    function read(bytes memory callData, bytes memory extra, bytes memory data)
        external
        payable
        returns (bytes32 guid);
}
