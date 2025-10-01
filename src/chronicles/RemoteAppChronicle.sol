// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IRemoteAppChronicle } from "../interfaces/IRemoteAppChronicle.sol";
import { ILiquidityMatrix } from "../interfaces/ILiquidityMatrix.sol";
import { ILiquidityMatrixHook } from "../interfaces/ILiquidityMatrixHook.sol";
import { SnapshotsLib } from "../libraries/SnapshotsLib.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";
import { ArrayLib } from "../libraries/ArrayLib.sol";
import { Pausable } from "../mixins/Pausable.sol";

/**
 * @title RemoteAppChronicle
 * @notice Manages settled state from remote chains for a specific app/chain/version combination
 * @dev This contract is deployed by LiquidityMatrix for each app/chain/version combination.
 *      It stores liquidity and data settlements from remote chains, maintaining historical
 *      snapshots for time-travel queries. The chronicle pattern enables blockchain reorganization
 *      protection by isolating state across versions.
 *
 *      Key responsibilities:
 *      - Store settled liquidity from remote chains with account mapping support
 *      - Store settled arbitrary data from remote chains
 *      - Track finalization status when both liquidity and data are settled
 *      - Trigger optional hooks for the application on settlement events
 *
 *      Access control:
 *      - Only the app's designated settler can write state
 *      - All view functions are publicly accessible
 *      - Pause control is inherited from LiquidityMatrix owner
 *
 *      Settlement flow:
 *      1. Settler calls settleLiquidity with account balances from remote chain
 *      2. Settler calls settleData with key-value data from remote chain
 *      3. When both are settled for same timestamp, state becomes finalized
 *      4. Optional hooks notify the app of settlement events
 */
