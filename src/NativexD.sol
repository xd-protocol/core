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

    /// @notice Maximum amount of native tokens that can be wrapped per account (0 = unlimited)
    uint256 public liquidityCap;

    /// @notice Tracks the amount of native tokens wrapped by each account
    mapping(address => uint256) public wrappedAmount;

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

    // Override receive to resolve multiple inheritance
    receive() external payable virtual override(BaseERC20xD, INativexD) {
        _recoverableETH += msg.value;
    }

    /// @inheritdoc INativexD
    function wrap(address to, bytes memory hookData) external payable virtual nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (msg.value == 0) revert InvalidAmount();

        // Check liquidity cap if it's set (0 means unlimited)
        uint256 _liquidityCap = liquidityCap;
        if (_liquidityCap > 0) {
            uint256 currentWrapped = wrappedAmount[to];
            uint256 newWrapped = currentWrapped + msg.value;
            if (newWrapped > _liquidityCap) {
                revert LiquidityCapExceeded(to, currentWrapped, msg.value, _liquidityCap);
            }
            wrappedAmount[to] = newWrapped;
        }

        address _hook = hook;
        uint256 actualAmount = msg.value;

        if (_hook != address(0)) {
            // Call onWrap hook with native tokens attached to get actual amount to mint
            actualAmount = IERC20xDHook(_hook).onWrap{ value: msg.value }(msg.sender, to, msg.value, hookData);
        }
        // If no hook, native tokens stay in this contract

        // Mint wrapped tokens for the native value received
        _transferFrom(address(0), to, actualAmount);

        emit Wrap(to, actualAmount);
    }

    /// @inheritdoc INativexD
    function unwrap(address to, uint256 amount, bytes memory data, bytes memory hookData)
        external
        payable
        virtual
        nonReentrant
        returns (bytes32 guid)
    {
        if (to == address(0)) revert InvalidAddress();

        // Encode the recipient address and hookData for the burn operation
        bytes memory callData = abi.encode(to, hookData);

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
            // Decode the recipient and hookData from callData
            (address recipient, bytes memory hookData) = abi.decode(pending.callData, (address, bytes));

            // Decrease wrapped amount for the sender if liquidity cap is enabled
            if (liquidityCap > 0) {
                uint256 currentWrapped = wrappedAmount[pending.from];
                wrappedAmount[pending.from] = currentWrapped > pending.amount ? currentWrapped - pending.amount : 0;
            }

            // Perform the burn
            _transferFrom(pending.from, address(0), pending.amount, pending.data);

            // Handle native token transfer
            address _hook = hook;
            uint256 underlyingAmount = pending.amount;

            if (_hook != address(0)) {
                // Call onUnwrap hook to get actual amount of native tokens to return
                // Hook should have transferred the native tokens to this contract
                underlyingAmount = IERC20xDHook(_hook).onUnwrap(pending.from, recipient, pending.amount, hookData);
            }

            // Send native tokens to the recipient
            AddressLib.transferNative(recipient, underlyingAmount);
            emit Unwrap(recipient, pending.amount, underlyingAmount);
        } else {
            // For normal transfers, use parent implementation
            super._executePendingTransfer(pending);
        }
    }

    /// @inheritdoc INativexD
    function setLiquidityCap(uint256 newCap) external virtual onlyOwner {
        liquidityCap = newCap;
        emit LiquidityCapUpdated(newCap);
    }
}
