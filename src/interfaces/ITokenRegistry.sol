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
    event BlacklistTargetSet(address indexed target, bool blacklisted);
    event BlacklistSelectorSet(bytes4 indexed selector, bool blacklisted);

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

    /**
     * @notice Check if a (target, selector) pair is blacklisted
     * @param target The target contract address
     * @param selector The function selector
     * @return blacklisted True if the pair is blacklisted
     */
    function isBlacklisted(address target, bytes4 selector) external view returns (bool blacklisted);

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

    /**
     * @notice Set blacklist status for multiple targets
     */
    function setBlacklistedTargets(address[] calldata targets, bool[] calldata flags) external;

    /**
     * @notice Set blacklist status for multiple function selectors
     */
    function setBlacklistedSelectors(bytes4[] calldata selectors, bool[] calldata flags) external;
}
