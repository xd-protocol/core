// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseSettler } from "../mixins/BaseSettler.sol";
import { ISynchronizer } from "../interfaces/ISynchronizer.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { ArrayLib } from "../libraries/ArrayLib.sol";

contract Settler is BaseSettler {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    struct State {
        mapping(uint256 index => address) accounts;
        MerkleTreeLib.Tree liquidityTree;
        mapping(uint256 index => bytes32) keys;
        MerkleTreeLib.Tree dataTree;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address app => mapping(uint32 eid => State)) internal _states;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _synchronizer) BaseSettler(_synchronizer) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Settles liquidity states directly without batching, verifying the proof for the app-tree root.
     * @param app The address of the application on the current chain.
     * @param eid The endpoint ID of the remote chain.
     * @param timestamp The timestamp of the root.
     * @param mainTreeIndex the index of app in the liquidity tree on the remote chain.
     * @param mainTreeProof The proof array to verify the app-root within the main tree.
     * @param accountIndices The array of accountIndices of accounts in the app tree that were already settled before.
     * @param newAccounts The array of new accounts that weren't settled.
     * @param liquidity The array of liquidity values corresponding to the accounts.
     */
    function settleLiquidity(
        address app,
        uint32 eid,
        uint256 timestamp,
        uint256 mainTreeIndex,
        bytes32[] calldata mainTreeProof,
        uint256[] calldata accountIndices,
        address[] calldata newAccounts,
        int256[] calldata liquidity
    ) external nonReentrant onlyApp(app) {
        uint256 accountLength = accountIndices.length + newAccounts.length;
        if (accountLength != liquidity.length) revert InvalidLengths();

        State storage state = _states[app][eid];

        address[] memory accounts = new address[](accountLength);
        for (uint256 i; i < accountIndices.length; ++i) {
            uint256 index = accountIndices[i];
            accounts[i] = state.accounts[index];
            state.liquidityTree.updateAt(bytes32(uint256(uint160(accounts[i]))), bytes32(uint256(liquidity[i])), index);
        }
        uint256 treeSize = state.liquidityTree.size;
        for (uint256 i; i < newAccounts.length; ++i) {
            uint256 index = treeSize + i;
            accounts[accountIndices.length + i] = newAccounts[i];
            state.accounts[index] = newAccounts[i];
            state.liquidityTree.updateAt(
                bytes32(uint256(uint160(newAccounts[i]))), bytes32(uint256(liquidity[i])), index
            );
        }

        _verifyMainTreeRoot(
            _getRemoteAppOrRevert(app, eid),
            state.liquidityTree.root,
            mainTreeIndex,
            mainTreeProof,
            ISynchronizer(synchronizer).getLiquidityRootAt(eid, timestamp)
        );

        ISynchronizer(synchronizer).settleLiquidity(
            ISynchronizer.SettleLiquidityParams(app, eid, timestamp, accounts, liquidity)
        );
    }

    /**
     * @notice Finalizes data states directly without batching, verifying the proof for the app-tree root.
     * @param app The address of the application on the current chain.
     * @param eid The endpoint ID of the remote chain.
     * @param timestamp The timestamp of the root.
     * @param mainTreeIndex the index of app in the data tree on the remote chain.
     * @param mainTreeProof The proof array to verify the app-root within the main tree.
     * @param keyIndices The array of indices of the values in the app tree that were settled before.
     * @param newKeys The array of new keys that weren't settled before.
     * @param values The array of data values corresponding to the keys.
     */
    function settleData(
        address app,
        uint32 eid,
        uint256 timestamp,
        uint256 mainTreeIndex,
        bytes32[] calldata mainTreeProof,
        uint256[] calldata keyIndices,
        bytes32[] calldata newKeys,
        bytes[] calldata values
    ) external nonReentrant onlyApp(app) {
        uint256 keyLength = keyIndices.length + newKeys.length;
        if (keyLength != values.length) revert InvalidLengths();

        State storage state = _states[app][eid];

        bytes32[] memory keys = new bytes32[](keyLength);
        for (uint256 i; i < keyIndices.length; ++i) {
            uint256 index = keyIndices[i];
            keys[i] = state.keys[index];
            state.dataTree.updateAt(keys[i], keccak256(values[i]), index);
        }
        uint256 treeSize = state.dataTree.size;
        for (uint256 i; i < newKeys.length; ++i) {
            uint256 index = treeSize + i;
            keys[keyIndices.length + i] = newKeys[i];
            state.keys[index] = newKeys[i];
            state.dataTree.updateAt(newKeys[i], keccak256(values[i]), index);
        }

        bytes32 mainTreeRoot = ISynchronizer(synchronizer).getDataRootAt(eid, timestamp);
        _verifyMainTreeRoot(
            _getRemoteAppOrRevert(app, eid), state.dataTree.root, mainTreeIndex, mainTreeProof, mainTreeRoot
        );

        ISynchronizer(synchronizer).settleData(ISynchronizer.SettleDataParams(app, eid, timestamp, keys, values));
    }
}
