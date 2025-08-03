// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract ERC20xDGatewayMock {
    uint256 public constant FEE = 0.01 ether;

    function read(bytes memory, bytes memory) external payable returns (MessagingReceipt memory) {
        require(msg.value >= FEE, "Insufficient fee");
        return MessagingReceipt({ guid: bytes32(0), nonce: 0, fee: MessagingFee({ nativeFee: FEE, lzTokenFee: 0 }) });
    }

    function quoteRead(bytes memory, uint128) external pure returns (uint256) {
        return FEE;
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
