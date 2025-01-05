// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { SnapshotsLib } from "../libraries/SnapshotsLib.sol";
import { ISynchronizer } from "../interfaces/ISynchronizer.sol";

/**
 * @title SynchronizerLocal
 * @dev A contract managing hierarchical Merkle trees to track and synchronize liquidity and data updates across applications.
 *
 * ## Architecture Overview:
 *
 * This contract maintains two main Merkle trees:
 * - **Main Liquidity Tree**: Tracks liquidity data for all registered applications.
 * - **Main Data Tree**: Tracks arbitrary key-value data for all registered applications.
 *
 * Each application maintains its own pair of Merkle trees:
 * - **Liquidity Tree**: Tracks account-specific liquidity data within the application.
 * - **Data Tree**: Tracks key-value pairs specific to the application.
 *
 * ## Relationship Between Main and App Trees:
 *
 * The roots of application-specific trees (liquidity and data) are added as nodes to their respective main trees.
 * This hierarchical structure allows efficient propagation of changes:
 * - When an application's liquidity or data tree is updated, its root is recalculated.
 * - The new root is propagated to the corresponding main tree, ensuring global consistency.
 *
 * ## ASCII Diagram:
 *
 *                         +--------------------------+
 *                         |    Main Liquidity Tree   |
 *                         |--------------------------|
 *                         |          Root            |
 *                         +--------------------------+
 *                                   |
 *               -------------------------------------------------
 *               |                               |               |
 *   +------------------------+   +------------------------+   +------------------------+
 *   | App A Liquidity Tree   |   | App B Liquidity Tree   |   | App C Liquidity Tree   |
 *   |------------------------|   |------------------------|   |------------------------|
 *   |          Root          |   |          Root          |   |          Root          |
 *   |------------------------|   |------------------------|   |------------------------|
 *   | + Node(Account X)      |   | + Node(Account Z)      |   | + Node(Account Y)      |
 *   | + Node(Account Y)      |   | + Node(Account W)      |   | + Node(Account Z)      |
 *   +------------------------+   +------------------------+   +------------------------+
 *
 *                         +--------------------------+
 *                         |     Main Data Tree       |
 *                         |--------------------------|
 *                         |          Root            |
 *                         +--------------------------+
 *                                   |
 *               -------------------------------------------------
 *               |                               |               |
 *   +------------------------+   +------------------------+   +------------------------+
 *   | App A Data Tree        |   | App B Data Tree        |   | App C Data Tree        |
 *   |------------------------|   |------------------------|   |------------------------|
 *   |          Root          |   |          Root          |   |          Root          |
 *   |------------------------|   |------------------------|   |------------------------|
 *   | + Node(Key 1)          |   | + Node(Key A)          |   | + Node(Key X)          |
 *   | + Node(Key 2)          |   | + Node(Key B)          |   | + Node(Key Y)          |
 *   +------------------------+   +------------------------+   +------------------------+
 *
 * ## Key Functionalities:
 *
 * 1. **App Registration**:
 *    - Applications must register to start using the contract.
 *    - During registration, their individual liquidity and data trees are initialized.
 *
 * 2. **Updating Liquidity**:
 *    - Liquidity updates are recorded in the app's liquidity tree.
 *    - The new liquidity tree root is propagated to the main liquidity tree.
 *
 * 3. **Updating Data**:
 *    - Key-value data updates are recorded in the app's data tree.
 *    - The new data tree root is propagated to the main data tree.
 *
 * 4. **Tree Root Retrieval**:
 *    - Allows querying of the current roots of the main liquidity and data trees.
 *    - Enables synchronization across chains or with off-chain systems.
 */
