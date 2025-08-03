// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface INativexD is IBaseERC20xD {
    function underlying() external view returns (address);

    function wrap(address to) external payable;

    function unwrap(address to, uint256 amount, bytes memory data) external payable returns (MessagingReceipt memory);

    fallback() external payable;
    receive() external payable;
}
