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

    /// @notice Maximum amount of tokens that can be wrapped per account (0 = unlimited)
    uint256 public liquidityCap;

    /// @notice Tracks the amount of tokens wrapped by each account
    mapping(address => uint256) public wrappedAmount;

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

    // Override receive to resolve multiple inheritance
    receive() external payable virtual override(BaseERC20xD, IWrappedERC20xD) {
        _recoverableETH += msg.value;
    }

    /// @inheritdoc IWrappedERC20xD
    function wrap(address to, uint256 amount, bytes memory hookData) external payable virtual nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        // Check liquidity cap if it's set (0 means unlimited)
        uint256 _liquidityCap = liquidityCap;
        if (_liquidityCap > 0) {
            uint256 currentWrapped = wrappedAmount[to];
            uint256 newWrapped = currentWrapped + amount;
            if (newWrapped > _liquidityCap) {
                revert LiquidityCapExceeded(to, currentWrapped, amount, _liquidityCap);
            }
            wrappedAmount[to] = newWrapped;
        }

        // Always transfer underlying tokens to this contract first
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        address _hook = hook;
        uint256 actualAmount = amount;

        if (_hook != address(0)) {
            // Approve the hook to pull the tokens
            ERC20(underlying).approve(_hook, amount);

            // Call onWrap hook - hook should pull tokens using transferFrom
            actualAmount = IERC20xDHook(_hook).onWrap(msg.sender, to, amount, hookData);

            // Clear any remaining allowance
            ERC20(underlying).approve(_hook, 0);
        }

        // Mint wrapped tokens
        _transferFrom(address(0), to, actualAmount);

        emit Wrap(to, actualAmount);
    }

    /// @inheritdoc IWrappedERC20xD
    function unwrap(address to, uint256 amount, bytes memory data, bytes memory hookData)
        external
        payable
        virtual
        nonReentrant
        returns (bytes32 guid)
    {
        if (to == address(0)) revert InvalidAddress();

        // Encode the recipient address and hookData for the burn operation
        // This will be available in _transferFrom via pending.callData
        bytes memory callData = abi.encode(to, hookData);

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
            // Decode the recipient and hookData from callData
            (address recipient, bytes memory hookData) = abi.decode(pending.callData, (address, bytes));

            // Decrease wrapped amount for the sender if liquidity cap is enabled
            if (liquidityCap > 0) {
                uint256 currentWrapped = wrappedAmount[pending.from];
                wrappedAmount[pending.from] = currentWrapped > pending.amount ? currentWrapped - pending.amount : 0;
            }

            // Perform the burn
            _transferFrom(pending.from, address(0), pending.amount, pending.data);

            // Handle underlying token transfer
            address _hook = hook;
            uint256 underlyingAmount = pending.amount;

            if (_hook != address(0)) {
                // Call onUnwrap hook to get actual amount of underlying to return
                // Hook should have transferred the underlying tokens to this contract
                underlyingAmount = IERC20xDHook(_hook).onUnwrap(pending.from, recipient, pending.amount, hookData);
            }

            // Transfer underlying tokens to the recipient
            ERC20(underlying).safeTransfer(recipient, underlyingAmount);
            emit Unwrap(recipient, pending.amount, underlyingAmount);
        } else {
            // For normal transfers, use parent implementation
            super._executePendingTransfer(pending);
        }
    }

    /// @inheritdoc IWrappedERC20xD
    function setLiquidityCap(uint256 newCap) external virtual onlyOwner {
        liquidityCap = newCap;
        emit LiquidityCapUpdated(newCap);
    }
}
