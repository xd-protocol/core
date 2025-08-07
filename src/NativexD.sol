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
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the NativexD contract.
     * @param _name The name of the wrapped native token.
     * @param _symbol The symbol of the wrapped native token.
     * @param _decimals The number of decimals for the wrapped native token.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the ERC20xDGateway contract.
     * @param _owner The address that will be granted ownership privileges.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner
    ) BaseERC20xD(_name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    fallback() external payable virtual { }

    receive() external payable virtual { }

    /**
     * @notice Wraps native tokens by accepting native value and minting wrapped tokens.
     * @dev Accepts native tokens via msg.value and mints equivalent wrapped tokens.
     *      Hooks can be used to implement custom deposit logic (e.g., depositing to vaults).
     * @param to The destination address to receive the wrapped tokens.
     */
    function wrap(address to) external payable virtual nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (msg.value == 0) revert InvalidAmount();

        // Mint wrapped tokens for the native value received
        _transferFrom(address(0), to, msg.value);

        emit Wrap(to, msg.value);
    }

    /**
     * @notice Initiates an unwrap operation to burn wrapped tokens.
     * @dev Burns wrapped tokens after global availability check. The actual redemption of native
     *      tokens should be handled by hooks in the afterTransfer callback.
     * @param to The destination address to receive the unwrapped native tokens.
     * @param amount The amount of wrapped tokens to unwrap.
     * @param data Extra data containing LayerZero parameters (gasLimit, refundTo) for cross-chain messaging.
     */
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

    /**
     * @notice Quotes the fee for wrapping native tokens.
     * @return fee The fee required for the wrap operation.
     */
    function quoteWrap(uint128) external pure virtual returns (uint256) {
        // Wrap is a local operation, no cross-chain fee needed
        return 0;
    }

    /**
     * @notice Quotes the fee for unwrapping tokens.
     * @param gasLimit The gas limit for the cross-chain operation.
     * @return fee The fee required for the unwrap operation.
     */
    function quoteUnwrap(uint128 gasLimit) external view virtual returns (uint256) {
        // Unwrap requires cross-chain messaging for global availability check
        return quoteTransfer(msg.sender, gasLimit);
    }
}
