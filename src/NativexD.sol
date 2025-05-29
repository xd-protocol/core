// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseWrappedERC20xD } from "./mixins/BaseWrappedERC20xD.sol";
import { INativexD } from "./interfaces/INativexD.sol";
import { IBaseWrappedERC20xD } from "./interfaces/IBaseWrappedERC20xD.sol";
import { IStakingVault, IStakingVaultNativeCallbacks } from "./interfaces/IStakingVault.sol";
import { IStakingVaultQuotable } from "./interfaces/IStakingVaultQuotable.sol";
import { AddressLib } from "./libraries/AddressLib.sol";

/**
 * @title NativexD
 * @notice A native token wrapper that extends cross-chain functionality for an underlying native asset.
 *         This contract builds upon BaseWrappedERC20xD to enable wrapping and unwrapping operations for the
 *         native cryptocurrency (e.g., ETH), interacting with a staking vault that supports native token
 *         deposits and redemptions.
 * @dev Outgoing operations (wrap) are performed by invoking _deposit() to deposit native tokens into the vault,
 *      while outgoing unwrapping (redeem) operations are executed via _redeem(). The contract also implements
 *      the IStakingVaultNativeCallbacks interface to handle incoming cross-chain messages confirming redemptions.
 */
contract NativexD is BaseWrappedERC20xD, INativexD {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Constant representing the native asset (e.g., ETH). In this context, native is denoted by address(0).
    address internal constant NATIVE = address(0);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the NativexD contract.
     * @dev Forwards parameters to the BaseWrappedERC20xD constructor using NATIVE as the underlying asset.
     * @param _vault The vault contract's address.
     * @param _name The name of the wrapped native token.
     * @param _symbol The symbol of the wrapped native token.
     * @param _decimals The number of decimals for the wrapped native token.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the ERC20xDGateway contract.
     * @param _owner The address that will be granted ownership privileges.
     */
    constructor(
        address _vault,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner
    ) BaseWrappedERC20xD(NATIVE, _vault, _name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner) { }

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
    ) public view override(BaseWrappedERC20xD, IBaseWrappedERC20xD) returns (uint256 fee) {
        return IStakingVaultQuotable(vault).quoteRedeemNative(
            to, shares, abi.encode(from, to), receivingData, receivingFee, minAmount, gasLimit
        );
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Executes a deposit (wrap) operation for the native asset.
     * @dev Checks that the provided fee is at least the amount to be wrapped.
     *      Then it calls the depositNative function on the vault with the provided fee.
     *      This function represents an outgoing operation that wraps native tokens.
     * @param amount The amount of native tokens to deposit.
     * @param fee The fee to forward with the deposit call.
     * @param data Additional data to pass to the vault's deposit function.
     */
    function _deposit(uint256 amount, uint256 fee, bytes memory data) internal override returns (uint256 shares) {
        if (msg.value < amount + fee) revert InsufficientValue();

        return IStakingVault(vault).depositNative{ value: amount + fee }(address(this), amount, data);
    }

    function _redeem(
        uint256 shares,
        bytes memory callbackData,
        bytes memory receivingData,
        uint128 receivingFee,
        bytes memory redeemData,
        uint256 redeemFee
    ) internal override {
        IStakingVault(vault).redeemNative{ value: redeemFee }(
            address(this), shares, callbackData, receivingData, receivingFee, redeemData
        );
    }

    /*//////////////////////////////////////////////////////////////
                    IStakingVaultNativeCallbacks
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Callback function invoked by the vault when a native redemption is executed.
     * @dev This function handles the incoming cross-chain message (incoming operation) confirming a redemption.
     *      It verifies that the caller is the vault, decodes the original sender and recipient addresses,
     *      updates internal accounting via _transferFrom, and transfers the redeemed native tokens to the recipient.
     * @param data Encoded data containing the original sender and recipient addresses.
     */
    function onRedeemNative(uint256 shares, bytes calldata data) external payable {
        if (msg.sender != vault) revert Forbidden();

        (address from, address to) = abi.decode(data, (address, address));
        _transferFrom(from, address(0), shares);

        AddressLib.transferNative(to, msg.value);
    }
}
