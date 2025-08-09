// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract LayerZeroGatewayMock {
    uint256 public constant FEE = 0.01 ether;

    mapping(address => mapping(bytes32 => bytes32)) public readTargets;

    function read(bytes memory, bytes memory, uint32, bytes memory) external payable returns (bytes32) {
        require(msg.value >= FEE, "Insufficient fee");
        return bytes32(uint256(1));
    }

    function quoteRead(address, bytes memory, uint32, uint128) external pure returns (uint256) {
        return FEE;
    }

    function updateReadTarget(bytes32 chainUID, bytes32 target) external {
        readTargets[msg.sender][chainUID] = target;
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
