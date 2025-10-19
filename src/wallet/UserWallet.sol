// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IUserWallet } from "../interfaces/IUserWallet.sol";
import { TokenRegistry } from "./TokenRegistry.sol";

/**
 * @title UserWallet
 * @notice Smart contract wallet for each user with deterministic addresses
 * @dev Can be called by owner or registered BaseERC20xD tokens
 */
contract UserWallet is IUserWallet {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUserWallet
    address public immutable override owner;

    /// @inheritdoc IUserWallet
    address public immutable override registry;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _registry) {
        owner = _owner;
        registry = _registry;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorized() {
        if (msg.sender != owner && !TokenRegistry(registry).isRegistered(msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

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
        onlyAuthorized
        returns (bool success, bytes memory result)
    {
        // Prevent self-calls and delegatecalls to protect storage
        if (target == address(this)) revert SelfCallNotAllowed();

        // Prevent calling the registry to avoid privilege escalation
        if (target == registry) revert CannotCallRegistry();

        // Enforce blacklist policy via registry
        bytes4 selector;
        if (data.length >= 4) {
            assembly {
                selector := shr(224, calldataload(data.offset))
            }
        }
        if (TokenRegistry(registry).isBlacklisted(target, selector)) revert Unauthorized();

        // Execute the call using the ETH sent with this transaction
        (success, result) = target.call{ value: msg.value }(data);

        emit Executed(target, msg.value, data, success, result);

        // Don't revert on failure to allow handling in calling contract
        return (success, result);
    }

    /**
     * @notice Execute a static call (view function)
     * @dev Can be called by anyone since it's read-only
     * @param target The target contract address
     * @param data The calldata to send
     * @return result The return data from the call
     */
    function query(address target, bytes calldata data) external view returns (bytes memory result) {
        (bool success, bytes memory returnData) = target.staticcall(data);
        if (!success) revert QueryFailed();
        return returnData;
    }

    /**
     * @notice Get the balance of a specific token
     * @dev Helper function for common use case
     * @param token The ERC20 token address
     * @return balance The token balance
     */
    function getTokenBalance(address token) external view returns (uint256) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        if (!success || data.length < 32) revert BalanceQueryFailed();
        return abi.decode(data, (uint256));
    }

    /**
     * @notice Check if this wallet can execute calls
     * @dev Used by UI/UX to verify wallet status
     * @param caller The address to check authorization for
     * @return authorized Whether the caller is authorized
     */
    function isAuthorized(address caller) external view returns (bool) {
        return caller == owner || TokenRegistry(registry).isRegistered(caller);
    }

    /*//////////////////////////////////////////////////////////////
                              RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow receiving ETH
    receive() external payable { }

    /// @notice Fallback for receiving ETH with data
    fallback() external payable { }
}
