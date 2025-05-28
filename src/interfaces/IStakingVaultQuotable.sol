// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IStakingVault } from "./IStakingVault.sol";

interface IStakingVaultQuotable is IStakingVault {
    function quoteDeposit(address asset, uint256 amount, uint128 gasLimit)
        external
        view
        returns (uint256 minAmount, uint256 fee);

    function quoteDepositNative(uint256 amount, uint128 gasLimit)
        external
        view
        returns (uint256 minAmount, uint256 fee);

    function quoteRedeem(
        address asset,
        address to,
        uint256 shares,
        bytes calldata callbackData,
        bytes calldata receivingData,
        uint128 receivingFee,
        uint256 minAmount,
        uint128 gasLimit
    ) external view returns (uint256 fee);

    function quoteRedeemNative(
        address to,
        uint256 shares,
        bytes calldata callbackData,
        bytes calldata receivingData,
        uint128 receivingFee,
        uint256 minAmount,
        uint128 gasLimit
    ) external view returns (uint256 fee);

    function quoteSendToken(address asset, uint256 shares, bytes calldata callbackData, uint128 gasLimit)
        external
        view
        returns (uint256 minAmount, uint256 fee);

    function quoteSendTokenNative(uint256 shares, bytes calldata callbackData, uint128 gasLimit)
        external
        view
        returns (uint256 minAmount, uint256 fee);
}
