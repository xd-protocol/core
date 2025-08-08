// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract LayerZeroReadGatewayMock {
    uint256 public constant FEE = 0.01 ether;

    mapping(address => mapping(uint32 => bytes32)) public readTargets;

    function read(bytes memory, bytes memory, bytes memory) external payable returns (bytes32) {
        require(msg.value >= FEE, "Insufficient fee");
        return bytes32(uint256(1));
    }

    function quoteRead(address, bytes memory, uint128) external pure returns (uint256) {
        return FEE;
    }

    function updateReadTarget(bytes32 chainIdentifier, bytes32 target) external {
        uint32 eid = uint32(uint256(chainIdentifier));
        readTargets[msg.sender][eid] = target;
    }

    function chainConfigs() external pure returns (uint32[] memory eids, uint16[] memory confirmations) {
        eids = new uint32[](1);
        eids[0] = 1;
        confirmations = new uint16[](1);
        confirmations[0] = 0;
    }

    function getCmd(uint16, address[] memory, bytes memory) external pure returns (bytes memory) {
        return abi.encode("cmd");
    }
}
