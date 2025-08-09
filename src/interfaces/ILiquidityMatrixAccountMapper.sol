// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILiquidityMatrixAccountMapper
 * @notice Interface for apps to validate account mapping requests from remote chains
 * @dev Implement this interface to control which remote accounts can be mapped to local accounts
 */
interface ILiquidityMatrixAccountMapper {
    /**
     * @notice Validates whether a remote account should be mapped to a local account
     * @dev Called by LiquidityMatrix when processing mapping requests from remote chains
     * @param chainUID The unique identifier of the remote chain
     * @param remoteAccount The account address on the remote chain
     * @param localAccount The account address on the local chain
     * @return Whether the mapping should be allowed
     */
    function shouldMapAccounts(bytes32 chainUID, address remoteAccount, address localAccount)
        external
        view
        returns (bool);
}
