// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILiquidityMatrix } from "./ILiquidityMatrix.sol";

interface IERC20xDGateway {
    function chainConfigs() external view returns (ILiquidityMatrix.ChainConfig[] memory);

    function transferDelay(uint32 eid) external view returns (uint256);

    function quoteRead(bytes memory cmd, uint128 gasLimit) external view returns (uint256 fee);

    function getCmd(uint16 cmdLabel, address[] memory targets, bytes memory callData)
        external
        view
        returns (bytes memory);

    function read(bytes memory cmd, bytes memory data) external payable returns (MessagingReceipt memory receipt);
}
