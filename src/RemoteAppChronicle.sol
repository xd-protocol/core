// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IRemoteAppChronicle } from "./interfaces/IRemoteAppChronicle.sol";
import { ILiquidityMatrix } from "./interfaces/ILiquidityMatrix.sol";
import { ILiquidityMatrixHook } from "./interfaces/ILiquidityMatrixHook.sol";
import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";
import { ArrayLib } from "./libraries/ArrayLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";

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
 *
 *      Settlement flow:
 *      1. Settler calls settleLiquidity with account balances from remote chain
 *      2. Settler calls settleData with key-value data from remote chain
 *      3. When both are settled for same timestamp, state becomes finalized
 *      4. Optional hooks notify the app of settlement events
 */
contract RemoteAppChronicle is IRemoteAppChronicle {
    using SnapshotsLib for SnapshotsLib.Snapshots;
    using ArrayLib for uint256[];

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

    uint256[] internal _settledLiquidityTimestamps;
    uint256[] internal _settledDataTimestamps;
    uint256[] internal _finalizedTimestamps;

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
    function isFinalized(uint64 timestamp) public view returns (bool) {
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
        return uint64(_settledLiquidityTimestamps.last());
    }

    /// @inheritdoc IRemoteAppChronicle
    function getSettledLiquidityTimestampAt(uint64 timestamp) external view returns (uint64) {
        return uint64(_settledLiquidityTimestamps.findFloor(timestamp));
    }

    /// @inheritdoc IRemoteAppChronicle
    function getLastSettledDataTimestamp() external view returns (uint64) {
        return uint64(_settledDataTimestamps.last());
    }

    /// @inheritdoc IRemoteAppChronicle
    function getSettledDataTimestampAt(uint64 timestamp) external view returns (uint64) {
        return uint64(_settledDataTimestamps.findFloor(timestamp));
    }

    /// @inheritdoc IRemoteAppChronicle
    function getLastFinalizedTimestamp() external view returns (uint64) {
        return uint64(_finalizedTimestamps.last());
    }

    /// @inheritdoc IRemoteAppChronicle
    function getFinalizedTimestampAt(uint64 timestamp) external view returns (uint64) {
        return uint64(_finalizedTimestamps.findFloor(timestamp));
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRemoteAppChronicle
    function settleLiquidity(SettleLiquidityParams memory params) external onlySettler {
        if (isLiquiditySettled[params.timestamp]) revert LiquidityAlreadySettled();

        (, bool syncMappedAccountsOnly, bool useHook,) = ILiquidityMatrix(liquidityMatrix).getAppSetting(app);

        isLiquiditySettled[params.timestamp] = true;

        if (params.timestamp > _settledLiquidityTimestamps.last()) {
            _settledLiquidityTimestamps.push(params.timestamp);
            if (params.timestamp > _finalizedTimestamps.last() && isDataSettled[params.timestamp]) {
                _finalizedTimestamps.push(params.timestamp);
            }
        }

        int256 totalLiquidity;
        // Process each account's liquidity update
        for (uint256 i; i < params.accounts.length; ++i) {
            (address account, int256 liquidity) = (params.accounts[i], params.liquidity[i]);

            // Check if account is mapped to a local account
            address _account = ILiquidityMatrix(liquidityMatrix).getMappedAccount(app, chainUID, account);
            if (syncMappedAccountsOnly && _account == address(0)) continue;
            if (_account == address(0)) {
                _account = account;
            }

            // Update liquidity snapshot and track total change
            SnapshotsLib.Snapshots storage snapshots = _liquidity[_account];
            totalLiquidity -= _liquidity[_account].getAsInt();
            snapshots.setAsInt(liquidity, params.timestamp);
            totalLiquidity += liquidity;

            // Trigger hook if enabled, catching any failures
            if (useHook) {
                try ILiquidityMatrixHook(app).onSettleLiquidity(chainUID, version, params.timestamp, _account) { }
                catch (bytes memory reason) {
                    emit OnSettleLiquidityFailure(params.timestamp, account, liquidity, reason);
                }
            }
        }

        _totalLiquidity.setAsInt(totalLiquidity, params.timestamp);
        if (useHook) {
            try ILiquidityMatrixHook(app).onSettleTotalLiquidity(chainUID, version, params.timestamp) { }
            catch (bytes memory reason) {
                emit OnSettleTotalLiquidityFailure(params.timestamp, totalLiquidity, reason);
            }
        }

        emit SettleLiquidity(params.timestamp);
    }

    /// @inheritdoc IRemoteAppChronicle
    function settleData(SettleDataParams memory params) external onlySettler {
        if (isDataSettled[params.timestamp]) revert DataAlreadySettled();

        (,, bool useHook,) = ILiquidityMatrix(liquidityMatrix).getAppSetting(app);

        isDataSettled[params.timestamp] = true;

        if (params.timestamp > _settledDataTimestamps.last()) {
            _settledDataTimestamps.push(params.timestamp);
            if (params.timestamp > _finalizedTimestamps.last() && isLiquiditySettled[params.timestamp]) {
                _finalizedTimestamps.push(params.timestamp);
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

        emit SettleData(params.timestamp);
    }
}
