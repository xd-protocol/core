// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { AddressLib } from "src/libraries/AddressLib.sol";
import { IStakingVault, IStakingVaultCallbacks, IStakingVaultNativeCallbacks } from "src/interfaces/IStakingVault.sol";
import { IStakingVaultQuotable } from "src/interfaces/IStakingVaultQuotable.sol";

contract StakingVaultMock is IStakingVaultQuotable {
    using SafeTransferLib for ERC20;

    address public constant NATIVE = address(0);

    mapping(address asset => mapping(address owner => uint256)) public sharesOf;

    function quoteDeposit(address, uint256 amount, uint128 gasLimit)
        public
        pure
        returns (uint256 minAmount, uint256 fee)
    {
        minAmount = amount * 99 / 100;
        fee = gasLimit * 1e9;
    }

    function quoteDepositNative(uint256 amount, uint128 gasLimit)
        public
        pure
        returns (uint256 minAmount, uint256 fee)
    {
        minAmount = amount * 99 / 100;
        fee = gasLimit * 1e9;
    }

    function quoteRedeem(
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata,
        uint128 receivingFee,
        uint256,
        uint128 gasLimit
    ) public pure returns (uint256 fee) {
        fee = receivingFee + gasLimit * 1e9;
    }

    function quoteRedeemNative(
        address,
        uint256,
        bytes calldata,
        bytes calldata,
        uint128 receivingFee,
        uint256,
        uint128 gasLimit
    ) public pure returns (uint256 fee) {
        fee = receivingFee + gasLimit * 1e9;
    }

    function quoteSendToken(address, uint256 amount, bytes calldata, uint128 gasLimit)
        external
        pure
        returns (uint256 minAmount, uint256 fee)
    {
        minAmount = amount * 99 / 100;
        fee = gasLimit * 1e9;
    }

    function quoteSendTokenNative(uint256 amount, bytes calldata, uint128 gasLimit)
        external
        pure
        returns (uint256 minAmount, uint256 fee)
    {
        minAmount = amount * 99 / 100;
        fee = gasLimit * 1e9;
    }

    function deposit(address asset, address to, uint256 amount, bytes calldata data)
        external
        payable
        returns (uint256 shares)
    {
        (uint256 minAmount, uint128 gasLimit,) = abi.decode(data, (uint256, uint128, address));
        (, uint256 fee) = quoteDeposit(asset, amount, gasLimit);
        if (msg.value < fee) revert("INSUFFICIENT_FEE");

        shares = minAmount;
        sharesOf[asset][to] += shares;

        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function depositNative(address to, uint256 amount, bytes calldata data) external payable returns (uint256 shares) {
        (uint256 minAmount, uint128 gasLimit,) = abi.decode(data, (uint256, uint128, address));
        (, uint256 fee) = quoteDepositNative(amount, gasLimit);
        if (msg.value < amount + fee) revert("INSUFFICIENT_FEE");

        shares = minAmount;
        sharesOf[NATIVE][to] += shares;
    }

    function redeem(
        address asset,
        address to,
        uint256 shares,
        bytes calldata callbackData,
        bytes calldata receivingData,
        uint128 receivingFee,
        bytes calldata data
    ) external payable {
        (uint256 minAmount, uint128 gasLimit,) = abi.decode(data, (uint256, uint128, address));
        uint256 fee = quoteRedeem(asset, to, shares, callbackData, receivingData, receivingFee, minAmount, gasLimit);
        if (msg.value < fee) revert("INSUFFICIENT_FEE");
        if (shares > sharesOf[asset][msg.sender]) revert("INSUFFICIENT_SHARES");

        ERC20(asset).safeApprove(to, 0);
        ERC20(asset).safeApprove(to, minAmount);
        try IStakingVaultCallbacks(to).onRedeem(asset, shares, minAmount, callbackData) { }
        catch {
            ERC20(asset).safeTransfer(to, minAmount);
        }
    }

    function redeemNative(
        address to,
        uint256 shares,
        bytes calldata callbackData,
        bytes calldata receivingData,
        uint128 receivingFee,
        bytes calldata data
    ) external payable {
        (uint256 minAmount, uint128 gasLimit,) = abi.decode(data, (uint256, uint128, address));
        uint256 fee = quoteRedeemNative(to, shares, callbackData, receivingData, receivingFee, minAmount, gasLimit);
        if (msg.value < fee) revert("INSUFFICIENT_FEE");
        if (shares > sharesOf[NATIVE][msg.sender]) revert("INSUFFICIENT_SHARES");

        try IStakingVaultNativeCallbacks(to).onRedeemNative{ value: minAmount }(shares, callbackData) { }
        catch {
            AddressLib.transferNative(to, minAmount);
        }
    }
}
