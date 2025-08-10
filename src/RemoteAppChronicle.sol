// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ILiquidityMatrix } from "./interfaces/ILiquidityMatrix.sol";
import { ILiquidityMatrixHook } from "./interfaces/ILiquidityMatrixHook.sol";
import { SnapshotsLib } from "./libraries/SnapshotsLib.sol";
import { ArrayLib } from "./libraries/ArrayLib.sol";
import { MerkleTreeLib } from "./libraries/MerkleTreeLib.sol";

contract RemoteAppChronicle {
    using SnapshotsLib for SnapshotsLib.Snapshots;
    using ArrayLib for uint256[];

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    struct SettleLiquidityParams {
        uint64 timestamp;
        address[] accounts;
        int256[] liquidity;
    }

    struct SettleDataParams {
        uint64 timestamp;
        bytes32[] keys;
        bytes[] values;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable liquidityMatrix;
    address public immutable app;
    bytes32 public immutable chainUID;
    uint256 public immutable version;

    SnapshotsLib.Snapshots internal _totalLiquidity;
    mapping(address account => SnapshotsLib.Snapshots) internal _liquidity;
    mapping(bytes32 key => SnapshotsLib.Snapshots) internal _dataHashes;
    mapping(bytes32 key => mapping(bytes32 hash => bytes)) internal _data;

    mapping(uint64 timestamp => bool) public isLiquiditySettled;
    mapping(uint64 timestamp => bool) public isDataSettled;

    uint256[] internal _settledLiquidityTimestamps;
    uint256[] internal _settledDataTimestamps;
    uint256[] internal _finalizedTimestamps;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event OnSettleLiquidityFailure(uint64 indexed timestamp, address indexed account, int256 liquidity, bytes reason);
    event OnSettleTotalLiquidityFailure(uint64 indexed timestamp, int256 totalLiquidity, bytes reason);
    event OnSettleDataFailure(uint64 indexed timestamp, bytes32 indexed key, bytes value, bytes reason);

    event SettleLiquidity(uint64 indexed timestamp);
    event SettleData(uint64 indexed timestamp);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();
    error LiquidityAlreadySettled();
    error DataAlreadySettled();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlySettler() {
        (,,, address settler) = ILiquidityMatrix(liquidityMatrix).getAppSetting(app);
        if (msg.sender != settler) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _liquidityMatrix, address _app, bytes32 _chainUID, uint256 _version) {
        liquidityMatrix = _liquidityMatrix;
        app = _app;
        chainUID = _chainUID;
        version = _version;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function isFinalized(uint64 timestamp) public view returns (bool) {
        return isLiquiditySettled[timestamp] && isDataSettled[timestamp];
    }

    function getTotalLiquidityAt(uint64 timestamp) external view returns (int256 liquidity) {
        liquidity = _totalLiquidity.getAsInt(timestamp);
    }

    function getLiquidityAt(address account, uint64 timestamp) external view returns (int256 liquidity) {
        liquidity = _liquidity[account].getAsInt(timestamp);
    }

    function getDataAt(bytes32 key, uint64 timestamp) external view returns (bytes memory data) {
        bytes32 hash = _dataHashes[key].get(timestamp);
        return _data[key][hash];
    }

    function getLastSettledLiquidityTimestamp() external view returns (uint64) {
        return uint64(_settledLiquidityTimestamps.last());
    }

    function getSettledLiquidityTimestampAt(uint64 timestamp) external view returns (uint64) {
        return uint64(_settledLiquidityTimestamps.findFloor(timestamp));
    }

    function getLastSettledDataTimestamp() external view returns (uint64) {
        return uint64(_settledDataTimestamps.last());
    }

    function getSettledDataTimestampAt(uint64 timestamp) external view returns (uint64) {
        return uint64(_settledDataTimestamps.findFloor(timestamp));
    }

    function getLastFinalizedTimestamp() external view returns (uint64) {
        return uint64(_finalizedTimestamps.last());
    }

    function getFinalizedTimestampAt(uint64 timestamp) external view returns (uint64) {
        return uint64(_finalizedTimestamps.findFloor(timestamp));
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Settles liquidity data from a remote chain for a specific app
     * @dev Trusts the settler to provide valid data without proof verification.
     *      Updates liquidity snapshots and triggers hooks if enabled.
     * @param params Settlement parameters including app, chainUID, timestamp, accounts and liquidity values
     */
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

    /**
     * @notice Settles arbitrary data from a remote chain for a specific app
     * @dev Trusts the settler to provide valid data without proof verification.
     *      Updates data hashes and triggers hook if enabled.
     * @param params Settlement parameters including app, chainUID, timestamp, keys and values
     */
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
