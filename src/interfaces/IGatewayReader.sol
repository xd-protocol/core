// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGatewayReader {
    struct Request {
        bytes32 chainIdentifier;
        uint64 timestamp;
        address target;
    }

    function reduce(Request[] calldata requests, bytes calldata callData, bytes[] calldata responses)
        external
        view
        returns (bytes memory);

    function onRead(bytes calldata _message, bytes calldata _extra) external;
}
