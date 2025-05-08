// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { AddressLib } from "src/libraries/AddressLib.sol";
import { LzLib } from "src/libraries/LzLib.sol";
import { IStakingVault, IStakingVaultCallbacks, IStakingVaultNativeCallbacks } from "src/interfaces/IStakingVault.sol";

contract StakingVaultMock is IStakingVault {
    using SafeTransferLib for ERC20;

    mapping(address => uint256) public sharesOf;

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

    function quoteWithdraw(address, address, uint256, uint256, bytes memory, uint128, bytes memory, uint128 gasLimit)
        public
        pure
        returns (uint256 fee)
    {
        fee = gasLimit * 1e9;
    }

    function quoteWithdrawNative(address, uint256, uint256, bytes memory, uint128, bytes memory, uint128 gasLimit)
        public
        pure
        returns (uint256 fee)
    {
        fee = gasLimit * 1e9;
    }

    function deposit(address asset, address, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        returns (uint256 dstAmount)
    {
        (uint128 gasLimit,) = LzLib.decodeOptions(options);
        (, uint256 fee) = quoteDeposit(asset, amount, gasLimit);
        if (msg.value < fee) revert("INSUFFICIENT_FEE");

        dstAmount = minAmount;
        sharesOf[msg.sender] += dstAmount;

        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function depositNative(address, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        returns (uint256 dstAmount)
    {
        (uint128 gasLimit,) = LzLib.decodeOptions(options);
        (, uint256 fee) = quoteDepositNative(amount, gasLimit);
        if (msg.value < amount + fee) revert("INSUFFICIENT_FEE");

        dstAmount = minAmount;
        sharesOf[msg.sender] += dstAmount;

        if (msg.value < amount) revert("INSUFFICIENT_VALUE");
    }

    function withdraw(
        address asset,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes calldata incomingOptions,
        bytes calldata options
    ) external payable {
        (uint128 gasLimit,) = LzLib.decodeOptions(options);
        uint256 fee = quoteWithdraw(asset, to, amount, minAmount, incomingData, incomingFee, incomingOptions, gasLimit);
        if (msg.value < amount + fee) revert("INSUFFICIENT_FEE");

        if (amount > sharesOf[msg.sender]) revert("INSUFFICIENT_SHARES");

        ERC20(asset).safeApprove(to, 0);
        ERC20(asset).safeApprove(to, minAmount);
        try IStakingVaultCallbacks(to).onWithdraw(asset, minAmount, incomingData) { }
        catch {
            ERC20(asset).safeTransfer(to, minAmount);
        }
    }

    function withdrawNative(
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128,
        bytes calldata,
        bytes calldata
    ) external payable {
        if (amount > sharesOf[msg.sender]) revert("INSUFFICIENT_SHARES");

        try IStakingVaultNativeCallbacks(to).onWithdrawNative{ value: minAmount }(incomingData) { }
        catch {
            AddressLib.transferNative(to, minAmount);
        }
    }
}
