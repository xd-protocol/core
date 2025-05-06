// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xDWrapper } from "./mixins/BaseERC20xDWrapper.sol";
import { IStakingVault, IStakingVaultNativeCallbacks } from "./interfaces/IStakingVault.sol";
import { AddressLib } from "./libraries/AddressLib.sol";

/**
 * @title xDNative
 * @notice A native token wrapper that extends cross-chain functionality for an underlying native asset.
 *         This contract builds upon BaseERC20xDWrapper to enable wrapping and unwrapping operations for the
 *         native cryptocurrency (e.g., ETH), interacting with a staking vault that supports native token
 *         deposits and withdrawals.
 * @dev Outgoing operations (wrap) are performed by invoking _deposit() to deposit native tokens into the vault,
 *      while outgoing unwrapping (withdraw) operations are executed via _withdraw(). The contract also implements
 *      the IStakingVaultNativeCallbacks interface to handle incoming cross-chain messages confirming withdrawals.
 */
contract xDNative is BaseERC20xDWrapper, IStakingVaultNativeCallbacks {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Constant representing the native asset (e.g., ETH). In this context, native is denoted by address(0).
    address public constant NATIVE = address(0);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the xDNative contract.
     * @dev Forwards parameters to the BaseERC20xDWrapper constructor using NATIVE as the underlying asset.
     * @param _timeLockPeriod The timelock period used for configuration updates.
     * @param _vault The vault contract's address.
     * @param _name The name of the wrapped native token.
     * @param _symbol The symbol of the wrapped native token.
     * @param _decimals The number of decimals for the wrapped native token.
     * @param _liquidityMatrix The address of the liquidityMatrix contract.
     * @param _owner The address that will be granted ownership privileges.
     */
    constructor(
        uint64 _timeLockPeriod,
        address _vault,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _owner
    ) BaseERC20xDWrapper(NATIVE, _timeLockPeriod, _vault, _name, _symbol, _decimals, _liquidityMatrix, _owner) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Executes a deposit (wrap) operation for the native asset.
     * @dev Checks that the provided fee is at least the amount to be wrapped.
     *      Then it calls the depositNative function on the vault with the provided fee.
     *      This function represents an outgoing operation that wraps native tokens.
     * @param amount The amount of native tokens to deposit.
     * @param minAmount The minimum amount expected to be deposited.
     * @param fee The fee to forward with the deposit call.
     * @param options Additional options to pass to the vault's deposit function.
     */
    function _deposit(uint256 amount, uint256 minAmount, uint256 fee, bytes memory options) internal override {
        if (fee < amount) revert InsufficientValue();

        IStakingVault(vault).depositNative{ value: fee }(amount, minAmount, options);
    }

    /**
     * @notice Executes a withdrawal (unwrap) operation for the native asset.
     * @dev Initiates an outgoing withdrawal request by calling the vault's withdrawNative function.
     *      If the withdrawal call fails, the failure is recorded via _onFailedWithdrawal.
     * @param amount The amount of native tokens to withdraw.
     * @param minAmount The minimum amount expected to be received.
     * @param incomingData Encoded data for processing the incoming cross-chain withdrawal message.
     * @param incomingFee The fee for processing the incoming withdrawal message.
     * @param incomingOptions Options associated with the incoming withdrawal message.
     * @param fee The fee to be forwarded with the withdrawal call.
     * @param options Additional options to pass to the vault's withdrawal function.
     */
    function _withdraw(
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes memory incomingOptions,
        uint256 fee,
        bytes memory options
    ) internal virtual override {
        try IStakingVault(vault).withdrawNative{ value: fee }(
            amount, minAmount, incomingData, incomingFee, incomingOptions, options
        ) { } catch (bytes memory reason) {
            _onFailedWithdrawal(amount, minAmount, incomingData, incomingFee, incomingOptions, fee, reason);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    IStakingVaultNativeCallbacks
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Callback function invoked by the vault when a native withdrawal is executed.
     * @dev This function handles the incoming cross-chain message (incoming operation) confirming a withdrawal.
     *      It verifies that the caller is the vault, decodes the original sender and recipient addresses,
     *      updates internal accounting via _transferFrom, and transfers the withdrawn native tokens to the recipient.
     * @param data Encoded data containing the original sender and recipient addresses.
     */
    function onWithdrawNative(bytes calldata data) external payable nonReentrant {
        if (msg.sender != vault) revert Forbidden();

        (address from, address to) = abi.decode(data, (address, address));
        _transferFrom(from, address(0), msg.value);

        AddressLib.transferNative(to, msg.value);
    }
}
