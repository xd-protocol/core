// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BaseERC20xD } from "./mixins/BaseERC20xD.sol";
import { IWrappedERC20xD } from "./interfaces/IWrappedERC20xD.sol";

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
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 amount);

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
     */
    constructor(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner
    ) BaseERC20xD(_name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner) {
        underlying = _underlying;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    fallback() external payable virtual { }

    receive() external payable virtual { }

    /**
     * @notice Wraps underlying tokens by transferring tokens from the caller and minting wrapped tokens.
     * @dev Transfers underlying tokens from caller and mints equivalent wrapped tokens.
     *      Hooks can be used to implement custom deposit logic (e.g., depositing to vaults).
     * @param to The destination address to receive the wrapped tokens.
     * @param amount The amount of underlying tokens to wrap.
     */
    function wrap(address to, uint256 amount) external payable virtual nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        // Transfer underlying tokens from caller
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        // Mint wrapped tokens
        _transferFrom(address(0), to, amount);

        emit Wrap(to, amount);
    }

    /**
     * @notice Initiates an unwrap operation to burn wrapped tokens.
     * @dev Burns wrapped tokens after global availability check. The actual redemption of underlying
     *      tokens should be handled by hooks in the afterTransfer callback.
     * @param to The destination address to receive the unwrapped tokens.
     * @param amount The amount of wrapped tokens to unwrap.
     * @param data Extra data containing cross-chain parameters (uint128 gasLimit, address refundTo) for cross-chain messaging.
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
     * @notice Quotes the fee for wrapping tokens.
     * @param gasLimit The gas limit (unused for local operations)
     * @return fee The fee required for the wrap operation.
     */
    function quoteWrap(uint128 gasLimit) external pure virtual returns (uint256) {
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
