// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DynamicSparseMerkleTreeLib } from "../libraries/DynamicSparseMerkleTreeLib.sol";
import { ISynchronizerCallbacks } from "../interfaces/ISynchronizerCallbacks.sol";

abstract contract SynchronizerLocal is ReentrancyGuard {
    using DynamicSparseMerkleTreeLib for DynamicSparseMerkleTreeLib.Tree;

    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct AppSetting {
        bool registered;
        bool syncContracts;
        mapping(uint32 eid => mapping(address => address)) accountRedirections;
        mapping(uint32 eid => mapping(address => address)) prevAccountRedirections;
    }

    struct AppState {
        int256 totalLiquidity;
        mapping(address account => int256) liquidities;
        DynamicSparseMerkleTreeLib.Tree liquidityTree;
        mapping(bytes32 key => bytes32) dataHashes;
        DynamicSparseMerkleTreeLib.Tree dataTree;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant TOP_TREE_HEIGHT = 32;
    uint256 internal constant LIQUIDITY_TREE_HEIGHT = 160;
    uint256 internal constant DATA_TREE_HEIGHT = 256;

    mapping(address app => AppSetting) internal _appSettings;
    mapping(address app => AppState) internal _appStates;
    DynamicSparseMerkleTreeLib.Tree internal _topLiquidityTree;
    DynamicSparseMerkleTreeLib.Tree internal _topDataTree;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(address indexed app);
    event UpdateLiquidity(address indexed app, address indexed account, int256 liquidity, uint256 indexed timestamp);
    event UpdateData(address indexed app, bytes32 indexed key, bytes value, bytes32 hash, uint256 indexed timestamp);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AppNotRegistered();
    error NotContract();
    error AlreadyRegistered();
    error ValueSizeTooBig();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp(address account) {
        if (!_appSettings[account].registered) revert AppNotRegistered();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _topLiquidityTree.initialize(TOP_TREE_HEIGHT);
        _topDataTree.initialize(TOP_TREE_HEIGHT);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the registration and synchronization settings for an application.
     * @param app The address of the application.
     * @return registered A boolean indicating whether the application is registered.
     * @return syncContracts A boolean indicating whether contract synchronization is enabled.
     */
    function getAppSetting(address app) external view returns (bool registered, bool syncContracts) {
        AppSetting storage setting = _appSettings[app];
        return (setting.registered, setting.syncContracts);
    }

    /**
     * @notice Retrieves the roots of the top-level liquidity and data Merkle trees.
     * @return liquidityRoot The root of the top liquidity tree.
     * @return dataRoot The root of the top data tree.
     * @return timestamp The current block timestamp.
     */
    function getTopTreeRoots() external view returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) {
        return (_topLiquidityTree.root, _topDataTree.root, block.timestamp);
    }

    /**
     * @notice Retrieves the total liquidity for an application.
     * @param app The address of the application.
     * @return liquidity The total liquidity of the application.
     */
    function getTotalLiquidity(address app) public view returns (int256 liquidity) {
        return _appStates[app].totalLiquidity;
    }

    /**
     * @notice Retrieves the liquidity of a specific account for an application.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @return liquidity The liquidity of the specified account.
     */
    function getLiquidity(address app, address account) public view returns (int256 liquidity) {
        return _appStates[app].liquidities[account];
    }

    /**
     * @notice Retrieves the hashed data associated with a specific key in an application's data tree.
     * @param app The address of the application.
     * @param key The key whose associated data is being queried.
     * @return hash The hashed data associated with the specified key.
     */
    function getDataHash(address app, bytes32 key) public view returns (bytes32 hash) {
        return _appStates[app].dataHashes[key];
    }

    /**
     * @notice Utility function to check if an address is a contract.
     * @param account The address to check.
     * @return True if the address is a contract, false otherwise.
     */
    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new application, initializing its liquidity and data trees.
     * @param syncContracts A boolean indicating whether contract accounts should be synchronized.
     *
     * Requirements:
     * - Caller must be a contract.
     * - App must not already be registered.
     */
    function registerApp(bool syncContracts) external {
        if (!_isContract(msg.sender)) revert NotContract();

        AppSetting storage appSetting = _appSettings[msg.sender];
        if (appSetting.registered) revert AlreadyRegistered();

        appSetting.registered = true;
        appSetting.syncContracts = syncContracts;

        _appStates[msg.sender].liquidityTree.initialize(LIQUIDITY_TREE_HEIGHT);
        _appStates[msg.sender].dataTree.initialize(DATA_TREE_HEIGHT);

        emit RegisterApp(msg.sender);
    }

    /**
     * @notice Updates the `syncContracts` flag for the application.
     * @param syncContracts A boolean indicating whether to enable or disable contract synchronization.
     *
     * Requirements:
     * - Caller must be a registered application.
     */
    function updateSyncContracts(bool syncContracts) external onlyApp(msg.sender) {
        AppSetting storage appSetting = _appSettings[msg.sender];
        appSetting.syncContracts = syncContracts;
    }

    /**
     * @notice Updates the account redirection settings for a specific external ID (`eid`).
     *         Allows an application to map a remote account to a local account for synchronization purposes.
     * @param eid The external ID associated with the remote account.
     * @param remote The address of the remote account.
     * @param local The address of the local account to map to.
     *
     * Requirements:
     * - Caller must be a registered application.
     */
    function updateAccountRedirection(uint32 eid, address remote, address local) external onlyApp(msg.sender) {
        AppSetting storage appSetting = _appSettings[msg.sender];
        appSetting.prevAccountRedirections[eid][remote] = appSetting.accountRedirections[eid][remote];
        appSetting.accountRedirections[eid][remote] = local;
    }

    /**
     * @notice Updates the liquidity for a specific account and propagates the changes to the top-level tree.
     * @param account The account whose liquidity is being updated.
     * @param liquidity The new liquidity value for the account.
     */
    function updateLiquidity(address account, int256 liquidity) external onlyApp(msg.sender) {
        AppState storage state = _appStates[msg.sender];

        int256 prevLiquidity = state.liquidities[account];
        state.liquidities[account] = liquidity;
        state.totalLiquidity += (liquidity - prevLiquidity);

        state.liquidityTree.updateNode(bytes32(uint256(uint160(account))), bytes32(uint256(liquidity)));
        _topLiquidityTree.updateNode(bytes32(uint256(uint160(msg.sender))), state.liquidityTree.root);

        emit UpdateLiquidity(msg.sender, account, liquidity, block.timestamp);
    }

    /**
     * @notice Updates the data for a specific key in an app's data tree and propagates the changes to the top-level tree.
     * @param key The key whose associated data is being updated.
     * @param value The new value to associate with the key.
     */
    function updateData(bytes32 key, bytes memory value) external onlyApp(msg.sender) {
        if (value.length > 256) revert ValueSizeTooBig();

        AppState storage state = _appStates[msg.sender];

        bytes32 hash = keccak256(value);
        state.dataHashes[key] = hash;

        state.dataTree.updateNode(key, hash);
        _topDataTree.updateNode(bytes32(uint256(uint160(msg.sender))), state.dataTree.root);

        emit UpdateData(msg.sender, key, value, hash, block.timestamp);
    }
}
