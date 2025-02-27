// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BasexDERC20Wrapper } from "./mixins/BasexDERC20Wrapper.sol";
import { IStakingVault, IStakingVaultCallbacks } from "./interfaces/IStakingVault.sol";

/**
 * @title xDERC20Wrapper
 * @notice Implements cross-chain wrapping and unwrapping for an underlying ERC20 token.
 *         This contract extends BasexDERC20Wrapper to provide wrapper-specific logic and integrates
 *         with a staking vault to perform deposit and withdrawal operations.
 * @dev Outgoing operations (wrap) call _deposit() to transfer tokens to the vault,
 *      while incoming operations (unwrap) call _withdraw() to trigger a vault withdrawal.
 *      The onWithdraw() callback finalizes withdrawals by transferring tokens to the recipient.
 */
contract xDERC20Wrapper is BasexDERC20Wrapper, IStakingVaultCallbacks {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the xDERC20Wrapper contract.
     * @dev Forwards the provided parameters to the BasexDERC20Wrapper constructor.
     * @param _underlying The address of the underlying token.
     * @param _timeLockPeriod The timelock period for configuration updates.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _synchronizer The address of the synchronizer contract.
     * @param _owner The owner of this contract.
     */
    constructor(
        address _underlying,
        uint64 _timeLockPeriod,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _synchronizer,
        address _owner
    ) BasexDERC20Wrapper(_underlying, _timeLockPeriod, _name, _symbol, _decimals, _synchronizer, _owner) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles the deposit (wrap) operation by transferring underlying tokens to the contract,
     *         approving the vault to spend them, and initiating a deposit in the vault.
     * @dev After the deposit is initiated with the vault, the approval is reset to zero.
     *      This function represents an outgoing operation that wraps tokens.
     * @param amount The amount of tokens to deposit.
     * @param minAmount The minimum amount acceptable for deposit.
     * @param fee The fee to be forwarded with the deposit call.
     * @param options Additional options to be forwarded to the vault deposit function.
     */
    function _deposit(uint256 amount, uint256 minAmount, uint256 fee, bytes memory options) internal override {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        ERC20(underlying).safeApprove(vault, 0);
        ERC20(underlying).safeApprove(vault, amount);
        IStakingVault(vault).deposit{ value: fee }(underlying, amount, minAmount, options);
    }

    /**
     * @notice Handles the withdrawal (unwrap) operation by invoking the vault's withdrawal function.
     * @dev This function attempts to withdraw tokens from the vault. If the withdrawal fails,
     *      it triggers a failure handler to record the failed withdrawal details.
     *      This represents an outgoing message to request tokens be unwrapped.
     * @param amount The amount of tokens to withdraw.
     * @param minAmount The minimum amount expected from the withdrawal.
     * @param incomingData Encoded data for the incoming cross-chain withdrawal message.
     * @param incomingFee The fee associated with the incoming withdrawal message.
     * @param incomingOptions Options for handling the incoming message.
     * @param fee The fee to be forwarded for the withdrawal call.
     * @param options Additional options to be passed to the vault withdrawal function.
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
        try IStakingVault(vault).withdraw{ value: fee }(
            underlying, amount, minAmount, incomingData, incomingFee, incomingOptions, options
        ) { } catch (bytes memory reason) {
            _onFailedWithdrawal(amount, minAmount, incomingData, incomingFee, incomingOptions, fee, reason);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        IStakingVaultCallbacks
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Callback function invoked by the vault when a withdrawal is executed.
     * @dev This function is called as part of the incoming cross-chain message that finalizes
     *      a withdrawal. It verifies the caller, decodes the sender and recipient, updates balances,
     *      and transfers the underlying tokens to the recipient.
     * @param amount The amount of tokens that have been withdrawn.
     * @param data Encoded data containing the original sender and recipient addresses.
     */
    function onWithdraw(address, uint256 amount, bytes calldata data) external nonReentrant {
        if (msg.sender != vault) revert Forbidden();

        (address from, address to) = abi.decode(data, (address, address));
        _transferFrom(from, address(0), amount);

        ERC20(underlying).safeTransferFrom(msg.sender, to, amount);
    }
}
