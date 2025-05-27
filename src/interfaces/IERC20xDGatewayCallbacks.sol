// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

interface IERC20xDGatewayCallbacks {
    function onRead(bytes memory _message) external;
}
