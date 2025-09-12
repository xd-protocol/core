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

        // Transfer underlying tokens from caller
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        // Mint wrapped tokens
        _transferFrom(address(0), to, amount);

        emit Wrap(to, amount);
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

        // Pass recipient address in callData for hooks to use
        guid = _transfer(msg.sender, address(0), amount, abi.encode(to), 0, data);

        emit Unwrap(to, amount);
    }

    /// @inheritdoc IWrappedERC20xD
    function quoteUnwrap(uint128 gasLimit) external view virtual returns (uint256) {
        // Unwrap requires cross-chain messaging for global availability check
        return this.quoteTransfer(msg.sender, gasLimit);
    }
}
