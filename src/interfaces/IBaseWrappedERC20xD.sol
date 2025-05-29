// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface IBaseWrappedERC20xD is IBaseERC20xD {
    function underlying() external view returns (address);
    function vault() external view returns (address);
    function failedRedemptions(uint256 id)
        external
        view
        returns (
            bool resolved,
            uint256 shares,
            bytes memory callbackData,
            bytes memory receivingData,
            uint128 receivingFee,
            uint256 redeemFee
        );

    function quoteUnwrap(address from, uint256 redeemFee, uint128 gasLimit) external view returns (uint256 fee);
    function quoteRedeem(
        address from,
        address to,
        uint256 shares,
        bytes memory receivingData,
        uint128 receivingFee,
        uint256 minAmount,
        uint128 gasLimit
    ) external view returns (uint256 fee);

    function updateVault(address _vault) external;

    function wrap(address to, uint256 amount, uint256 depositFee, bytes memory depositData)
        external
        payable
        returns (uint256 shares);

    function unwrap(
        address to,
        uint256 shares,
        bytes memory receivingData,
        uint128 receivingFee,
        bytes memory redeemData,
        uint256 redeemFee,
        bytes memory readData
    ) external payable returns (MessagingReceipt memory receipt);

    function redeemRestricted(
        uint256 shares,
        bytes memory callbackData,
        bytes memory receivingData,
        uint128 receivingFee,
        bytes memory redeemData,
        uint256 redeemFee
    ) external;

    function retryRedeem(uint256 id, bytes memory data) external payable;

    fallback() external payable;
    receive() external payable;
}
