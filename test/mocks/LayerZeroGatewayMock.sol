// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract LayerZeroGatewayMock {
    uint256 public constant FEE = 0.01 ether;

    function read(
        bytes32[] memory chainUIDs,
        address[] memory targets,
        bytes memory callData,
        bytes memory extra,
        uint32 returnDataSize,
        bytes memory data
    ) external payable returns (bytes32) {
        require(msg.value >= FEE, "Insufficient fee");
        require(chainUIDs.length == targets.length, "Invalid lengths");
        return bytes32(uint256(1));
    }

    function quoteRead(
        address app,
        bytes32[] memory chainUIDs,
        address[] memory targets,
        bytes memory callData,
        uint32 returnDataSize,
        uint128 gasLimit
    ) external pure returns (uint256) {
        require(chainUIDs.length == targets.length, "Invalid lengths");
        return FEE;
    }

    function quoteSendMessage(bytes32 chainUID, address app, bytes memory message, uint128 gasLimit)
        external
        pure
        returns (uint256)
    {
        return FEE;
    }

    function sendMessage(bytes32 chainUID, address target, bytes memory message, bytes memory data)
        external
        payable
        returns (bytes32)
    {
        require(msg.value >= FEE, "Insufficient fee");
        return bytes32(uint256(1));
    }

    function chainConfigs() external pure returns (bytes32[] memory chainUIDs, uint16[] memory confirmations) {
        chainUIDs = new bytes32[](1);
        chainUIDs[0] = bytes32(uint256(1));
        confirmations = new uint16[](1);
        confirmations[0] = 0;
    }

    function chainUIDsLength() external pure returns (uint256) {
        return 1;
    }

    function chainUIDAt(uint256) external pure returns (bytes32) {
        return bytes32(uint256(1));
    }

    function getCmd(uint16, address[] memory, bytes memory) external pure returns (bytes memory) {
        return abi.encode("cmd");
    }
}
