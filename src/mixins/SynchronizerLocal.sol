// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { SnapshotsLib } from "../libraries/SnapshotsLib.sol";

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
abstract contract SynchronizerLocal is ReentrancyGuard {
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
        mapping(address account => SnapshotsLib.Snapshots) liquidities;
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
    mapping(uint256 timestamp => bytes32) internal _mainLiquidityRoots;
    mapping(uint256 timestamp => bytes32) internal _mainDataRoots;
    uint256[] internal _updateTimestamps;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(address indexed app);
    event UpdateLiquidity(
        address indexed app,
        uint256 appIndex,
        address indexed account,
        int256 liquidity,
        uint256 treeIndex,
        uint256 indexed timestamp
    );
    event UpdateData(
        address indexed app,
        uint256 appIndex,
        bytes32 indexed key,
        bytes value,
        bytes32 hash,
        uint256 treeIndex,
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
     * @param eid The endpoint ID of the remote chain associated with the account mapping.
     * @param app The address of the application that owns the mapping.
     * @param remote The address of the remote account.
     * @return local The address of the corresponding local account, or `address(0)` if no mapping exists.
     */
    function getLocalAccount(uint32 eid, address app, address remote) public view returns (address local) {
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
        return _appStates[app].liquidities[account].getLastAsInt();
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
        return _appStates[app].liquidities[account].getAsInt(timestamp);
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
     * @notice Retrieves the roots of the main liquidity and data trees on current chain.
     * @dev This will be called by lzRead from remote chains.
     * @return liquidityRoot The root of the main liquidity tree.
     * @return dataRoot The root of the main data tree.
     * @return timestamp The current block timestamp.
     */
    function getFinalizedMainRoots() public view returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) {
        if (_updateTimestamps.length == 0) {
            return (bytes32(0), bytes32(0), 0);
        }
        for (uint256 i; i < 2; ++i) {
            uint256 ts = _updateTimestamps[_updateTimestamps.length - i - 1];
            if (ts < block.timestamp) {
                return (_mainLiquidityRoots[ts], _mainDataRoots[ts], ts);
            }
        }
        return (bytes32(0), bytes32(0), 0);
    }

    /**
     * @notice Retrieves the roots of the main liquidity and data trees on current chain at timestamp.
     * @dev This will be called by lzRead from remote chains.
     * @return liquidityRoot The root of the main liquidity tree.
     * @return dataRoot The root of the main data tree.
     * @return timestamp The current block timestamp.
     */
    function getMainRootsAt(uint256 ts)
        public
        view
        returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp)
    {
        return (_mainLiquidityRoots[ts], _mainDataRoots[ts], ts);
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
     * @notice Updates the liquidity for a specific account and propagates the changes to the main tree.
     * @param account The account whose liquidity is being updated.
     * @param liquidity The new liquidity value for the account.
     */
    function updateLiquidity(address account, int256 liquidity) external onlyApp(msg.sender) {
        _finalizeRoots();

        AppState storage state = _appStates[msg.sender];

        int256 prevLiquidity = state.liquidities[account].getLastAsInt();
        // optimization
        if (liquidity != prevLiquidity) {
            state.liquidities[account].appendAsInt(liquidity);
            int256 prevTotalLiquidity = state.totalLiquidity.getLastAsInt();
            state.totalLiquidity.appendAsInt(prevTotalLiquidity + liquidity - prevLiquidity);

            uint256 treeIndex =
                state.liquidityTree.update(bytes32(uint256(uint160(account))), bytes32(uint256(liquidity)));
            uint256 appIndex =
                _mainLiquidityTree.update(bytes32(uint256(uint160(msg.sender))), state.liquidityTree.root);

            emit UpdateLiquidity(msg.sender, appIndex, account, liquidity, treeIndex, block.timestamp);
        }
    }

    /**
     * @notice Finalizes roots of the main liquidity and data trees on current chain and retrieves the them.
     * @dev This will be called by lzRead from remote chains.
     * @return liquidityRoot The root of the main liquidity tree.
     * @return dataRoot The root of the main data tree.
     * @return timestamp The current block timestamp.
     */
    function finalizeAndGetMainRoots() external returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) {
        return getMainRootsAt(_finalizeRoots());
    }

    /**
     * @notice Updates the data for a specific key in an app's data tree and propagates the changes to the main tree.
     * @param key The key whose associated data is being updated.
     * @param value The new value to associate with the key.
     */
    function updateData(bytes32 key, bytes memory value) external onlyApp(msg.sender) {
        if (value.length > MAX_DATA_SIZE) revert DataTooLarge();

        _finalizeRoots();

        AppState storage state = _appStates[msg.sender];

        bytes32 hash = keccak256(value);
        bytes32 prevHash = state.dataHashes[key].getLast();
        // optimization
        if (hash != prevHash) {
            state.dataHashes[key].append(hash);

            uint256 treeIndex = state.dataTree.update(key, hash);
            uint256 appIndex = _mainDataTree.update(bytes32(uint256(uint160(msg.sender))), state.dataTree.root);

            emit UpdateData(msg.sender, appIndex, key, value, hash, treeIndex, block.timestamp);
        }
    }

    function _finalizeRoots() internal returns (uint256 finalizedTimestamp) {
        if (_updateTimestamps.length == 0) {
            _updateTimestamps.push(block.timestamp);
            return 0;
        }

        uint256 lastTimestamp = _updateTimestamps[_updateTimestamps.length - 1];
        if (lastTimestamp < block.timestamp) {
            _updateTimestamps.push(block.timestamp);
            _mainLiquidityRoots[lastTimestamp] = _mainLiquidityTree.root;
            _mainDataRoots[lastTimestamp] = _mainDataTree.root;
            return lastTimestamp;
        }

        return _updateTimestamps.length > 1 ? _updateTimestamps[_updateTimestamps.length - 2] : 0;
    }
}
