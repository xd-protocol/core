// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BaseERC20xDWrapper } from "./mixins/BaseERC20xDWrapper.sol";
import { IStakingVault, IStakingVaultCallbacks } from "./interfaces/IStakingVault.sol";
import { IStakingVaultQuotable } from "./interfaces/IStakingVaultQuotable.sol";

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
     * @param _vault The vault contract's address.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the ERC20xDGateway contract.
     * @param _owner The owner of this contract.
     */
    constructor(
        address _underlying,
        address _vault,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner
    ) BaseERC20xDWrapper(_underlying, _vault, _name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner) { }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function quoteRedeem(
        address from,
        address to,
        uint256 shares,
        bytes memory receivingData,
        uint128 receivingFee,
        uint256 minAmount,
        uint128 gasLimit
    ) public view override returns (uint256 fee) {
        return IStakingVaultQuotable(vault).quoteRedeem(
            underlying, to, shares, abi.encode(from, to), receivingData, receivingFee, minAmount, gasLimit
        );
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles the deposit (wrap) operation by transferring underlying tokens to the contract,
     *         approving the vault to spend them, and initiating a deposit in the vault.
     * @dev After the deposit is initiated with the vault, the approval is reset to zero.
     *      This function represents an outgoing operation that wraps tokens.
     * @param amount The amount of tokens to deposit.
     * @param fee The fee to be forwarded with the deposit call.
     * @param data Additional data to be forwarded to the vault deposit function.
     */
    function _deposit(uint256 amount, uint256 fee, bytes memory data) internal override returns (uint256 shares) {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        ERC20(underlying).safeApprove(vault, 0);
        ERC20(underlying).safeApprove(vault, amount);
        return IStakingVault(vault).deposit{ value: fee }(underlying, address(this), amount, data);
    }

    function _redeem(
        uint256 shares,
        bytes memory callbackData,
        bytes memory receivingData,
        uint128 receivingFee,
        bytes memory redeemData,
        uint256 redeemFee
    ) internal override {
        IStakingVault(vault).redeem{ value: redeemFee }(
            underlying, address(this), shares, callbackData, receivingData, receivingFee, redeemData
        );
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
