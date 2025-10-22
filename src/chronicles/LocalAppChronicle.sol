// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ILocalAppChronicle } from "../interfaces/ILocalAppChronicle.sol";
import { ILiquidityMatrix } from "../interfaces/ILiquidityMatrix.sol";
import { ILiquidityMatrixHook } from "../interfaces/ILiquidityMatrixHook.sol";
import { SnapshotsLib } from "../libraries/SnapshotsLib.sol";
import { ArrayLib } from "../libraries/ArrayLib.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { Pausable } from "../mixins/Pausable.sol";

/**
 * @title LocalAppChronicle
 * @notice Manages local application state for a specific version with Merkle tree tracking
 * @dev This contract is deployed by LiquidityMatrix for each app/version combination.
 *      It maintains isolated state including liquidity snapshots, data storage, and Merkle trees.
 *      The chronicle pattern enables blockchain reorganization protection by versioning all state.
 *
 *      Key responsibilities:
 *      - Maintain app-specific liquidity and data Merkle trees
 *      - Track historical snapshots of liquidity and data
 *      - Update top-level trees in LiquidityMatrix when app state changes
 *      - Provide point-in-time queries for all stored data
 *
 *      Access control:
 *      - Only the associated app or LiquidityMatrix can update state
 *      - All view functions are publicly accessible
 *      - Pause control is inherited from LiquidityMatrix owner
 */
