// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IRemoteAppChronicle
 * @notice Interface for managing settled state from remote chains for a specific app/chain/version combination
 * @dev Each RemoteAppChronicle instance handles settlement of cross-chain data for one app on one remote chain
 *      in a specific version. This enables version-isolated state management for reorganization protection.
 *
 *      The chronicle processes two types of settlements:
 *      - Liquidity settlements: Account balances from remote chains
 *      - Data settlements: Arbitrary key-value data from remote chains
 *
 *      When both liquidity and data are settled for the same timestamp, the state becomes "finalized",
 *      representing a complete snapshot of the remote chain's state at that point in time.
 */
interface IRemoteAppChronicle {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when caller is not the authorized settler
     */
    error Forbidden();

    /**
     * @notice Thrown when attempting to settle liquidity that's already settled
     */
    error LiquidityAlreadySettled();

    /**
     * @notice Thrown when attempting to settle data that's already settled
     */
    error DataAlreadySettled();

    /**
     * @notice Thrown when no root has been received for the given timestamp
     */
    error RootNotReceived();

    /**
     * @notice Thrown when the Merkle proof verification fails
     */
    error InvalidMerkleProof();

    error RemoteAppNotSet();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the LiquidityMatrix contract address
     * @return The address of the LiquidityMatrix that deployed this chronicle
     */
    function liquidityMatrix() external view returns (address);

    /**
     * @notice Returns the application this chronicle serves
     * @return The application address
     */
    function app() external view returns (address);

    /**
     * @notice Returns the chain unique identifier of the remote chain
     * @return The chain UID this chronicle tracks
     */
    function chainUID() external view returns (bytes32);

    /**
     * @notice Returns the version number this chronicle is associated with
     * @return The version number for state isolation
     */
    function version() external view returns (uint256);

    /**
     * @notice Checks if state is finalized at a specific timestamp
     * @dev State is finalized when both liquidity and data are settled for the same timestamp
     * @param timestamp The timestamp to check
     * @return True if both liquidity and data are settled at this timestamp
     */
    function isFinalized(uint64 timestamp) external view returns (bool);

    /**
     * @notice Checks if liquidity is settled at a specific timestamp
     * @param timestamp The timestamp to check
     * @return True if liquidity has been settled at this timestamp
     */
    function isLiquiditySettled(uint64 timestamp) external view returns (bool);

    /**
     * @notice Checks if data is settled at a specific timestamp
     * @param timestamp The timestamp to check
     * @return True if data has been settled at this timestamp
     */
    function isDataSettled(uint64 timestamp) external view returns (bool);

    /**
     * @notice Gets the total liquidity at a specific timestamp
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity across all accounts at that timestamp
     */
    function getTotalLiquidityAt(uint64 timestamp) external view returns (int256 liquidity);

    /**
     * @notice Gets the liquidity for a specific account at a timestamp
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The account's liquidity at that timestamp
     */
    function getLiquidityAt(address account, uint64 timestamp) external view returns (int256 liquidity);

    /**
     * @notice Gets the data value for a key at a specific timestamp
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return data The data value at that timestamp
     */
    function getDataAt(bytes32 key, uint64 timestamp) external view returns (bytes memory data);

    /**
     * @notice Gets the most recent timestamp when liquidity was settled
     * @return The last settled liquidity timestamp, or 0 if never settled
     */
    function getLastSettledLiquidityTimestamp() external view returns (uint64);

    /**
     * @notice Gets the most recent settled liquidity timestamp at or before a given timestamp
     * @param timestamp The timestamp to search from
     * @return The nearest settled liquidity timestamp at or before the input
     */
    function getSettledLiquidityTimestampAt(uint64 timestamp) external view returns (uint64);

    /**
     * @notice Gets the most recent timestamp when data was settled
     * @return The last settled data timestamp, or 0 if never settled
     */
    function getLastSettledDataTimestamp() external view returns (uint64);

    /**
     * @notice Gets the most recent settled data timestamp at or before a given timestamp
     * @param timestamp The timestamp to search from
     * @return The nearest settled data timestamp at or before the input
     */
    function getSettledDataTimestampAt(uint64 timestamp) external view returns (uint64);

    /**
     * @notice Gets the most recent timestamp when state was finalized
     * @return The last finalized timestamp, or 0 if never finalized
     */
    function getLastFinalizedTimestamp() external view returns (uint64);

    /**
     * @notice Gets the most recent finalized timestamp at or before a given timestamp
     * @param timestamp The timestamp to search from
     * @return The nearest finalized timestamp at or before the input
     */
    function getFinalizedTimestampAt(uint64 timestamp) external view returns (uint64);
}
