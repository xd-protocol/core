// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseSettler } from "./mixins/BaseSettler.sol";
import { ISynchronizer } from "./interfaces/ISynchronizer.sol";

contract SettlerTrusted is BaseSettler {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address account => bool) public isTrusted;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateTrusted(address indexed account, bool isTrusted);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotTrusted();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyTrusted(address account) {
        if (!isTrusted[account]) revert NotTrusted();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _synchronizer) BaseSettler(_synchronizer) { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateTrusted(address account, bool _isTrusted) external {
        isTrusted[account] = _isTrusted;

        emit UpdateTrusted(account, _isTrusted);
    }

    /**
     * @notice Settles liquidity states directly without batching, verifying the proof for the app-tree root.
     * @param app The address of the application on the current chain.
     * @param eid The endpoint ID of the remote chain.
     * @param timestamp The timestamp of the root.
     * @param mainTreeIndex The index of app in the liquidity tree on the remote chain.
     * @param mainTreeProof The proof array to verify the app-root within the main tree.
     * @param accounts The array of accounts to settle.
     * @param liquidity The array of liquidity values corresponding to the accounts.
     * @param appRoot Pre-calculated root for this application derived from `accounts` and `liquidity`.
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
        int256[] calldata liquidity,
        bytes32 appRoot
    ) external nonReentrant onlyApp(app) onlyTrusted(msg.sender) {
        if (accounts.length != liquidity.length) revert InvalidLengths();

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
     * @param appRoot Pre-calculated root for this application derived from `keys` and `values`.
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
        bytes[] calldata values,
        bytes32 appRoot
    ) external nonReentrant onlyApp(app) onlyTrusted(msg.sender) {
        if (keys.length != values.length) revert InvalidLengths();

        bytes32 mainTreeRoot = ISynchronizer(synchronizer).getDataRootAt(eid, timestamp);
        _verifyMainTreeRoot(_getRemoteAppOrRevert(app, eid), appRoot, mainTreeIndex, mainTreeProof, mainTreeRoot);

        ISynchronizer(synchronizer).settleData(ISynchronizer.SettleDataParams(app, eid, timestamp, keys, values));
    }
}
