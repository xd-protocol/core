// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

/**
 * @title IERC20xDHook
 * @notice Interface for contracts that want to be notified of balance changes in ERC20xD tokens
 */
interface IERC20xDHook {
    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Called when a transfer is initiated
     * @dev This function should not revert as it could block transfers
     * @param from Source address initiating the transfer
     * @param to Destination address for the transfer
     * @param amount Amount of tokens being transferred
     * @param callData Optional calldata to execute on the recipient
     * @param value Native token value sent with the transfer
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters passed with the transfer
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
     * @param data Extra data containing cross-chain parameters (uint128 gasLimit, address refundTo) when applicable
     */
    function beforeTransfer(address from, address to, uint256 amount, bytes memory data) external;

    /**
     * @notice Called after transfer in ERC20xD
     * @dev This function should not revert as it could block transfers
     * @param from Source address (address(0) for mints)
     * @param to Destination address (address(0) for burns)
     * @param amount Amount transferred
     * @param data Extra data containing cross-chain parameters (uint128 gasLimit, address refundTo) when applicable
     */
    function afterTransfer(address from, address to, uint256 amount, bytes memory data) external;

    /**
     * @notice Called when remote accounts are mapped to local accounts
     * @dev This function should not revert as it could block account mapping
     * @param chainUID The remote chain identifier
     * @param remoteAccount The account address on the remote chain
     * @param localAccount The mapped local account address
     */
    function onMapAccounts(bytes32 chainUID, address remoteAccount, address localAccount) external;

    /**
     * @notice Called when liquidity for a specific account is settled from a remote chain
     * @dev This function should not revert as it could block settlement
     * @param chainUID The remote chain identifier
     * @param timestamp The timestamp of the settlement
     * @param account The account whose liquidity was settled
     * @param liquidity The settled liquidity amount
     */
    function onSettleLiquidity(bytes32 chainUID, uint256 timestamp, address account, int256 liquidity) external;

    /**
     * @notice Called when total liquidity is settled from a remote chain
     * @dev This function should not revert as it could block settlement
     * @param chainUID The remote chain identifier
     * @param timestamp The timestamp of the settlement
     * @param totalLiquidity The total liquidity amount settled
     */
    function onSettleTotalLiquidity(bytes32 chainUID, uint256 timestamp, int256 totalLiquidity) external;

    /**
     * @notice Called when data is settled from a remote chain
     * @dev This function should not revert as it could block settlement
     * @param chainUID The remote chain identifier
     * @param timestamp The timestamp of the settlement
     * @param key The data key that was settled
     * @param value The settled data value
     */
    function onSettleData(bytes32 chainUID, uint256 timestamp, bytes32 key, bytes memory value) external;

    /**
     * @notice Called when tokens are being wrapped
     * @dev For ERC20 tokens: The wrapped token contract holds the tokens and gives this hook an allowance.
     *      The hook should use transferFrom to pull the exact amount needed.
     *      For native tokens: Called WITH native tokens attached as msg.value.
     *      The hook is responsible for managing these tokens (e.g., depositing to a vault).
     *      This function should not revert as it could block wrapping.
     * @param from The address providing the underlying tokens
     * @param to The address receiving the wrapped tokens
     * @param amount The amount of underlying tokens being wrapped (equals msg.value for native)
     * @return actualAmount The actual amount of wrapped tokens to mint (usually same as amount)
     */
    function onWrap(address from, address to, uint256 amount) external payable returns (uint256 actualAmount);

    /**
     * @notice Called when tokens are being unwrapped
     * @dev This function is called BEFORE burning the wrapped tokens.
     *      The hook must transfer the underlying tokens to the unwrap contract.
     *      Can return more underlying than shares if yield was accrued.
     *      This function should not revert as it could block unwrapping.
     * @param from The address providing the wrapped tokens
     * @param to The address receiving the underlying tokens
     * @param shares The amount of wrapped tokens being burned
     * @return underlyingAmount The actual amount of underlying tokens to return (can exceed shares if yield accrued)
     */
    function onUnwrap(address from, address to, uint256 shares) external returns (uint256 underlyingAmount);
}
