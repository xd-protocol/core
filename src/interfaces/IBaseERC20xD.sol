// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20Permit } from "./IERC20Permit.sol";
import { IGatewayApp } from "./IGatewayApp.sol";

interface IBaseERC20xD is IERC20Permit, IGatewayApp {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Represents a pending cross-chain transfer.
     * @param pending Indicates if the transfer is still pending.
     * @param from The address initiating the transfer.
     * @param to The recipient address on the target chain.
     * @param amount The amount of tokens to transfer.
     * @param callData Optional calldata for executing a function on the recipient contract.
     * @param value The native cryptocurrency value to send with the callData, if any.
     * @param data Extra data containing cross-chain parameters (uint128 gasLimit, address refundTo).
     */
    struct PendingTransfer {
        bool pending;
        address from;
        address to;
        uint256 amount;
        bytes callData;
        uint256 value;
        bytes data;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRequests();
    error Unsupported();
    error Forbidden();
    error TransferNotPending(uint256 nonce);
    error InvalidAmount();
    error InvalidAddress();
    error InsufficientBalance();
    error InsufficientValue();
    error TransferPending();
    error Overflow();
    error InsufficientAvailability(uint256 nonce, uint256 amount, int256 availabillity);
    error CallFailure(address to, bytes reason);
    error NotComposing();
    error HookAlreadyAdded();
    error HookNotFound();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateLiquidityMatrix(address indexed liquidityMatrix);
    event UpdateGateway(address indexed gateway);
    event InitiateTransfer(
        address indexed from, address indexed to, uint256 amount, uint256 value, uint256 indexed nonce
    );
    event CancelPendingTransfer(uint256 indexed nonce);
    event HookAdded(address indexed hook);
    event HookRemoved(address indexed hook);
    event OnInitiateTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, uint256 value, bytes reason
    );
    event OnReadGlobalAvailabilityHookFailure(
        address indexed hook, address indexed account, int256 globalAvailability, bytes reason
    );
    event BeforeTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, bytes reason
    );
    event AfterTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, bytes reason
    );
    event OnMapAccountsHookFailure(
        address indexed hook, bytes32 indexed chainUID, address remoteAccount, address localAccount, bytes reason
    );
    event OnSettleLiquidityHookFailure(
        address indexed hook,
        bytes32 indexed chainUID,
        uint64 timestamp,
        address indexed account,
        int256 liquidity,
        bytes reason
    );
    event OnSettleTotalLiquidityHookFailure(
        address indexed hook, bytes32 indexed chainUID, uint64 timestamp, int256 totalLiquidity, bytes reason
    );
    event OnSettleDataHookFailure(
        address indexed hook, bytes32 indexed chainUID, uint64 timestamp, bytes32 indexed key, bytes value, bytes reason
    );

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the LiquidityMatrix contract
     * @return The LiquidityMatrix contract address
     */
    function liquidityMatrix() external view returns (address);

    /**
     * @notice Returns the address of the Gateway contract
     * @return The Gateway contract address
     */
    function gateway() external view returns (address);

    /**
     * @notice Returns the hook address at a specific index
     * @param index The index of the hook to retrieve
     * @return The hook contract address
     */
    function hooks(uint256 index) external view returns (address);

    /**
     * @notice Checks if an address is a registered hook
     * @param hook The address to check
     * @return True if the address is a registered hook
     */
    function isHook(address hook) external view returns (bool);

    /**
     * @notice Returns the pending transfer nonce for an account
     * @param account The account to check
     * @return The pending transfer nonce (0 if no pending transfer)
     */
    function pendingNonce(address account) external view returns (uint256);

    /**
     * @notice Returns the pending transfer details for an account
     * @param account The account to check
     * @return The pending transfer struct
     */
    function pendingTransfer(address account) external view returns (PendingTransfer memory);

    /**
     * @notice Returns the total supply on the current chain
     * @return The local total supply of the token as an int256
     */
    function localTotalSupply() external view returns (int256);

    /**
     * @notice Returns the local balance of a specific account on the current chain
     * @param account The account to query
     * @return The local balance of the account on this chain as an int256
     */
    function localBalanceOf(address account) external view returns (int256);

    /**
     * @notice Quotes the messaging fee for sending a read request with specific gas and calldata size
     * @param from The address initiating the cross-chain transfer
     * @param gasLimit The gas limit to allocate for actual transfer after Gateway read
     * @return fee The estimated messaging fee for the request
     */
    function quoteTransfer(address from, uint128 gasLimit) external view returns (uint256);

    /**
     * @notice Retrieves available balance of account on current chain
     * @dev This will be called by Gateway read from remote chains
     * @param account The owner of available balance to read
     * @return balance The balance that can be spent on current chain
     */
    function availableLocalBalanceOf(address account) external view returns (int256);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the liquidity matrix contract address
     * @param newLiquidityMatrix The new liquidity matrix address
     */
    function updateLiquidityMatrix(address newLiquidityMatrix) external;

    /**
     * @notice Updates the gateway contract address
     * @param newGateway The new gateway address
     */
    function updateGateway(address newGateway) external;

    /**
     * @notice Updates the read target address for a specific chain
     * @param chainUID The chain unique identifier
     * @param target The target address on the remote chain
     */
    function updateReadTarget(bytes32 chainUID, bytes32 target) external;

    /**
     * @notice Updates whether to sync only mapped accounts
     * @param syncMappedAccountsOnly True to sync only mapped accounts
     */
    function updateSyncMappedAccountsOnly(bool syncMappedAccountsOnly) external;

    /**
     * @notice Updates whether to use callbacks
     * @param useHook True to enable callbacks
     */
    function updateUseHook(bool useHook) external;

    /**
     * @notice Updates the settler address
     * @param settler The new settler address
     */
    function updateSettler(address settler) external;

    /**
     * @notice Updates the remote app address and index for a specific chain
     * @param chainUID The chain unique identifier
     * @param app The remote app address on the specified chain
     * @param appIndex The index of the app on the remote chain
     */
    function updateRemoteApp(bytes32 chainUID, address app, uint256 appIndex) external;

    /**
     * @notice Adds a hook to the token
     * @param hook The hook address to add
     */
    function addHook(address hook) external;

    /**
     * @notice Removes a hook from the token
     * @param hook The hook address to remove
     */
    function removeHook(address hook) external;

    /**
     * @notice Returns all registered hooks
     * @return Array of hook addresses
     */
    function getHooks() external view returns (address[] memory);

    /**
     * @notice Transfers tokens with encoded cross-chain parameters
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     * @return guid The unique identifier for this transfer
     */
    function transfer(address to, uint256 amount, bytes memory data) external payable returns (bytes32 guid);

    /**
     * @notice Transfers tokens with calldata execution and cross-chain parameters
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param callData Optional function call data to execute on recipient
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     * @return guid The unique identifier for this transfer
     */
    function transfer(address to, uint256 amount, bytes memory callData, bytes memory data)
        external
        payable
        returns (bytes32 guid);

    /**
     * @notice Transfers tokens with calldata execution, value, and cross-chain parameters
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param callData Optional function call data to execute on recipient
     * @param value Native currency value to send with callData
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     * @return guid The unique identifier for this transfer
     */
    function transfer(address to, uint256 amount, bytes memory callData, uint256 value, bytes memory data)
        external
        payable
        returns (bytes32 guid);

    /**
     * @notice Cancels a pending cross-chain transfer
     * @dev Only callable by the user who initiated the transfer
     */
    function cancelPendingTransfer() external;
}
