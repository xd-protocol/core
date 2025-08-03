// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    ILayerZeroEndpointV2,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IERC20Permit } from "./IERC20Permit.sol";

interface IBaseERC20xD is IERC20Permit {
    /**
     * @notice Represents a pending cross-chain transfer.
     * @param pending Indicates if the transfer is still pending.
     * @param from The address initiating the transfer.
     * @param to The recipient address on the target chain.
     * @param amount The amount of tokens to transfer.
     * @param callData Optional calldata for executing a function on the recipient contract.
     * @param value The native cryptocurrency value to send with the callData, if any.
     * @param data Extra data containing LayerZero parameters (gasLimit, refundTo).
     */
    struct PendingTransfer {
        bool pending;
        address from;
        address to;
        uint256 amount;
        bytes callData;
        uint256 value;
        bytes data;
    }

    function liquidityMatrix() external view returns (address);

    function gateway() external view returns (address);

    function peers(uint32 eid) external view returns (bytes32);

    function pendingNonce(address account) external view returns (uint256);

    function pendingTransfer(address account) external view returns (PendingTransfer memory);

    function localTotalSupply() external view returns (int256);

    function localBalanceOf(address account) external view returns (int256);

    function quoteTransfer(address from, uint128 gasLimit) external view returns (uint256);

    function availableLocalBalanceOf(address account, uint256 dummy) external view returns (int256);

    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory);

    function getReadAvailabilityCmd(address from, uint256 nonce) external view returns (bytes memory);

    function setPeer(uint32 eid, bytes32 peer) external;

    function updateLiquidityMatrix(address newLiquidityMatrix) external;

    function updateGateway(address newGateway) external;

    function transfer(address to, uint256 amount, bytes memory data)
        external
        payable
        returns (MessagingReceipt memory);

    function transfer(address to, uint256 amount, bytes memory callData, bytes memory data)
        external
        payable
        returns (MessagingReceipt memory);

    function transfer(address to, uint256 amount, bytes memory callData, uint256 value, bytes memory data)
        external
        payable
        returns (MessagingReceipt memory);

    function cancelPendingTransfer() external;

    function onRead(bytes calldata _message) external;
}
