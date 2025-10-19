// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUserWallet {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error SelfCallNotAllowed();
    error CannotCallRegistry();
    error QueryFailed();
    error BalanceQueryFailed();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Executed(address indexed target, uint256 value, bytes data, bool success, bytes result);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The user who owns this wallet
     * @return The owner address
     */
    function owner() external view returns (address);

    /**
     * @notice The token registry contract
     * @return The registry address
     */
    function registry() external view returns (address);

    /**
     * @notice Execute a static call (view function)
     * @dev Can be called by anyone since it's read-only
     * @param target The target contract address
     * @param data The calldata to send
     * @return result The return data from the call
     */
    function query(address target, bytes calldata data) external view returns (bytes memory result);

    /**
     * @notice Get the balance of a specific token
     * @dev Helper function for common use case
     * @param token The ERC20 token address
     * @return balance The token balance
     */
    function getTokenBalance(address token) external view returns (uint256);

    /**
     * @notice Check if this wallet can execute calls
     * @dev Used by UI/UX to verify wallet status
     * @param caller The address to check authorization for
     * @return authorized Whether the caller is authorized
     */
    function isAuthorized(address caller) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute an arbitrary call
     * @dev Can be called by owner or registered tokens. Prevents delegatecall and self-calls
     * @param target The target contract address
     * @param data The calldata to send
     * @return success Whether the call succeeded
     * @return result The return data from the call
     */
    function execute(address target, bytes calldata data)
        external
        payable
        returns (bool success, bytes memory result);
}
