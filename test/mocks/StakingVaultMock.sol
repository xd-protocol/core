// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { AddressLib } from "src/libraries/AddressLib.sol";
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

    function quoteRedeem(address, address, uint256, uint256, bytes memory, uint128, bytes memory, uint128 gasLimit)
        public
        pure
        returns (uint256 fee)
    {
        fee = gasLimit * 1e9;
    }

    function quoteRedeemNative(
        address,
        uint256,
        uint256,
        bytes memory,
        uint128 incomingFee,
        bytes memory,
        uint128 gasLimit
    ) public pure returns (uint256 fee) {
        fee = incomingFee + gasLimit * 1e9;
    }

    function deposit(address asset, address to, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        returns (uint256 shares)
    {
        (uint128 gasLimit,) = abi.decode(options, (uint128, address));
        (, uint256 fee) = quoteDeposit(asset, amount, gasLimit);
        if (msg.value < fee) revert("INSUFFICIENT_FEE");

        shares = minAmount;
        sharesOf[to] += shares;

        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function depositNative(address to, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        returns (uint256 shares)
    {
        (uint128 gasLimit,) = abi.decode(options, (uint128, address));
        (, uint256 fee) = quoteDepositNative(amount, gasLimit);
        if (msg.value < amount + fee) revert("INSUFFICIENT_FEE");

        shares = minAmount;
        sharesOf[to] += shares;
    }

    function redeem(
        address asset,
        address to,
        uint256 shares,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes calldata incomingOptions,
        bytes calldata options
    ) external payable {
        (uint128 gasLimit,) = abi.decode(options, (uint128, address));
        uint256 fee = quoteRedeem(asset, to, shares, minAmount, incomingData, incomingFee, incomingOptions, gasLimit);
        if (msg.value < fee) revert("INSUFFICIENT_FEE");
        if (shares > sharesOf[msg.sender]) revert("INSUFFICIENT_SHARES");

        ERC20(asset).safeApprove(to, 0);
        ERC20(asset).safeApprove(to, minAmount);
        try IStakingVaultCallbacks(to).onRedeem(asset, shares, minAmount, incomingData) { }
        catch {
            ERC20(asset).safeTransfer(to, minAmount);
        }
    }

    function redeemNative(
        address to,
        uint256 shares,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes calldata incomingOptions,
        bytes calldata options
    ) external payable {
        (uint128 gasLimit,) = abi.decode(options, (uint128, address));
        uint256 fee = quoteRedeemNative(to, shares, minAmount, incomingData, incomingFee, incomingOptions, gasLimit);
        if (msg.value < fee) revert("INSUFFICIENT_FEE");
        if (shares > sharesOf[msg.sender]) revert("INSUFFICIENT_SHARES");

        try IStakingVaultNativeCallbacks(to).onRedeemNative{ value: minAmount }(shares, incomingData) { }
        catch {
            AddressLib.transferNative(to, minAmount);
        }
    }
}
