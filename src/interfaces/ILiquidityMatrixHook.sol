// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILiquidityMatrixHook
 * @notice Interface for applications to receive callbacks when remote state is settled
 * @dev Implement this interface to be notified when liquidity or data from remote chains is settled
 *      All callbacks are executed with try/catch to prevent settlement failures
 */
interface ILiquidityMatrixHook {
    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called when remote accounts are successfully mapped to local accounts
     * @dev Allows apps to perform additional logic when account mappings are established
     * @param chainUID The unique identifier of the remote chain
     * @param remoteAccount The account address on the remote chain
     * @param localAccount The mapped local account address
     */
    function onMapAccounts(bytes32 chainUID, address remoteAccount, address localAccount) external;

    /**
     * @notice Called when liquidity for a specific account is settled from a remote chain
     * @dev Triggered during settleLiquidity if callbacks are enabled for the app
     * @param chainUID The unique identifier of the remote chain
     * @param version The version of the state
     * @param timestamp The timestamp of the settled data
     * @param account The account whose liquidity was updated
     */
    function onSettleLiquidity(bytes32 chainUID, uint256 version, uint64 timestamp, address account) external;

    /**
     * @notice Called when the total liquidity is settled from a remote chain
     * @dev Triggered after all individual account liquidity updates are processed
     * @param chainUID The unique identifier of the remote chain
     * @param version The version of the state
     * @param timestamp The timestamp of the settled data
     */
    function onSettleTotalLiquidity(bytes32 chainUID, uint256 version, uint64 timestamp) external;

    /**
     * @notice Called when data is settled from a remote chain
     * @dev Triggered during settleData if callbacks are enabled for the app
     * @param chainUID The unique identifier of the remote chain
     * @param version The version of the state
     * @param timestamp The timestamp of the settled data
     * @param key The data key that was updated
     */
    function onSettleData(bytes32 chainUID, uint256 version, uint64 timestamp, bytes32 key) external;
}
