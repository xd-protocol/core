// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BaseERC20xD } from "./mixins/BaseERC20xD.sol";
import { IBaseERC20xD } from "./interfaces/IBaseERC20xD.sol";
import { IWrappedERC20xD } from "./interfaces/IWrappedERC20xD.sol";
import { IERC20xDHook } from "./interfaces/IERC20xDHook.sol";

/**
 * @title WrappedERC20xD
 * @notice A cross-chain wrapped token implementation that allows wrapping and unwrapping of underlying ERC20 tokens.
 * @dev This contract extends BaseERC20xD to add wrapping and unwrapping capabilities.
 *      All vault integration and redemption logic should be implemented via hooks.
 */
contract WrappedERC20xD is BaseERC20xD, IWrappedERC20xD {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable underlying;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the WrappedERC20xD with the underlying token and token parameters.
     * @param _underlying The address of the underlying token to wrap.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the Gateway contract.
     * @param _owner The owner of the contract.
     * @param _settler The address of the whitelisted settler for this token.
     */
    constructor(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner,
        address _settler
    ) BaseERC20xD(_name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner, _settler) {
        underlying = _underlying;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IWrappedERC20xD
    fallback() external payable virtual { }

    /// @inheritdoc IWrappedERC20xD
    receive() external payable virtual { }

    /// @inheritdoc IWrappedERC20xD
    function wrap(address to, uint256 amount) external payable virtual nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        // Always transfer underlying tokens to this contract first
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        address _hook = hook;
        uint256 actualAmount = amount;

        if (_hook != address(0)) {
            // Approve the hook to pull the tokens
            ERC20(underlying).approve(_hook, amount);

            // Call onWrap hook - hook should pull tokens using transferFrom
            try IERC20xDHook(_hook).onWrap(msg.sender, to, amount) returns (uint256 _actualAmount) {
                actualAmount = _actualAmount;
            } catch (bytes memory reason) {
                emit OnWrapHookFailure(_hook, msg.sender, to, amount, reason);
                // Continue with original amount if hook fails
            }

            // Clear any remaining allowance
            ERC20(underlying).approve(_hook, 0);
        }

        // Mint wrapped tokens
        _transferFrom(address(0), to, actualAmount);

        emit Wrap(to, actualAmount);
    }

    /// @inheritdoc IWrappedERC20xD
    function unwrap(address to, uint256 amount, bytes memory data)
        external
        payable
        virtual
        nonReentrant
        returns (bytes32 guid)
    {
        if (to == address(0)) revert InvalidAddress();

        // Encode the recipient address with the callData for the burn operation
        // This will be available in _transferFrom via pending.callData
        bytes memory callData = abi.encode(to);

        // The actual burn and underlying transfer will happen in _transferFrom after cross-chain check
        guid = _transfer(msg.sender, address(0), amount, callData, 0, data);
    }

    /// @inheritdoc IWrappedERC20xD
    function quoteUnwrap(uint128 gasLimit) external view virtual returns (uint256) {
        // Unwrap requires cross-chain messaging for global availability check
        return this.quoteTransfer(msg.sender, gasLimit);
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

            // Handle underlying token transfer
            address _hook = hook;
            uint256 underlyingAmount = pending.amount;

            if (_hook != address(0)) {
                // Call onUnwrap hook to get actual amount of underlying to return
                try IERC20xDHook(_hook).onUnwrap(pending.from, recipient, pending.amount) returns (
                    uint256 _underlyingAmount
                ) {
                    underlyingAmount = _underlyingAmount;
                    // Hook should have transferred the underlying tokens to this contract
                } catch (bytes memory reason) {
                    emit OnUnwrapHookFailure(_hook, pending.from, recipient, pending.amount, reason);
                    // Continue with original amount if hook fails
                }
            }

            // Transfer underlying tokens to the recipient
            ERC20(underlying).safeTransfer(recipient, underlyingAmount);
            emit Unwrap(recipient, pending.amount, underlyingAmount);
        } else {
            // For normal transfers, use parent implementation
            super._executePendingTransfer(pending);
        }
    }
}
