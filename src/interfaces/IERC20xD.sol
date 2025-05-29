// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface IERC20xD is IBaseERC20xD {
    function quoteMint(address from, uint128 gasLimit) external view returns (uint256 fee);

    function quoteBurn(address from, uint128 gasLimit) external view returns (uint256);

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount, bytes calldata data) external payable returns (MessagingReceipt memory);
}
