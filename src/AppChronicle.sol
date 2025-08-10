// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";

contract AppChronicle {
    using SnapshotsLib for SnapshotsLib.Snapshots;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    SnapshotsLib.Snapshots _totalLiquidity;
    mapping(address account => SnapshotsLib.Snapshots) _liquidity;
    MerkleTreeLib.Tree _liquidityTree;
    mapping(bytes32 key => SnapshotsLib.Snapshots) _dataHashes;
    MerkleTreeLib.Tree _dataTree;
}
