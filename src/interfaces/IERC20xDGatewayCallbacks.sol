// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20xDGatewayCallbacks {
    function onRead(bytes memory _message) external;
}
