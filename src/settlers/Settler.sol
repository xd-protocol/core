// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseSettler } from "../mixins/BaseSettler.sol";
import { ISynchronizer } from "../interfaces/ISynchronizer.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { ArrayLib } from "../libraries/ArrayLib.sol";

contract Settler is BaseSettler {
    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _synchronizer) BaseSettler(_synchronizer) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Settles liquidity states directly without batching, verifying the proof for the app-tree root.
     * @param eid The endpoint ID of the remote chain.
     * @param timestamp The timestamp of the root.
     * @param app The address of the application on the current chain.
     * @param mainTreeIndex the index of app in the liquidity tree on the remote chain.
     * @param mainTreeProof The proof array to verify the app-root within the main tree.
     * @param accounts The array of accounts to settle.
     * @param liquidity The array of liquidity values corresponding to the accounts.
     *
     * Requirements:
     * - The `accounts` and `liquidity` arrays must have the same length.
     */
    function settleLiquidity(
        address app,
        uint32 eid,
        uint256 timestamp,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        address[] calldata accounts,
        int256[] calldata liquidity
    ) external nonReentrant onlyApp(app) {
        if (accounts.length != liquidity.length) revert InvalidLengths();

        bytes32[] memory keys = ArrayLib.convertToBytes32(accounts);
        bytes32[] memory values = ArrayLib.convertToBytes32(liquidity);
        bytes32 appRoot = MerkleTreeLib.computeRoot(keys, values);
        bytes32 mainTreeRoot = ISynchronizer(synchronizer).getLiquidityRootAt(eid, timestamp);
        _verifyMainTreeRoot(_getRemoteAppOrRevert(app, eid), appRoot, mainTreeIndex, mainTreeProof, mainTreeRoot);

        ISynchronizer(synchronizer).settleLiquidity(
            ISynchronizer.SettleLiquidityParams(app, eid, timestamp, accounts, liquidity)
        );
    }

    /**
     * @notice Finalizes data states directly without batching, verifying the proof for the app-tree root.
     * @param eid The endpoint ID of the remote chain.
     * @param timestamp The timestamp of the root.
     * @param app The address of the application on the current chain.
     * @param mainTreeIndex the index of app in the data tree on the remote chain.
     * @param mainTreeProof The proof array to verify the app-root within the main tree.
     * @param keys The array of keys to settle.
     * @param values The array of data values corresponding to the keys.
     *
     * Requirements:
     * - The `keys` and `values` arrays must have the same length.
     */
    function settleData(
        address app,
        uint32 eid,
        uint256 timestamp,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external nonReentrant onlyApp(app) {
        if (keys.length != values.length) revert InvalidLengths();

        bytes32 appRoot = MerkleTreeLib.computeRoot(keys, ArrayLib.hashElements(values));
        bytes32 mainTreeRoot = ISynchronizer(synchronizer).getDataRootAt(eid, timestamp);
        _verifyMainTreeRoot(_getRemoteAppOrRevert(app, eid), appRoot, mainTreeIndex, mainTreeProof, mainTreeRoot);

        ISynchronizer(synchronizer).settleData(ISynchronizer.SettleDataParams(app, eid, timestamp, keys, values));
    }
}