contract LocalAppChronicle is Pausable, ILocalAppChronicle {
    using SnapshotsLib for SnapshotsLib.Snapshots;
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using ArrayLib for uint256[];

    /*//////////////////////////////////////////////////////////////
                        ACTION BIT MAPPINGS (1-32)
    //////////////////////////////////////////////////////////////*/

    // Define which bit position corresponds to which action in this contract
    uint8 constant ACTION_UPDATE_LIQUIDITY = 1; // Bit 1: update liquidity for accounts
    uint8 constant ACTION_UPDATE_DATA = 2; // Bit 2: update data key-value pairs
    // Bits 3-32 are available for future use

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The LiquidityMatrix contract that deployed this chronicle
    address public immutable liquidityMatrix;

    /// @notice The application this chronicle serves
    address public immutable app;

    /// @notice The version number this chronicle is associated with
    uint256 public immutable version;

    /// @notice Snapshots of total liquidity across all accounts
    SnapshotsLib.Snapshots internal _totalLiquidity;

    /// @notice Per-account liquidity snapshots
    mapping(address account => SnapshotsLib.Snapshots) internal _liquidity;

    /// @notice Snapshots of data hashes for each key
    mapping(bytes32 key => SnapshotsLib.Snapshots) internal _dataHashes;

    /// @notice Actual data values indexed by key and hash
    mapping(bytes32 key => mapping(bytes32 hash => bytes)) internal _data;

    /// @notice Merkle tree tracking all account liquidity
    MerkleTreeLib.Tree internal _liquidityTree;

    /// @notice Merkle tree tracking all data key-value pairs
    MerkleTreeLib.Tree internal _dataTree;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Restricts access to the associated app or LiquidityMatrix contract
     * @dev Reverts with Forbidden if caller is unauthorized
     */
    modifier onlyAppOrLiquidityMatrix() {
        if (msg.sender != app && msg.sender != liquidityMatrix) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes a new LocalAppChronicle for a specific app and version
     * @dev Deployed by LiquidityMatrix when an app calls addLocalAppChronicle
     * @param _liquidityMatrix The LiquidityMatrix contract address
     * @param _app The application this chronicle will serve
     * @param _version The version number for state isolation
     */
    constructor(address _liquidityMatrix, address _app, uint256 _version) {
        liquidityMatrix = _liquidityMatrix;
        app = _app;
        version = _version;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILocalAppChronicle
    function getLiquidityRoot() external view returns (bytes32) {
        return _liquidityTree.getRoot();
    }

    /// @inheritdoc ILocalAppChronicle
    function getDataRoot() external view returns (bytes32) {
        return _dataTree.getRoot();
    }

    /// @inheritdoc ILocalAppChronicle
    function getTotalLiquidity() external view returns (int256 liquidity) {
        liquidity = _totalLiquidity.getAsInt();
    }

    /// @inheritdoc ILocalAppChronicle
    function getTotalLiquidityAt(uint256 timestamp) external view returns (int256 liquidity) {
        liquidity = _totalLiquidity.getAsInt(timestamp);
    }

    /// @inheritdoc ILocalAppChronicle
    function getLiquidity(address account) external view returns (int256 liquidity) {
        liquidity = _liquidity[account].getAsInt();
    }

    /// @inheritdoc ILocalAppChronicle
    function getLiquidityAt(address account, uint256 timestamp) external view returns (int256 liquidity) {
        liquidity = _liquidity[account].getAsInt(timestamp);
    }

    /// @inheritdoc ILocalAppChronicle
    function getData(bytes32 key) external view returns (bytes memory data) {
        bytes32 hash = _dataHashes[key].get();
        return _data[key][hash];
    }

    /// @inheritdoc ILocalAppChronicle
    function getDataAt(bytes32 key, uint256 timestamp) external view returns (bytes memory data) {
        bytes32 hash = _dataHashes[key].get(timestamp);
        return _data[key][hash];
    }

    /**
     * @notice Internal function to check LiquidityMatrix owner for pause control
     * @dev Required by Pausable contract
     */
    function _requirePauser() internal view override {
        address matrixOwner = ILiquidityMatrix(liquidityMatrix).owner();
        if (msg.sender != matrixOwner) revert Unauthorized();
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILocalAppChronicle
    function updateLiquidity(address account, int256 liquidity)
        external
        override
        onlyAppOrLiquidityMatrix
        whenNotPaused(ACTION_UPDATE_LIQUIDITY)
        returns (uint256 topTreeIndex, uint256 appTreeIndex)
    {
        // Update account liquidity in the tree
        appTreeIndex = _liquidityTree.update(bytes32(uint256(uint160(account))), bytes32(uint256(liquidity)));

        // Calculate new total liquidity
        int256 oldTotalLiquidity = _totalLiquidity.getAsInt();
        int256 oldLiquidity = _liquidity[account].getAsInt();
        _liquidity[account].setAsInt(liquidity);
        int256 newTotalLiquidity = oldTotalLiquidity - oldLiquidity + liquidity;
        _totalLiquidity.setAsInt(newTotalLiquidity);

        // Create composite hash of liquidity tree root and total liquidity
        // This allows future Settler contracts to verify both the Merkle tree AND total liquidity
        bytes32 liquidityTreeRoot = _liquidityTree.getRoot();
        bytes32 compositeRoot = keccak256(abi.encodePacked(liquidityTreeRoot, bytes32(uint256(newTotalLiquidity))));

        // Update top tree with composite root that commits to both individual liquidities and total
        topTreeIndex = ILiquidityMatrix(liquidityMatrix).updateTopLiquidityTree(version, app, compositeRoot);

        emit UpdateLiquidity(topTreeIndex, account, appTreeIndex, uint64(block.timestamp));
    }
    /// @inheritdoc ILocalAppChronicle

    function updateData(bytes32 key, bytes memory value)
        external
        override
        onlyAppOrLiquidityMatrix
        whenNotPaused(ACTION_UPDATE_DATA)
        returns (uint256 topTreeIndex, uint256 appTreeIndex)
    {
        bytes32 hash = keccak256(value);
        appTreeIndex = _dataTree.update(key, hash);
        topTreeIndex = ILiquidityMatrix(liquidityMatrix).updateTopDataTree(version, app, _dataTree.getRoot());

        _dataHashes[key].set(hash);
        _data[key][hash] = value;

        emit UpdateData(topTreeIndex, key, hash, appTreeIndex, uint64(block.timestamp));
    }
}
