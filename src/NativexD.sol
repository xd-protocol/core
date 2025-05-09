// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xDWrapper } from "./mixins/BaseERC20xDWrapper.sol";
import { IStakingVault, IStakingVaultNativeCallbacks } from "./interfaces/IStakingVault.sol";
import { AddressLib } from "./libraries/AddressLib.sol";

/**
 * @title NativexD
 * @notice A native token wrapper that extends cross-chain functionality for an underlying native asset.
 *         This contract builds upon BaseERC20xDWrapper to enable wrapping and unwrapping operations for the
 *         native cryptocurrency (e.g., ETH), interacting with a staking vault that supports native token
 *         deposits and redemptions.
 * @dev Outgoing operations (wrap) are performed by invoking _deposit() to deposit native tokens into the vault,
 *      while outgoing unwrapping (redeem) operations are executed via _redeem(). The contract also implements
 *      the IStakingVaultNativeCallbacks interface to handle incoming cross-chain messages confirming redemptions.
 */
contract NativexD is BaseERC20xDWrapper, IStakingVaultNativeCallbacks {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Constant representing the native asset (e.g., ETH). In this context, native is denoted by address(0).
    address public constant NATIVE = address(0);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the NativexD contract.
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
    function _deposit(uint256 amount, uint256 minAmount, uint256 fee, bytes memory options)
        internal
        override
        returns (uint256 dstAmount)
    {
        if (fee < amount) revert InsufficientValue();

        return IStakingVault(vault).depositNative{ value: fee }(address(this), amount, minAmount, options);
    }

    /**
     * @notice Executes a redemption (unwrap) operation for the native asset.
     * @dev Initiates an outgoing redemption request by calling the vault's redeemNative function.
     *      If the redemption call fails, the failure is recorded via _onFailedRedemption.
     * @param amount The amount of native tokens to redeem.
     * @param minAmount The minimum amount expected to be received.
     * @param incomingData Encoded data for processing the incoming cross-chain redemption message.
     * @param incomingFee The fee for processing the incoming redemption message.
     * @param incomingOptions Options associated with the incoming redemption message.
     * @param fee The fee to be forwarded with the redemption call.
     * @param options Additional options to pass to the vault's redemption function.
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
        try IStakingVault(vault).redeemNative{ value: fee }(
            address(this), amount, minAmount, incomingData, incomingFee, incomingOptions, options
        ) { } catch (bytes memory reason) {
            _onFailedRedemption(amount, minAmount, incomingData, incomingFee, incomingOptions, fee, reason);
        }
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
    function onRedeemNative(uint256 shares, bytes calldata data) external payable nonReentrant {
        if (msg.sender != vault) revert Forbidden();

        (address from, address to) = abi.decode(data, (address, address));
        _transferFrom(from, address(0), shares);

        AddressLib.transferNative(to, msg.value);
    }
}
