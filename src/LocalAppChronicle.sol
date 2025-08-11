// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ILiquidityMatrix } from "./interfaces/ILiquidityMatrix.sol";
import { ILiquidityMatrixHook } from "./interfaces/ILiquidityMatrixHook.sol";
import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";
import { ArrayLib } from "./libraries/ArrayLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";

contract LocalAppChronicle {
    using SnapshotsLib for SnapshotsLib.Snapshots;
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using ArrayLib for uint256[];

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable liquidityMatrix;
    address public immutable app;
    uint256 public immutable version;

    SnapshotsLib.Snapshots internal _totalLiquidity;
    mapping(address account => SnapshotsLib.Snapshots) internal _liquidity;
    mapping(bytes32 key => SnapshotsLib.Snapshots) internal _dataHashes;
    mapping(bytes32 key => mapping(bytes32 hash => bytes)) internal _data;

    MerkleTreeLib.Tree internal _liquidityTree;
    MerkleTreeLib.Tree internal _dataTree;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateLiquidity(
        uint256 topTreeIndex, address indexed account, uint256 appTreeIndex, uint64 indexed timestamp
    );

    event UpdateData(
        uint256 topTreeIndex, bytes32 indexed key, bytes32 hash, uint256 appTreeIndex, uint64 indexed timestamp
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotInitialized();
    error Forbidden();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAppOrLiquidityMatrix() {
        if (msg.sender != app && msg.sender != liquidityMatrix) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _liquidityMatrix, address _app, uint256 _version) {
        liquidityMatrix = _liquidityMatrix;
        app = _app;
        version = _version;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getLiquidityRoot() public view returns (bytes32) {
        return _liquidityTree.root;
    }

    function getDataRoot() public view returns (bytes32) {
        return _dataTree.root;
    }

    function getTotalLiquidity() external view returns (int256 liquidity) {
        liquidity = _totalLiquidity.getAsInt();
    }

    function getTotalLiquidityAt(uint256 timestamp) external view returns (int256 liquidity) {
        liquidity = _totalLiquidity.getAsInt(timestamp);
    }

    function getLiquidity(address account) external view returns (int256 liquidity) {
        liquidity = _liquidity[account].getAsInt();
    }

    function getLiquidityAt(address account, uint256 timestamp) external view returns (int256 liquidity) {
        liquidity = _liquidity[account].getAsInt(timestamp);
    }

    function getData(bytes32 key) external view returns (bytes memory data) {
        bytes32 hash = _dataHashes[key].get();
        return _data[key][hash];
    }

    function getDataAt(bytes32 key, uint256 timestamp) external view returns (bytes memory data) {
        bytes32 hash = _dataHashes[key].get(timestamp);
        return _data[key][hash];
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the liquidity for an account in the calling app
     * @dev Updates the app's liquidity tree and propagates to the top tree
     * @param account The account to update
     * @param liquidity The new liquidity amount
     * @return topTreeIndex The index in the top liquidity tree
     * @return appTreeIndex The index in the app's liquidity tree
     */
    function updateLiquidity(address account, int256 liquidity)
        external
        onlyAppOrLiquidityMatrix
        returns (uint256 topTreeIndex, uint256 appTreeIndex)
    {
        appTreeIndex = _liquidityTree.update(bytes32(uint256(uint160(account))), bytes32(uint256(liquidity)));
        topTreeIndex = ILiquidityMatrix(liquidityMatrix).updateTopLiquidityTree(version, app, _liquidityTree.root);

        int256 oldTotalLiquidity = _totalLiquidity.getAsInt();
        int256 oldLiquidity = _liquidity[account].getAsInt();
        _liquidity[account].setAsInt(liquidity);
        int256 newTotalLiquidity = oldTotalLiquidity - oldLiquidity + liquidity;
        _totalLiquidity.setAsInt(newTotalLiquidity);

        emit UpdateLiquidity(topTreeIndex, account, appTreeIndex, uint64(block.timestamp));
    }
    /**
     * @notice Updates arbitrary data for the calling app
     * @dev Updates the app's data tree and propagates to the top tree
     * @param key The data key
     * @param value The data value
     * @return topTreeIndex The index in the top data tree
     * @return appTreeIndex The index in the app's data tree
     */

    function updateData(bytes32 key, bytes memory value)
        external
        onlyAppOrLiquidityMatrix
        returns (uint256 topTreeIndex, uint256 appTreeIndex)
    {
        bytes32 hash = keccak256(value);
        appTreeIndex = _dataTree.update(key, hash);
        topTreeIndex = ILiquidityMatrix(liquidityMatrix).updateTopDataTree(version, app, _dataTree.root);

        _dataHashes[key].set(hash);
        _data[key][hash] = value;

        emit UpdateData(topTreeIndex, key, hash, appTreeIndex, uint64(block.timestamp));
    }
}