abstract contract SynchronizerLocal is ReentrancyGuard, ISynchronizer {
    using AddressLib for address;
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using SnapshotsLib for SnapshotsLib.Snapshots;

    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct AppState {
        bool registered;
        bool syncContracts;
        mapping(uint32 eid => mapping(address remote => address local)) accountsRemoteToLocal;
        SnapshotsLib.Snapshots totalLiquidity;
        mapping(address account => SnapshotsLib.Snapshots) liquidity;
        MerkleTreeLib.Tree liquidityTree;
        mapping(bytes32 key => SnapshotsLib.Snapshots) dataHashes;
        MerkleTreeLib.Tree dataTree;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant MAX_DATA_SIZE = 256;

    mapping(address app => AppState) internal _appStates;
    MerkleTreeLib.Tree internal _mainLiquidityTree;
    MerkleTreeLib.Tree internal _mainDataTree;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(address indexed app);
    event UpdateLocalLiquidity(
        address indexed app,
        uint256 mainTreeIndex,
        address indexed account,
        int256 liquidity,
        uint256 appTreeIndex,
        uint256 indexed timestamp
    );
    event UpdateLocalData(
        address indexed app,
        uint256 mainTreeIndex,
        bytes32 indexed key,
        bytes value,
        bytes32 hash,
        uint256 appTreeIndex,
        uint256 indexed timestamp
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AppNotRegistered();
    error NotContract();
    error AlreadyRegistered();
    error DataTooLarge();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp(address account) {
        if (!_appStates[account].registered) revert AppNotRegistered();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _mainLiquidityTree.initialize();
        _mainDataTree.initialize();
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
        AppState storage state = _appStates[app];
        return (state.registered, state.syncContracts);
    }

    /**
     * @notice Retrieves the local account address mapped to a given remote account for an application from a specific chain.
     * @param app The address of the application that owns the mapping.
     * @param eid The endpoint ID of the remote chain associated with the account mapping.
     * @param remote The address of the remote account.
     * @return local The address of the corresponding local account, or `address(0)` if no mapping exists.
     */
    function getLocalAccount(address app, uint32 eid, address remote) public view returns (address local) {
        local = _appStates[app].accountsRemoteToLocal[eid][remote];
        return local == address(0) ? remote : local;
    }

    /**
     * @notice Retrieves the total liquidity for an application on current chain.
     * @param app The address of the application.
     * @return liquidity The total liquidity of the application.
     */
    function getLocalTotalLiquidity(address app) public view returns (int256 liquidity) {
        return _appStates[app].totalLiquidity.getLastAsInt();
    }

    /**
     * @notice Retrieves the total liquidity for an application on current chain.
     * @param app The address of the application.
     * @param timestamp The timestamp to query liquidity at.
     * @return liquidity The total liquidity of the application.
     */
    function getLocalTotalLiquidityAt(address app, uint256 timestamp) public view returns (int256 liquidity) {
        return _appStates[app].totalLiquidity.getAsInt(timestamp);
    }

    /**
     * @notice Retrieves the liquidity of a specific account for an application on current chain.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @return liquidity The liquidity of the specified account.
     */
    function getLocalLiquidity(address app, address account) public view returns (int256 liquidity) {
        return _appStates[app].liquidity[account].getLastAsInt();
    }

    /**
     * @notice Retrieves the liquidity of a specific account for an application on current chain.
     * @param app The address of the application.
     * @param account The account whose liquidity is being queried.
     * @param timestamp The timestamp to query liquidity at.
     * @return liquidity The liquidity of the specified account.
     */
    function getLocalLiquidityAt(address app, address account, uint256 timestamp)
        public
        view
        returns (int256 liquidity)
    {
        return _appStates[app].liquidity[account].getAsInt(timestamp);
    }

    /**
     * @notice Retrieves the hashed data associated with a specific key in an application's data tree on current chain.
     * @param app The address of the application.
     * @param key The key whose associated data is being queried.
     * @return hash The hashed data associated with the specified key.
     */
    function getLocalDataHash(address app, bytes32 key) public view returns (bytes32 hash) {
        return _appStates[app].dataHashes[key].getLast();
    }

    /**
     * @notice Retrieves the hashed data associated with a specific key in an application's data tree on current chain.
     * @param app The address of the application.
     * @param key The key whose associated data is being queried.
     * @param timestamp The timestamp to query liquidity at.
     * @return hash The hashed data associated with the specified key.
     */
    function getLocalDataHashAt(address app, bytes32 key, uint256 timestamp) public view returns (bytes32 hash) {
        return _appStates[app].dataHashes[key].get(timestamp);
    }

    /**
     * @notice Retrieves the Merkle root of the liquidity tree for a specific application.
     * @param app The address of the application whose liquidity root is being queried.
     * @return The current Merkle root of the application's liquidity tree.
     */
    function getLocalLiquidityRoot(address app) public view returns (bytes32) {
        return _appStates[app].liquidityTree.root;
    }

    /**
     * @notice Retrieves the Merkle root of the data tree for a specific application.
     * @param app The address of the application whose data root is being queried.
     * @return The current Merkle root of the application's data tree.
     */
    function getLocalDataRoot(address app) public view returns (bytes32) {
        return _appStates[app].dataTree.root;
    }

    /**
     * @notice Retrieves the roots of the main liquidity and data trees on current chain.
     * @dev This will be called by lzRead from remote chains.
     * @return liquidityRoot The root of the main liquidity tree.
     * @return dataRoot The root of the main data tree.
     * @return timestamp The current block timestamp.
     */
    function getMainRoots() public view returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) {
        return (getMainLiquidityRoot(), getMainDataRoot(), block.timestamp);
    }

    /**
     * @notice Retrieves the Merkle root of the main liquidity tree on the current chain.
     * @return The current Merkle root of the main liquidity tree.
     */
    function getMainLiquidityRoot() public view returns (bytes32) {
        return _mainLiquidityTree.root;
    }

    /**
     * @notice Retrieves the Merkle root of the main data tree on the current chain.
     * @return The current Merkle root of the main data tree.
     */
    function getMainDataRoot() public view returns (bytes32) {
        return _mainDataTree.root;
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
        if (!msg.sender.isContract()) revert NotContract();

        AppState storage state = _appStates[msg.sender];
        if (state.registered) revert AlreadyRegistered();

        state.registered = true;
        state.syncContracts = syncContracts;

        state.liquidityTree.initialize();
        state.dataTree.initialize();

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
        _appStates[msg.sender].syncContracts = syncContracts;
    }

    /**
     * @notice Updates local liquidity for a specific account and propagates the changes to the main tree.
     * @param account The account whose liquidity is being updated.
     * @param liquidity The new liquidity value for the account.
     * @return mainTreeIndex the index of app in the main tree.
     * @return appTreeIndex the index of account in the app tree.
     */
    function updateLocalLiquidity(address account, int256 liquidity)
        external
        onlyApp(msg.sender)
        returns (uint256 mainTreeIndex, uint256 appTreeIndex)
    {
        address app = msg.sender;
        AppState storage state = _appStates[app];

        appTreeIndex = state.liquidityTree.update(bytes32(uint256(uint160(account))), bytes32(uint256(liquidity)));
        mainTreeIndex = _mainLiquidityTree.update(bytes32(uint256(uint160(app))), state.liquidityTree.root);

        int256 prevLiquidity = state.liquidity[account].getLastAsInt();
        // optimization
        if (liquidity != prevLiquidity) {
            state.liquidity[account].appendAsInt(liquidity);
            int256 prevTotalLiquidity = state.totalLiquidity.getLastAsInt();
            state.totalLiquidity.appendAsInt(prevTotalLiquidity + liquidity - prevLiquidity);
        }

        emit UpdateLocalLiquidity(app, mainTreeIndex, account, liquidity, appTreeIndex, block.timestamp);
    }

    /**
     * @notice Updates local data for a specific key in an app's data tree and propagates the changes to the main tree.
     * @param key The key whose associated data is being updated.
     * @param value The new value to associate with the key.
     * @return mainTreeIndex the index of app in the main tree.
     * @return appTreeIndex the index of account in the app tree.
     */
    function updateLocalData(bytes32 key, bytes memory value)
        external
        onlyApp(msg.sender)
        returns (uint256 mainTreeIndex, uint256 appTreeIndex)
    {
        if (value.length > MAX_DATA_SIZE) revert DataTooLarge();

        address app = msg.sender;
        AppState storage state = _appStates[app];

        bytes32 hash = keccak256(value);
        appTreeIndex = state.dataTree.update(key, hash);
        mainTreeIndex = _mainDataTree.update(bytes32(uint256(uint160(app))), state.dataTree.root);

        bytes32 prevHash = state.dataHashes[key].getLast();
        // optimization
        if (hash != prevHash) {
            state.dataHashes[key].append(hash);
        }

        emit UpdateLocalData(app, mainTreeIndex, key, value, hash, appTreeIndex, block.timestamp);
    }
}