contract RemoteAppChronicle is IRemoteAppChronicle, Pausable {
    using SnapshotsLib for SnapshotsLib.Snapshots;

    /*//////////////////////////////////////////////////////////////
                        ACTION BIT MAPPINGS (1-32)
    //////////////////////////////////////////////////////////////*/

    // Define which bit position corresponds to which action in this contract
    uint8 constant ACTION_SETTLE_LIQUIDITY = 1; // Bit 1: settle liquidity from remote chains
    uint8 constant ACTION_SETTLE_DATA = 2; // Bit 2: settle data from remote chains
    // Bits 3-32 are available for future use

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRemoteAppChronicle
    address public immutable liquidityMatrix;

    /// @inheritdoc IRemoteAppChronicle
    address public immutable app;

    /// @inheritdoc IRemoteAppChronicle
    bytes32 public immutable chainUID;

    /// @inheritdoc IRemoteAppChronicle
    uint256 public immutable version;

    SnapshotsLib.Snapshots internal _totalLiquidity;
    mapping(address account => SnapshotsLib.Snapshots) internal _liquidity;
    mapping(bytes32 key => SnapshotsLib.Snapshots) internal _dataHashes;
    mapping(bytes32 key => mapping(bytes32 hash => bytes)) internal _data;

    /// @inheritdoc IRemoteAppChronicle
    mapping(uint64 timestamp => bool) public isLiquiditySettled;

    /// @inheritdoc IRemoteAppChronicle
    mapping(uint64 timestamp => bool) public isDataSettled;

    // Simple arrays for chronological timestamp tracking (uint256 for ArrayLib compatibility)
    uint256[] internal _settledLiquidityTimestamps;
    uint256[] internal _settledDataTimestamps;
    uint256[] internal _finalizedTimestamps;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a liquidity settlement hook fails
     * @param timestamp The timestamp of the settlement
     * @param account The account that failed to process
     * @param liquidity The liquidity value that failed to process
     * @param reason The error reason from the failed hook call
     */
    event OnSettleLiquidityFailure(uint64 indexed timestamp, address indexed account, int256 liquidity, bytes reason);

    /**
     * @notice Emitted when a total liquidity settlement hook fails
     * @param timestamp The timestamp of the settlement
     * @param totalLiquidity The total liquidity value that failed to process
     * @param reason The error reason from the failed hook call
     */
    event OnSettleTotalLiquidityFailure(uint64 indexed timestamp, int256 totalLiquidity, bytes reason);

    /**
     * @notice Emitted when a data settlement hook fails
     * @param timestamp The timestamp of the settlement
     * @param key The data key that failed to process
     * @param value The data value that failed to process
     * @param reason The error reason from the failed hook call
     */
    event OnSettleDataFailure(uint64 indexed timestamp, bytes32 indexed key, bytes value, bytes reason);

    /**
     * @notice Emitted when liquidity is successfully settled
     * @param timestamp The timestamp of the settled state
     */
    event SettleLiquidity(uint64 indexed timestamp, bytes32 indexed liquidityRoot);

    /**
     * @notice Emitted when data is successfully settled
     * @param timestamp The timestamp of the settled state
     */
    event SettleData(uint64 indexed timestamp, bytes32 indexed dataRoot);

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Parameters for settling liquidity from a remote chain
     * @param timestamp The timestamp of the remote state being settled
     * @param accounts Array of account addresses
     * @param liquidity Array of liquidity values corresponding to accounts
     * @param totalLiquidity The total liquidity across all accounts on the remote chain
     * @param liquidityRoot The root of this app's liquidity tree on the remote chain
     * @param proof Merkle proof that the app's root is in the remote top tree
     */
    struct SettleLiquidityParams {
        uint64 timestamp;
        address[] accounts;
        int256[] liquidity;
        int256 totalLiquidity;
        bytes32 liquidityRoot;
        bytes32[] proof;
    }

    /**
     * @notice Parameters for settling data from a remote chain
     * @param timestamp The timestamp of the remote state being settled
     * @param keys Array of data keys
     * @param values Array of data values corresponding to keys
     * @param dataRoot The root of this app's data tree on the remote chain
     * @param proof Merkle proof that the app's root is in the remote top tree
     */
    struct SettleDataParams {
        uint64 timestamp;
        bytes32[] keys;
        bytes[] values;
        bytes32 dataRoot;
        bytes32[] proof;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Restricts access to the app's designated settler
     * @dev Fetches the settler from LiquidityMatrix and reverts with Forbidden if unauthorized
     */
    modifier onlySettler() {
        (,,, address settler) = ILiquidityMatrix(liquidityMatrix).getAppSetting(app);
        if (msg.sender != settler) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes a new RemoteAppChronicle for a specific app/chain/version
     * @dev Deployed by LiquidityMatrix when an app calls addRemoteAppChronicle
     * @param _liquidityMatrix The LiquidityMatrix contract address
     * @param _app The application this chronicle will serve
     * @param _chainUID The remote chain identifier
     * @param _version The version number for state isolation
     */
    constructor(address _liquidityMatrix, address _app, bytes32 _chainUID, uint256 _version) {
        liquidityMatrix = _liquidityMatrix;
        app = _app;
        chainUID = _chainUID;
        version = _version;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRemoteAppChronicle
    function isFinalized(uint64 timestamp) external view returns (bool) {
        return isLiquiditySettled[timestamp] && isDataSettled[timestamp];
    }

    /// @inheritdoc IRemoteAppChronicle
    function getTotalLiquidityAt(uint64 timestamp) external view returns (int256 liquidity) {
        liquidity = _totalLiquidity.getAsInt(timestamp);
    }

    /// @inheritdoc IRemoteAppChronicle
    function getLiquidityAt(address account, uint64 timestamp) external view returns (int256 liquidity) {
        liquidity = _liquidity[account].getAsInt(timestamp);
    }

    /// @inheritdoc IRemoteAppChronicle
    function getDataAt(bytes32 key, uint64 timestamp) external view returns (bytes memory data) {
        bytes32 hash = _dataHashes[key].get(timestamp);
        return _data[key][hash];
    }

    /// @inheritdoc IRemoteAppChronicle
    function getLastSettledLiquidityTimestamp() external view returns (uint64) {
        // O(1) - return last element (always maximum in chronological order)
        uint256 length = _settledLiquidityTimestamps.length;
        return length > 0 ? uint64(_settledLiquidityTimestamps[length - 1]) : 0;
    }

    /// @inheritdoc IRemoteAppChronicle
    function getSettledLiquidityTimestampAt(uint64 timestamp) external view returns (uint64) {
        // O(log n) - binary search on sorted array using ArrayLib
        return uint64(ArrayLib.findFloor(_settledLiquidityTimestamps, timestamp));
    }

    /// @inheritdoc IRemoteAppChronicle
    function getLastSettledDataTimestamp() external view returns (uint64) {
        // O(1) - return last element (always maximum in chronological order)
        uint256 length = _settledDataTimestamps.length;
        return length > 0 ? uint64(_settledDataTimestamps[length - 1]) : 0;
    }

    /// @inheritdoc IRemoteAppChronicle
    function getSettledDataTimestampAt(uint64 timestamp) external view returns (uint64) {
        // O(log n) - binary search on sorted array using ArrayLib
        return uint64(ArrayLib.findFloor(_settledDataTimestamps, timestamp));
    }

    /// @inheritdoc IRemoteAppChronicle
    function getLastFinalizedTimestamp() external view returns (uint64) {
        // O(1) - return last element (always maximum in chronological order)
        uint256 length = _finalizedTimestamps.length;
        return length > 0 ? uint64(_finalizedTimestamps[length - 1]) : 0;
    }

    /// @inheritdoc IRemoteAppChronicle
    function getFinalizedTimestampAt(uint64 timestamp) external view returns (uint64) {
        // O(log n) - binary search on sorted array using ArrayLib
        return uint64(ArrayLib.findFloor(_finalizedTimestamps, timestamp));
    }

    /**
     * @notice Internal function to check LiquidityMatrix owner for pause control
     * @dev Required by Pausable contract
     */
    function _requirePauser() internal view override {
        address matrixOwner = ILiquidityMatrix(liquidityMatrix).owner();
        if (msg.sender != matrixOwner) revert Unauthorized();
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Settles liquidity data from a remote chain for a specific timestamp
     * @dev Only callable by the app's authorized settler
     *      Processes account liquidity updates, handles account mapping,
     *      and triggers optional hooks for the application
     *      Reverts if liquidity is already settled for the timestamp
     * @param params Settlement parameters containing timestamp, accounts, and liquidity values
     */
    function settleLiquidity(SettleLiquidityParams memory params)
        external
        onlySettler
        whenNotPaused(ACTION_SETTLE_LIQUIDITY)
    {
        if (isLiquiditySettled[params.timestamp]) revert LiquidityAlreadySettled();

        ILiquidityMatrix _liquidityMatrix = ILiquidityMatrix(liquidityMatrix);
        // Get the remote chain's top liquidity tree root
        bytes32 topLiquidityRoot = _liquidityMatrix.getRemoteLiquidityRootAt(chainUID, version, params.timestamp);
        if (topLiquidityRoot == bytes32(0)) revert RootNotReceived();

        // Get the remote app and remote app index
        (address remoteApp, uint256 remoteAppIndex) = _liquidityMatrix.getRemoteApp(app, chainUID);
        if (remoteApp == address(0)) revert RemoteAppNotSet();

        // Verify that the app's liquidity root is in the remote top tree
        bool valid = MerkleTreeLib.verifyProof(
            bytes32(uint256(uint160(remoteApp))), // Key is the app address
            params.liquidityRoot, // App's liquidity root on remote chain
            remoteAppIndex, // App's index in remote top tree
            params.proof, // Merkle proof for remote top tree
            topLiquidityRoot // Root of remote top tree
        );

        if (!valid) revert InvalidMerkleProof();

        (, bool syncMappedAccountsOnly, bool useHook,) = _liquidityMatrix.getAppSetting(app);

        isLiquiditySettled[params.timestamp] = true;

        // Ensure chronological order (O(1) check)
        uint256 length = _settledLiquidityTimestamps.length;
        if (length > 0 && params.timestamp <= uint64(_settledLiquidityTimestamps[length - 1])) {
            revert StaleTimestamp();
        }

        // O(1) append to sorted array (cast to uint256 for storage)
        _settledLiquidityTimestamps.push(uint256(params.timestamp));

        // Handle finalization if data is also settled
        if (isDataSettled[params.timestamp]) {
            // Ensure chronological order for finalized timestamps
            uint256 finalizedLength = _finalizedTimestamps.length;
            if (finalizedLength == 0 || params.timestamp > uint64(_finalizedTimestamps[finalizedLength - 1])) {
                _finalizedTimestamps.push(uint256(params.timestamp));
            }
        }

        // Process each account's liquidity update
        for (uint256 i; i < params.accounts.length; ++i) {
            (address account, int256 liquidity) = (params.accounts[i], params.liquidity[i]);

            // Check if account is mapped to a local account
            address _account = _liquidityMatrix.getMappedAccount(app, chainUID, account);
            if (syncMappedAccountsOnly && _account == address(0)) continue;
            if (_account == address(0)) {
                _account = account;
            }

            // Update liquidity snapshot
            _liquidity[_account].setAsInt(liquidity, params.timestamp);

            // Trigger hook if enabled, catching any failures
            if (useHook) {
                try ILiquidityMatrixHook(app).onSettleLiquidity(chainUID, version, params.timestamp, _account) { }
                catch (bytes memory reason) {
                    emit OnSettleLiquidityFailure(params.timestamp, account, liquidity, reason);
                }
            }
        }

        // Use the total liquidity provided by the settler
        _totalLiquidity.setAsInt(params.totalLiquidity, params.timestamp);
        if (useHook) {
            try ILiquidityMatrixHook(app).onSettleTotalLiquidity(chainUID, version, params.timestamp) { }
            catch (bytes memory reason) {
                emit OnSettleTotalLiquidityFailure(params.timestamp, params.totalLiquidity, reason);
            }
        }

        emit SettleLiquidity(params.timestamp, params.liquidityRoot);
    }

    /**
     * @notice Settles data from a remote chain for a specific timestamp
     * @dev Only callable by the app's authorized settler
     *      Processes key-value data updates and triggers optional hooks
     *      Reverts if data is already settled for the timestamp
     * @param params Settlement parameters containing timestamp, keys, and values
     */
    function settleData(SettleDataParams memory params) external onlySettler whenNotPaused(ACTION_SETTLE_DATA) {
        if (isDataSettled[params.timestamp]) revert DataAlreadySettled();

        ILiquidityMatrix _liquidityMatrix = ILiquidityMatrix(liquidityMatrix);
        // Get the remote chain's top data tree root
        bytes32 topDataRoot = _liquidityMatrix.getRemoteDataRootAt(chainUID, version, params.timestamp);
        if (topDataRoot == bytes32(0)) revert RootNotReceived();

        // Get the remote app and remote app index
        (address remoteApp, uint256 remoteAppIndex) = _liquidityMatrix.getRemoteApp(app, chainUID);
        if (remoteApp == address(0)) revert RemoteAppNotSet();

        // Verify that the app's data root is in the remote top tree
        bool valid = MerkleTreeLib.verifyProof(
            bytes32(uint256(uint160(remoteApp))), // Key is the app address
            params.dataRoot, // App's data root on remote chain
            remoteAppIndex, // App's index in remote top tree
            params.proof, // Merkle proof for remote top tree
            topDataRoot // Root of remote top tree
        );

        if (!valid) revert InvalidMerkleProof();

        (,, bool useHook,) = _liquidityMatrix.getAppSetting(app);

        isDataSettled[params.timestamp] = true;

        // Ensure chronological order (O(1) check)
        uint256 length = _settledDataTimestamps.length;
        if (length > 0 && params.timestamp <= uint64(_settledDataTimestamps[length - 1])) {
            revert StaleTimestamp();
        }

        // O(1) append to sorted array (cast to uint256 for storage)
        _settledDataTimestamps.push(uint256(params.timestamp));

        // Handle finalization if liquidity is also settled
        if (isLiquiditySettled[params.timestamp]) {
            // Ensure chronological order for finalized timestamps
            uint256 finalizedLength = _finalizedTimestamps.length;
            if (finalizedLength == 0 || params.timestamp > uint64(_finalizedTimestamps[finalizedLength - 1])) {
                _finalizedTimestamps.push(uint256(params.timestamp));
            }
        }

        // Process each key-value pair
        for (uint256 i; i < params.keys.length; ++i) {
            (bytes32 key, bytes memory value) = (params.keys[i], params.values[i]);
            bytes32 hash = keccak256(value);
            _dataHashes[key].set(hash, params.timestamp);
            _data[key][hash] = value;

            // Trigger hook if enabled, catching any failures
            if (useHook) {
                try ILiquidityMatrixHook(app).onSettleData(chainUID, version, params.timestamp, key) { }
                catch (bytes memory reason) {
                    emit OnSettleDataFailure(params.timestamp, key, value, reason);
                }
            }
        }

        emit SettleData(params.timestamp, params.dataRoot);
    }
}
