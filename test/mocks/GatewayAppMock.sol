// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IGatewayApp } from "src/interfaces/IGatewayApp.sol";

/**
 * @title GatewayAppMock
 * @notice Mock implementation of IGatewayApp for testing
 */
contract GatewayAppMock is IGatewayApp {
    bytes public lastMessage;
    bytes public lastExtra;
    bytes32 public lastSourceChain;
    bytes public lastReceivedMessage;
    bool public reduceCallSuccess = true;
    bytes public reduceReturnData;

    constructor() {
        reduceReturnData = abi.encode(uint256(300)); // Default aggregation result
    }

    function reduce(
        Request[] calldata, // requests - unused
        bytes calldata, // callData - unused
        bytes[] calldata responses
    ) external view returns (bytes memory) {
        require(reduceCallSuccess, "Reduce failed");

        // Simple aggregation: sum all uint256 responses
        uint256 total = 0;
        for (uint256 i = 0; i < responses.length; i++) {
            if (responses[i].length > 0) {
                uint256 value = abi.decode(responses[i], (uint256));
                total += value;
            }
        }

        return abi.encode(total);
    }

    function onRead(bytes calldata _message, bytes calldata _extra) external {
        lastMessage = _message;
        lastExtra = _extra;
    }

    function onReceive(bytes32 sourceChainId, bytes calldata message) external {
        lastSourceChain = sourceChainId;
        lastReceivedMessage = message;
    }

    function setReduceSuccess(bool success) external {
        reduceCallSuccess = success;
    }

    function setReduceReturnData(bytes memory data) external {
        reduceReturnData = data;
    }
}
