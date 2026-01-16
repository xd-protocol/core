// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IGatewayApp } from "./IGatewayApp.sol";
import { ILiquidityMatrixHook } from "../interfaces/ILiquidityMatrixHook.sol";

interface IBaseERC20xD is IERC20, IGatewayApp, ILiquidityMatrixHook {
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

    /**
     * @notice Status of a queued transfer
     */
    enum TransferStatus {
        Pending,
        Processing,
        Executed,
        Cancelled,
        Failed
    }

    /**
     * @notice Represents a queued standard ERC20 transfer
     * @param from The address initiating the transfer
     * @param to The recipient address
     * @param amount The amount of tokens to transfer
     * @param status The current status of the transfer
     */
    struct QueuedTransfer {
        address from;
        address to;
        uint256 amount;
        TransferStatus status;
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
    error UserWalletFactoryNotSet();
    error CallFailure(address to, bytes reason);
    error NotComposing();
    error UnauthorizedComposeSpender();
    error UnauthorizedComposeSource();
    error NoChainsConfigured();
    error InvalidTarget();
    error InvalidLengths();
    error ChainAlreadyAdded();
    error ChainNotConfigured();
    error TransferNotQueued(uint64 id);
    error TransferNotCancellable(uint64 id);
    error InvalidTransferId();
    error InvalidBatchRange();
    error UnauthorizedSettler();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateLiquidityMatrix(address indexed liquidityMatrix);
    event UpdateGateway(address indexed gateway);
    event WalletFactoryUpdated(address indexed walletFactory);
    event InitiateTransfer(
        address indexed from, address indexed to, uint256 amount, uint256 value, uint256 indexed nonce
    );
    event CancelPendingTransfer(uint256 indexed nonce);
    event SetHook(address indexed oldHook, address indexed newHook);
    event OnMapAccountsHookFailure(
        address indexed hook, bytes32 indexed chainUID, address[] remoteAccounts, address[] localAccounts, bytes reason
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
    event AddReadTarget(bytes32 indexed chainUID, bytes32 indexed target);
    event UpdateReadTarget(bytes32 indexed chainUID, bytes32 indexed target);
    event ETHRecovered(address indexed to, uint256 amount);
    event TransferQueued(uint64 indexed id, address indexed from, address indexed to, uint256 amount);
    event TransferExecuted(uint64 indexed id);
    event TransferFailed(uint64 indexed id);
    event TransferCancelled(uint64 indexed id);

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
     * @notice Returns the address of the UserWalletFactory contract
     * @return The UserWalletFactory contract address
     */
    function walletFactory() external view returns (address);

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

    /**
     * @notice Retrieves available balances of multiple accounts on current chain
     * @dev This will be called by Gateway read for batch processing
     * @param accounts The accounts to query
     * @return balances The balances that can be spent on current chain
     */
    function availableLocalBalanceOf(address[] calldata accounts) external view returns (int256[] memory balances);

    /**
     * @notice Returns the next transfer ID to be assigned
     * @return The next transfer ID
     */
    function nextTransferId() external view returns (uint64);

    /**
     * @notice Returns the last processed transfer ID
     * @return The last processed transfer ID
     */
    function lastProcessedId() external view returns (uint64);

    /**
     * @notice Returns the queued transfer details for a given ID
     * @param id The transfer ID to query
     * @return The queued transfer struct
     */
    function getQueuedTransfer(uint64 id) external view returns (QueuedTransfer memory);

    /**
     * @notice Returns the locked amount for an account
     * @param account The account to query
     * @return The locked amount
     */
    function getLockedAmount(address account) external view returns (uint256);

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
     * @notice Updates the UserWalletFactory address for compose operations
     * @param newWalletFactory The new UserWalletFactory contract address
     * @dev Compose requires a UserWalletFactory; if set to address(0), compose will revert
     */
    function updateWalletFactory(address newWalletFactory) external;

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
     * @notice Sets the hook for the token (replacing any existing hook)
     * @param newHook The hook address to set (address(0) to remove hook)
     */
    function setHook(address newHook) external;

    /**
     * @notice Returns the current hook address
     * @return The hook address (address(0) if no hook set)
     */
    function getHook() external view returns (address);

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

    /**
     * @notice Adds new chains to read from for cross-chain operations
     * @dev Only callable by owner. Reverts if any chain already exists.
     * @param chainUIDs Array of new chain UIDs to add
     * @param targets Array of target addresses for each chain
     */
    function addReadChains(bytes32[] memory chainUIDs, address[] memory targets) external;

    /**
     * @notice Updates target addresses for existing chains
     * @dev Only callable by owner. Reverts if any chain doesn't exist.
     * @param chainUIDs Array of existing chain UIDs to update
     * @param targets Array of new target addresses for each chain
     */
    function updateReadTargets(bytes32[] memory chainUIDs, address[] memory targets) external;

    /**
     * @notice Returns the amount of ETH that can be recovered
     * @dev This is ETH that was sent through receive()
     * @return The amount of recoverable ETH
     */
    function getRecoverableETH() external view returns (uint256);

    /**
     * @notice Recover all ETH that was sent to the contract through receive()
     * @dev Only the owner can recover ETH. Recovers all tracked ETH in one call.
     * @param to The address to send the recovered ETH to
     */
    function recoverETH(address to) external;

    /**
     * @notice Cancels a queued standard transfer
     * @dev Only callable by the sender of the transfer while in Pending status
     * @param id The transfer ID to cancel
     */
    function cancelQueuedTransfer(uint64 id) external;

    /**
     * @notice Initiates batch processing of queued transfers
     * @dev Only callable by settler. Starts Gateway.read() for global availability check.
     * @param startId The first transfer ID to process (must be lastProcessedId + 1)
     * @param endId The last transfer ID to process (inclusive)
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters
     * @return guid The unique identifier for this batch operation
     */
    function processTransfers(uint64 startId, uint64 endId, bytes memory data) external payable returns (bytes32 guid);
}
