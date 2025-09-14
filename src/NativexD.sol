// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xD } from "./mixins/BaseERC20xD.sol";
import { IBaseERC20xD } from "./interfaces/IBaseERC20xD.sol";
import { INativexD } from "./interfaces/INativexD.sol";
import { IERC20xDHook } from "./interfaces/IERC20xDHook.sol";
import { AddressLib } from "./libraries/AddressLib.sol";

/**
 * @title NativexD
 * @notice A cross-chain wrapped token implementation for native assets (e.g., ETH).
 * @dev This contract extends BaseERC20xD directly to enable wrapping and unwrapping of native tokens.
 *      All vault integration and redemption logic should be implemented via hooks.
 */
contract NativexD is BaseERC20xD, INativexD {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Constant representing the native asset (e.g., ETH). In this context, native is denoted by address(0).
    address public constant underlying = address(0);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the NativexD contract.
     * @param _name The name of the wrapped native token.
     * @param _symbol The symbol of the wrapped native token.
     * @param _decimals The number of decimals for the wrapped native token.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the Gateway contract.
     * @param _owner The address that will be granted ownership privileges.
     * @param _settler The address of the whitelisted settler for this token.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner,
        address _settler
    ) BaseERC20xD(_name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner, _settler) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc INativexD
    fallback() external payable virtual { }

    /// @inheritdoc INativexD
    receive() external payable virtual { }

    /// @inheritdoc INativexD
    function wrap(address to) external payable virtual nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (msg.value == 0) revert InvalidAmount();

        address _hook = hook;
        uint256 actualAmount = msg.value;

        if (_hook != address(0)) {
            // Call onWrap hook with native tokens attached to get actual amount to mint
            try IERC20xDHook(_hook).onWrap{ value: msg.value }(msg.sender, to, msg.value) returns (
                uint256 _actualAmount
            ) {
                actualAmount = _actualAmount;
            } catch (bytes memory reason) {
                emit OnWrapHookFailure(_hook, msg.sender, to, msg.value, reason);
                // Continue with original amount if hook fails
            }
        }
        // If no hook, native tokens stay in this contract

        // Mint wrapped tokens for the native value received
        _transferFrom(address(0), to, actualAmount);

        emit Wrap(to, actualAmount);
    }

    /// @inheritdoc INativexD
    function unwrap(address to, uint256 amount, bytes memory data)
        external
        payable
        virtual
        nonReentrant
        returns (bytes32 guid)
    {
        if (to == address(0)) revert InvalidAddress();

        // Encode the recipient address with the callData for the burn operation
        bytes memory callData = abi.encode(to);

        // The actual burn and native transfer will happen in _executePendingTransfer after cross-chain check
        guid = _transfer(msg.sender, address(0), amount, callData, 0, data);
    }

    /// @inheritdoc INativexD
    function quoteUnwrap(uint128 gasLimit) external view virtual returns (uint256) {
        // Unwrap requires cross-chain messaging for global availability check
        return quoteTransfer(msg.sender, gasLimit);
    }

    /**
     * @dev Override _executePendingTransfer to handle unwrap logic
     */
    function _executePendingTransfer(IBaseERC20xD.PendingTransfer memory pending) internal virtual override {
        // For burns (unwraps), handle the recipient from callData
        if (pending.to == address(0) && pending.callData.length > 0) {
            // Decode the recipient from callData
            address recipient = abi.decode(pending.callData, (address));

            // Perform the burn
            _transferFrom(pending.from, address(0), pending.amount, pending.data);

            // Handle native token transfer
            address _hook = hook;
            uint256 underlyingAmount = pending.amount;

            if (_hook != address(0)) {
                // Call onUnwrap hook to get actual amount of native tokens to return
                try IERC20xDHook(_hook).onUnwrap(pending.from, recipient, pending.amount) returns (
                    uint256 _underlyingAmount
                ) {
                    underlyingAmount = _underlyingAmount;
                    // Hook should have transferred the native tokens to this contract
                } catch (bytes memory reason) {
                    emit OnUnwrapHookFailure(_hook, pending.from, recipient, pending.amount, reason);
                    // Continue with original amount if hook fails
                }
            }

            // Send native tokens to the recipient
            AddressLib.transferNative(recipient, underlyingAmount);
            emit Unwrap(recipient, pending.amount, underlyingAmount);
        } else {
            // For normal transfers, use parent implementation
            super._executePendingTransfer(pending);
        }
    }
}
