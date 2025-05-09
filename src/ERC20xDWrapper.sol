// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BaseERC20xDWrapper } from "./mixins/BaseERC20xDWrapper.sol";
import { IStakingVault, IStakingVaultCallbacks } from "./interfaces/IStakingVault.sol";

/**
 * @title ERC20xDWrapper
 * @notice Implements cross-chain wrapping and unwrapping for an underlying ERC20 token.
 *         This contract extends BaseERC20xDWrapper to provide wrapper-specific logic and integrates
 *         with a staking vault to perform deposit and redemption operations.
 * @dev Outgoing operations (wrap) call _deposit() to transfer tokens to the vault,
 *      while incoming operations (unwrap) call _redeem() to trigger a vault redemption.
 *      The onRedeem() callback finalizes redemptions by transferring tokens to the recipient.
 */
contract ERC20xDWrapper is BaseERC20xDWrapper, IStakingVaultCallbacks {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the ERC20xDWrapper contract.
     * @dev Forwards the provided parameters to the BaseERC20xDWrapper constructor.
     * @param _underlying The address of the underlying token.
     * @param _timeLockPeriod The timelock period for configuration updates.
     * @param _vault The vault contract's address.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _liquidityMatrix The address of the liquidityMatrix contract.
     * @param _owner The owner of this contract.
     */
    constructor(
        address _underlying,
        uint64 _timeLockPeriod,
        address _vault,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _owner
    ) BaseERC20xDWrapper(_underlying, _timeLockPeriod, _vault, _name, _symbol, _decimals, _liquidityMatrix, _owner) { }

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
    function _deposit(uint256 amount, uint256 minAmount, uint256 fee, bytes memory options)
        internal
        override
        returns (uint256 shares)
    {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        ERC20(underlying).safeApprove(vault, 0);
        ERC20(underlying).safeApprove(vault, amount);
        return IStakingVault(vault).deposit{ value: fee }(underlying, address(this), amount, minAmount, options);
    }

    /**
     * @notice Handles the redemption (unwrap) operation by invoking the vault's redemption function.
     * @dev This function attempts to redeem tokens from the vault. If the redemption fails,
     *      it triggers a failure handler to record the failed redemption details.
     *      This represents an outgoing message to request tokens be unwrapped.
     * @param amount The amount of tokens to redeem.
     * @param minAmount The minimum amount expected from the redemption.
     * @param incomingData Encoded data for the incoming cross-chain redemption message.
     * @param incomingFee The fee associated with the incoming redemption message.
     * @param incomingOptions Options for handling the incoming message.
     * @param fee The fee to be forwarded for the redemption call.
     * @param options Additional options to be passed to the vault redemption function.
     */
    function _redeem(
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes memory incomingOptions,
        uint256 fee,
        bytes memory options
    ) internal virtual override {
        try IStakingVault(vault).redeem{ value: fee }(
            underlying, address(this), amount, minAmount, incomingData, incomingFee, incomingOptions, options
        ) { } catch (bytes memory reason) {
            _onFailedRedemption(amount, minAmount, incomingData, incomingFee, incomingOptions, fee, reason);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        IStakingVaultCallbacks
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Callback function invoked by the vault when a redemption is executed.
     * @dev This function is called as part of the incoming cross-chain message that finalizes
     *      a redemption. It verifies the caller, decodes the sender and recipient, updates balances,
     *      and transfers the underlying tokens to the recipient.
     * @param amount The amount of tokens that have been redeemed.
     * @param data Encoded data containing the original sender and recipient addresses.
     */
    function onRedeem(address, uint256 shares, uint256 amount, bytes calldata data) external {
        if (msg.sender != vault) revert Forbidden();

        (address from, address to) = abi.decode(data, (address, address));
        _transferFrom(from, address(0), shares);

        ERC20(underlying).safeTransferFrom(msg.sender, to, amount);
    }
}
