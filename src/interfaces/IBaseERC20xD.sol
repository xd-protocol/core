// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20Permit } from "./IERC20Permit.sol";
import { IGatewayApp } from "./IGatewayApp.sol";

interface IBaseERC20xD is IERC20Permit, IGatewayApp {
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

    function liquidityMatrix() external view returns (address);

    function gateway() external view returns (address);

    function pendingNonce(address account) external view returns (uint256);

    function pendingTransfer(address account) external view returns (PendingTransfer memory);

    function localTotalSupply() external view returns (int256);

    function localBalanceOf(address account) external view returns (int256);

    function quoteTransfer(address from, uint128 gasLimit) external view returns (uint256);

    function availableLocalBalanceOf(address account) external view returns (int256);

    function updateLiquidityMatrix(address newLiquidityMatrix) external;

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
     * @param useCallbacks True to enable callbacks
     */
    function updateUseCallbacks(bool useCallbacks) external;

    /**
     * @notice Updates the settler address
     * @param settler The new settler address
     */
    function updateSettler(address settler) external;

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

    function cancelPendingTransfer() external;
}
