// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

/**
 * @title BaseERC20
 * @notice An abstract ERC20 contract providing foundational functionality and storage.
 */
abstract contract BaseERC20 is IERC20 {
    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address account => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20 token with metadata.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _decimals The number of decimals the token uses.
     */
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total supply of the token across all chains.
     * @return The total supply of the token as a `uint256`.
     */
    function totalSupply() public view virtual returns (uint256);
    /**
     * @notice Returns the synced balance of a specific account across all chains.
     * @param account The address of the account to query.
     * @return The synced balance of the account as a `uint256`.
     */
    function balanceOf(address account) public view virtual returns (uint256);

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves a spender to transfer up to a specified amount of tokens on behalf of the caller.
     * @param spender The address allowed to spend the tokens.
     * @param amount The maximum amount of tokens the spender is allowed to transfer.
     * @return true if the approval is successful.
     */
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /**
     * @notice Transfers a specified amount of tokens to another address.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return true if the transfer is successful.
     */
    function transfer(address to, uint256 amount) public virtual returns (bool);

    /**
     * @notice Transfers a specified amount of tokens from one address to another, using the caller's allowance.
     * @dev The caller must be approved to transfer the specified amount on behalf of `from`.
     *      The `hasSufficientBalance` modifier ensures that the `from` address has enough local balance.
     * @param from The address from which tokens will be transferred.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return true if the transfer is successful.
     */
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool);
}
