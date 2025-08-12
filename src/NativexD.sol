// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xD } from "./mixins/BaseERC20xD.sol";
import { INativexD } from "./interfaces/INativexD.sol";
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

        // Mint wrapped tokens for the native value received
        _transferFrom(address(0), to, msg.value);

        emit Wrap(to, msg.value);
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
        guid = _transfer(msg.sender, address(0), amount, abi.encode(to), 0, data);

        emit Unwrap(to, amount);
    }

    /// @inheritdoc INativexD
    function quoteUnwrap(uint128 gasLimit) external view virtual returns (uint256) {
        // Unwrap requires cross-chain messaging for global availability check
        return quoteTransfer(msg.sender, gasLimit);
    }
}
