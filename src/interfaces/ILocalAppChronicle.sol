// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILocalAppChronicle
 * @notice Interface for managing local application state within a specific version
 * @dev Each LocalAppChronicle instance is tied to a specific app and version,
 *      providing isolated state management to protect against blockchain reorganizations.
 *      The chronicle maintains Merkle trees for both liquidity and data, enabling
 *      efficient state verification and cross-chain synchronization.
 */
interface ILocalAppChronicle {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when liquidity is updated for an account
     * @param topTreeIndex The index in the top-level liquidity tree
     * @param account The account whose liquidity was updated
     * @param appTreeIndex The index in the app's liquidity tree
     * @param timestamp The timestamp of the update
     */
    event UpdateLiquidity(
        uint256 topTreeIndex, address indexed account, uint256 appTreeIndex, uint64 indexed timestamp
    );

    /**
     * @notice Emitted when data is updated for a key
     * @param topTreeIndex The index in the top-level data tree
     * @param key The data key that was updated
     * @param hash The keccak256 hash of the data value
     * @param appTreeIndex The index in the app's data tree
     * @param timestamp The timestamp of the update
     */
    event UpdateData(
        uint256 topTreeIndex, bytes32 indexed key, bytes32 hash, uint256 appTreeIndex, uint64 indexed timestamp
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Thrown when chronicle is not properly initialized
     */
    error NotInitialized();

    /**
     * @notice Thrown when caller is not authorized
     */
    error Forbidden();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the LiquidityMatrix contract
     * @return The LiquidityMatrix contract address
     */
    function liquidityMatrix() external view returns (address);

    /**
     * @notice Returns the address of the application this chronicle serves
     * @return The application address
     */
    function app() external view returns (address);

    /**
     * @notice Returns the version number this chronicle is associated with
     * @return The version number
     */
    function version() external view returns (uint256);

    /**
     * @notice Gets the current root of the liquidity Merkle tree
     * @return The liquidity tree root hash
     */
    function getLiquidityRoot() external view returns (bytes32);

    /**
     * @notice Gets the current root of the data Merkle tree
     * @return The data tree root hash
     */
    function getDataRoot() external view returns (bytes32);

    /**
     * @notice Gets the current total liquidity for the app
     * @return liquidity The total liquidity across all accounts
     */
    function getTotalLiquidity() external view returns (int256 liquidity);

    /**
     * @notice Gets the total liquidity at a specific timestamp
     * @param timestamp The timestamp to query
     * @return liquidity The total liquidity at that timestamp
     */
    function getTotalLiquidityAt(uint256 timestamp) external view returns (int256 liquidity);

    /**
     * @notice Gets the current liquidity for a specific account
     * @param account The account address
     * @return liquidity The account's current liquidity
     */
    function getLiquidity(address account) external view returns (int256 liquidity);

    /**
     * @notice Gets the liquidity for an account at a specific timestamp
     * @param account The account address
     * @param timestamp The timestamp to query
     * @return liquidity The account's liquidity at that timestamp
     */
    function getLiquidityAt(address account, uint256 timestamp) external view returns (int256 liquidity);

    /**
     * @notice Gets the current data value for a key
     * @param key The data key
     * @return data The data value
     */
    function getData(bytes32 key) external view returns (bytes memory data);

    /**
     * @notice Gets the data value for a key at a specific timestamp
     * @param key The data key
     * @param timestamp The timestamp to query
     * @return data The data value at that timestamp
     */
    function getDataAt(bytes32 key, uint256 timestamp) external view returns (bytes memory data);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the liquidity for an account
     * @dev Only callable by the app or LiquidityMatrix contract.
     *      Updates both the app's liquidity tree and propagates to the top-level tree.
     *      Also updates the total liquidity snapshot.
     * @param account The account to update
     * @param liquidity The new liquidity amount (replaces previous value)
     * @return topTreeIndex The index in the top-level liquidity tree
     * @return appTreeIndex The index in the app's liquidity tree
     */
    function updateLiquidity(address account, int256 liquidity)
        external
        returns (uint256 topTreeIndex, uint256 appTreeIndex);

    /**
     * @notice Updates data for a specific key
     * @dev Only callable by the app or LiquidityMatrix contract.
     *      Updates both the app's data tree and propagates to the top-level tree.
     *      Stores the full data value and indexes it by its hash for historical queries.
     * @param key The data key to update
     * @param value The new data value
     * @return topTreeIndex The index in the top-level data tree
     * @return appTreeIndex The index in the app's data tree
     */
    function updateData(bytes32 key, bytes memory value)
        external
        returns (uint256 topTreeIndex, uint256 appTreeIndex);
}
