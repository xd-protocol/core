// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseSettler } from "../mixins/BaseSettler.sol";
import { ISynchronizer } from "../interfaces/ISynchronizer.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";

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

    uint32 internal constant TRAILING_MASK = uint32(0x80000000);
    uint32 internal constant INDEX_MASK = uint32(0x7fffffff);

    mapping(address app => mapping(uint32 eid => State)) internal _states;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event StoreAccount(uint32 indexed index, address indexed accounts);
    event StoreKey(uint32 indexed index, bytes32 indexed key);

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _synchronizer) BaseSettler(_synchronizer) { }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getRemoteAccountAt(address app, uint32 eid, uint256 index) external view returns (address) {
        return _states[app][eid].accounts[index];
    }

    function getRemoteKeyAt(address app, uint32 eid, uint256 index) external view returns (bytes32) {
        return _states[app][eid].keys[index];
    }

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
     * @param accountsData Encoded array of either account index or (index + address).
     * @param liquidity The array of liquidity values corresponding to the accounts.
     */
    function settleLiquidity(
        address app,
        uint32 eid,
        uint256 timestamp,
        uint256 mainTreeIndex,
        bytes32[] calldata mainTreeProof,
        bytes calldata accountsData,
        int256[] calldata liquidity
    ) external nonReentrant onlyApp(app) {
        State storage state = _states[app][eid];

        address[] memory accounts = new address[](liquidity.length);
        uint256 offset;
        for (uint256 i; i < liquidity.length; ++i) {
            // first bit indicates whether an account follows after index and the rest 31 bits represent index
            uint32 _index = uint32(bytes4(accountsData[offset:offset + 4]));
            offset += 4;
            uint32 index = _index & INDEX_MASK;
            if (_index & TRAILING_MASK > 0) {
                accounts[i] = address(bytes20(accountsData[offset:offset + 20]));
                offset += 20;
                state.accounts[index] = accounts[i];
                emit StoreAccount(index, accounts[i]);
            } else {
                accounts[i] = state.accounts[index];
            }
            state.liquidityTree.update(bytes32(uint256(uint160(accounts[i]))), bytes32(uint256(liquidity[i])));
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
     * @param keysData Encoded array of either key index or (index + key).
     * @param values The array of data values corresponding to the keys.
     */
    function settleData(
        address app,
        uint32 eid,
        uint256 timestamp,
        uint256 mainTreeIndex,
        bytes32[] calldata mainTreeProof,
        bytes calldata keysData,
        bytes[] calldata values
    ) external nonReentrant onlyApp(app) {
        State storage state = _states[app][eid];

        bytes32[] memory keys = new bytes32[](values.length);
        uint256 offset;
        for (uint256 i; i < values.length; ++i) {
            // first bit indicates whether a key follows after index and the rest 31 bits represent index
            uint32 _index = uint32(bytes4(keysData[offset:offset + 4]));
            offset += 4;
            uint32 index = _index & INDEX_MASK;
            if (_index & TRAILING_MASK > 0) {
                keys[i] = bytes32(keysData[offset:offset + 32]);
                offset += 32;
                state.keys[index] = keys[i];
                emit StoreKey(index, keys[i]);
            } else {
                keys[i] = state.keys[index];
            }
            state.dataTree.update(keys[i], keccak256(values[i]));
        }

        bytes32 mainTreeRoot = ISynchronizer(synchronizer).getDataRootAt(eid, timestamp);
        _verifyMainTreeRoot(
            _getRemoteAppOrRevert(app, eid), state.dataTree.root, mainTreeIndex, mainTreeProof, mainTreeRoot
        );

        ISynchronizer(synchronizer).settleData(ISynchronizer.SettleDataParams(app, eid, timestamp, keys, values));
    }
}
