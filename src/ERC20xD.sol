// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xD } from "./mixins/BaseERC20xD.sol";
import { IERC20xD } from "./interfaces/IERC20xD.sol";

/**
 * @title ERC20xD
 * @notice A concrete implementation of a cross-chain ERC20 token with full transfer and liquidity management capabilities
 * @dev Extends BaseERC20xD to provide a complete cross-chain token implementation that can be deployed directly.
 *      Inherits all functionality including pending transfers, hooks, cross-chain reads, and liquidity tracking.
 */
contract ERC20xD is BaseERC20xD, IERC20xD {
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20xD contract.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the Gateway contract.
     * @param _owner The owner of this contract.
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
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Quotes the fee for burning tokens (cross-chain transfer to zero address)
     * @param from The address burning the tokens
     * @param gasLimit The gas limit for the cross-chain operation
     * @return fee The estimated fee for the burn operation
     */
    function quoteBurn(address from, uint128 gasLimit) public view returns (uint256 fee) {
        return quoteTransfer(from, gasLimit);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    fallback() external payable virtual { }

    receive() external payable virtual { }

    /**
     * @notice Mints tokens by transferring from the zero address.
     * @param to The recipient address of the minted tokens.
     * @param amount The amount of tokens to mint.
     * @dev Only callable by the contract owner. Triggers hook callbacks if any are registered.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _transferFrom(address(0), to, amount);
    }

    /**
     * @notice Burns tokens by transferring them to the zero address with cross-chain availability check.
     * @param amount The amount of tokens to burn.
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters for cross-chain operations.
     * @return guid The unique identifier for this cross-chain operation.
     * @dev Performs global liquidity check across all chains before burning. Triggers hook callbacks if any are registered.
     */
    function burn(uint256 amount, bytes calldata data) external payable returns (bytes32 guid) {
        return _transfer(msg.sender, address(0), amount, "", 0, data);
    }
}
