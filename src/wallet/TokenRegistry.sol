// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ITokenRegistry } from "../interfaces/ITokenRegistry.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenRegistry
 * @notice Registry for managing BaseERC20xD tokens that can use UserWallet
 * @dev Only registers tokens, not external protocols like Uniswap or Aave
 */
contract TokenRegistry is ITokenRegistry, Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITokenRegistry
    mapping(address token => bool registered) public override registeredTokens;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register or unregister a BaseERC20xD token
     * @dev Only owner can register tokens. This is for YOUR tokens only, not external protocols
     * @param token The BaseERC20xD token address
     * @param status True to register, false to unregister
     */
    function registerToken(address token, bool status) external onlyOwner {
        registeredTokens[token] = status;
        emit TokenRegistered(token, status);
    }

    /**
     * @notice Check if a token is registered
     * @param token The token address to check
     * @return registered True if the token is registered
     */
    function isRegistered(address token) external view returns (bool) {
        return registeredTokens[token];
    }

    /**
     * @notice Batch register multiple tokens
     * @param tokens Array of token addresses
     * @param statuses Array of registration statuses
     */
    function batchRegisterTokens(address[] calldata tokens, bool[] calldata statuses) external onlyOwner {
        if (tokens.length != statuses.length) revert LengthMismatch();

        for (uint256 i = 0; i < tokens.length; i++) {
            registeredTokens[tokens[i]] = statuses[i];
            emit TokenRegistered(tokens[i], statuses[i]);
        }
    }
}
