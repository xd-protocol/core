// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xD } from "./mixins/BaseERC20xD.sol";
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

        // Pass recipient address in callData for hooks to use
        // The actual burn and native transfer will happen in _transferFrom after cross-chain check
        guid = _transfer(msg.sender, address(0), amount, abi.encode(to), 0, data);
    }

    /// @inheritdoc INativexD
    function quoteUnwrap(uint128 gasLimit) external view virtual returns (uint256) {
        // Unwrap requires cross-chain messaging for global availability check
        return quoteTransfer(msg.sender, gasLimit);
    }

    /**
     * @dev Override _transferFrom to handle unwrap logic when burning tokens
     */
    function _transferFrom(address from, address to, uint256 amount, bytes memory data) internal virtual override {
        // Call parent implementation first to handle the burn
        super._transferFrom(from, to, amount, data);

        // If this is a burn (unwrap), handle native token transfer
        if (to == address(0) && from != address(0)) {
            // Decode the recipient address from data (passed from unwrap function)
            address recipient = abi.decode(data, (address));
            if (recipient == address(0)) revert InvalidAddress();

            address _hook = hook;
            uint256 underlyingAmount = amount;

            if (_hook != address(0)) {
                // Call onUnwrap hook to get actual amount of native tokens to return
                try IERC20xDHook(_hook).onUnwrap(from, recipient, amount) returns (uint256 _underlyingAmount) {
                    underlyingAmount = _underlyingAmount;
                    // Hook should have transferred the native tokens to this contract
                } catch (bytes memory reason) {
                    emit OnUnwrapHookFailure(_hook, from, recipient, amount, reason);
                    // Continue with original amount if hook fails
                }
            }

            // Send native tokens to the recipient
            AddressLib.transferNative(recipient, underlyingAmount);
            emit Unwrap(recipient, amount, underlyingAmount);
        }
    }
}
