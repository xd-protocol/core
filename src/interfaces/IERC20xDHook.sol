// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

/**
 * @title IERC20xDHook
 * @notice Interface for contracts that want to be notified of balance changes in ERC20xD tokens
 */
interface IERC20xDHook {
    /**
     * @notice Called when a transfer is initiated
     * @dev This function should not revert as it could block transfers
     * @param from Source address initiating the transfer
     * @param to Destination address for the transfer
     * @param amount Amount of tokens being transferred
     * @param callData Optional calldata to execute on the recipient
     * @param value Native token value sent with the transfer
     * @param data Extra data passed with the transfer
     */
    function onInitiateTransfer(
        address from,
        address to,
        uint256 amount,
        bytes memory callData,
        uint256 value,
        bytes memory data
    ) external;

    /**
     * @notice Called when global availability is read during transfer execution
     * @dev This function should not revert as it could block transfers
     * @param account The account whose global availability was read
     * @param globalAvailability The total available balance across all chains
     */
    function onReadGlobalAvailability(address account, int256 globalAvailability) external;

    /**
     * @notice Called before transfer in ERC20xD
     * @dev This function should not revert as it could block transfers
     * @param from Source address (address(0) for mints)
     * @param to Destination address (address(0) for burns)
     * @param amount Amount transferred
     * @param data Extra data containing LayerZero parameters (gasLimit, refundTo) when applicable
     */
    function beforeTransfer(address from, address to, uint256 amount, bytes memory data) external;

    /**
     * @notice Called after transfer in ERC20xD
     * @dev This function should not revert as it could block transfers
     * @param from Source address (address(0) for mints)
     * @param to Destination address (address(0) for burns)
     * @param amount Amount transferred
     * @param data Extra data containing LayerZero parameters (gasLimit, refundTo) when applicable
     */
    function afterTransfer(address from, address to, uint256 amount, bytes memory data) external;

    function onMapAccounts(bytes32 chainUID, address remoteAccount, address localAccount) external;

    function onSettleLiquidity(bytes32 chainUID, uint256 timestamp, address account, int256 liquidity) external;

    function onSettleTotalLiquidity(bytes32 chainUID, uint256 timestamp, int256 totalLiquidity) external;

    function onSettleData(bytes32 chainUID, uint256 timestamp, bytes32 key, bytes memory value) external;
}
