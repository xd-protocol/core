// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { ISynchronizer } from "./interfaces/ISynchronizer.sol";
import { ArrayLib } from "./libraries/ArrayLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";

contract Settler is ReentrancyGuard {
    address immutable synchronizer;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event VerifyRoot(address indexed app, bytes32 indexed root);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AppNotRegistered();
    error SettlerNotSet();
    error RemoteAppNotSet();
    error InvalidLengths();
    error RootNotReceived();
    error InvalidRoot();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp(address account) {
        (bool registered,,, address settler) = ISynchronizer(synchronizer).getAppSetting(account);
        if (!registered) revert AppNotRegistered();
        if (settler != address(this)) revert SettlerNotSet();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _synchronizer) {
        synchronizer = _synchronizer;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getRemoteAppOrRevert(address app, uint32 eid) internal view returns (address remoteApp) {
        remoteApp = ISynchronizer(synchronizer).getRemoteApp(app, eid);
        if (remoteApp == address(0)) revert RemoteAppNotSet();
    }

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

        bytes32 root = ISynchronizer(synchronizer).getLiquidityRootAt(eid, timestamp);
        _verifyRoot(
            _getRemoteAppOrRevert(app, eid),
            ArrayLib.convertToBytes32(accounts),
            ArrayLib.convertToBytes32(liquidity),
            mainTreeIndex,
            mainTreeProof,
            root
        );
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

        bytes32 root = ISynchronizer(synchronizer).getDataRootAt(eid, timestamp);
        _verifyRoot(
            _getRemoteAppOrRevert(app, eid), keys, ArrayLib.hashElements(values), mainTreeIndex, mainTreeProof, root
        );
        ISynchronizer(synchronizer).settleData(ISynchronizer.SettleDataParams(app, eid, timestamp, keys, values));
    }

    /**
     * @notice Verifies a Merkle tree root for an application and marks it as settled.
     * @param app The address of the application for which the root is being verified.
     * @param keys The array of keys representing the nodes in the application's subtree.
     * @param values The array of values corresponding to the keys in the application's subtree.
     * @param mainTreeIndex the index of application in the main tree on the remote chain.
     * @param mainTreeProof The Merkle proof connecting the application's subtree root to the main tree root.
     * @param mainTreeRoot The expected root of the main Merkle tree.
     *
     * @dev This function:
     * - Constructs the application's subtree root using the given keys and values.
     * - Validates the Merkle proof to ensure the application's subtree is correctly connected to the main tree.
     */
    function _verifyRoot(
        address app,
        bytes32[] memory keys,
        bytes32[] memory values,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        bytes32 mainTreeRoot
    ) internal {
        if (mainTreeRoot == bytes32(0)) revert RootNotReceived();

        // Construct the Merkle tree and verify mainTreeRoot
        bytes32 appRoot = MerkleTreeLib.computeRoot(keys, values);
        bool valid = MerkleTreeLib.verifyProof(
            bytes32(uint256(uint160(app))), appRoot, mainTreeIndex, mainTreeProof, mainTreeRoot
        );
        if (!valid) revert InvalidRoot();

        emit VerifyRoot(app, mainTreeRoot);
    }
}
