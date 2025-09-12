// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenRegistry {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error LengthMismatch();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenRegistered(address indexed token, bool status);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mapping of registered BaseERC20xD tokens
     * @param token The token address to check
     * @return registered Whether the token is registered
     */
    function registeredTokens(address token) external view returns (bool registered);

    /**
     * @notice Check if a token is registered
     * @param token The token address to check
     * @return registered True if the token is registered
     */
    function isRegistered(address token) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register or unregister a BaseERC20xD token
     * @dev Only owner can register tokens. This is for YOUR tokens only, not external protocols
     * @param token The BaseERC20xD token address
     * @param status True to register, false to unregister
     */
    function registerToken(address token, bool status) external;

    /**
     * @notice Batch register multiple tokens
     * @param tokens Array of token addresses
     * @param statuses Array of registration statuses
     */
    function batchRegisterTokens(address[] calldata tokens, bool[] calldata statuses) external;
}
