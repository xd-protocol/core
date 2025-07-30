// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidityMatrix {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AppNotRegistered();
    error AppAlreadyRegistered();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidLengths();
    error Forbidden();
    error RemoteAccountAlreadyMapped(uint32 eid, address remote);
    error LocalAccountAlreadyMapped(uint32 eid, address local);
    error LiquidityAlreadySettled();
    error DataAlreadySettled();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(address indexed app, bool syncMappedAccountsOnly, bool useCallbacks, address settler);
    event UpdateSyncMappedAccountsOnly(address indexed app, bool syncMappedAccountsOnly);
    event UpdateUseCallbacks(address indexed app, bool useCallbacks);
    event UpdateSettler(address indexed app, address settler);
    event UpdateSettlerWhitelisted(address indexed account, bool whitelisted);

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

    event UpdateRemoteApp(address indexed app, uint32 indexed eid, address indexed remoteApp);
    event MapRemoteAccount(address indexed app, uint32 indexed eid, address indexed remote, address local);

    event OnReceiveRoots(
        uint32 indexed eid, bytes32 indexed liquidityRoot, bytes32 indexed dataRoot, uint256 timestamp
    );

    event UpdateSynchronizer(address indexed synchronizer);
    event UpdateMaxLoop(uint256 indexed maxLoop);

    event SettleLiquidity(uint32 indexed eid, address indexed app, bytes32 indexed liquidityRoot, uint256 timestamp);
    event SettleData(uint32 indexed eid, address indexed app, bytes32 indexed dataRoot, uint256 timestamp);

    event OnUpdateLiquidityFailure(
        uint32 indexed eid, uint256 indexed timestamp, address indexed account, int256 liquidity, bytes reason
    );
    event OnUpdateTotalLiquidityFailure(
        uint32 indexed eid, uint256 indexed timestamp, int256 totalLiquidity, bytes reason
    );
    event OnUpdateDataFailure(
        uint32 indexed eid, uint256 indexed timestamp, bytes32 indexed key, bytes value, bytes reason
    );

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct SettleLiquidityParams {
        address app;
        uint32 eid;
        uint256 timestamp;
        address[] accounts;
        int256[] liquidity;
    }

    struct SettleDataParams {
        address app;
        uint32 eid;
        uint256 timestamp;
        bytes32[] keys;
        bytes[] values;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function synchronizer() external view returns (address);

    function maxLoop() external view returns (uint256);

    function getAppSetting(address app)
        external
        view
        returns (bool registered, bool syncMappedAccountsOnly, bool useCallbacks, address settler);

    function getLocalTotalLiquidity(address app) external view returns (int256 liquidity);

    function getLocalTotalLiquidityAt(address app, uint256 timestamp) external view returns (int256 liquidity);

    function getLocalLiquidity(address app, address account) external view returns (int256 liquidity);

    function getLocalLiquidityAt(address app, address account, uint256 timestamp)
        external
        view
        returns (int256 liquidity);

    function getLocalDataHash(address app, bytes32 key) external view returns (bytes32 hash);

    function getLocalDataHashAt(address app, bytes32 key, uint256 timestamp) external view returns (bytes32 hash);

    function getLocalLiquidityRoot(address app) external view returns (bytes32);

    function getLocalDataRoot(address app) external view returns (bytes32);

    function getMainRoots() external view returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp);

    function getMainLiquidityRoot() external view returns (bytes32);

    function getMainDataRoot() external view returns (bytes32);

    function isSettlerWhitelisted(address account) external view returns (bool);

    function getMappedAccount(address app, uint32 eid, address remote) external view returns (address local);

    function isLocalAccountMapped(address app, uint32 eid, address local) external view returns (bool);

    function getLiquidityRootAt(uint32 eid, uint256 timestamp) external view returns (bytes32 root);

    function getDataRootAt(uint32 eid, uint256 timestamp) external view returns (bytes32 root);

    function getRemoteApp(address app, uint32 eid) external view returns (address);

    function getSettledTotalLiquidity(address app) external view returns (int256 liquidity);

    function getFinalizedTotalLiquidity(address app) external view returns (int256 liquidity);

    function getTotalLiquidityAt(address app, uint256[] memory timestamps) external view returns (int256 liquidity);

    function getSettledLiquidity(address app, address account) external view returns (int256 liquidity);

    function getFinalizedLiquidity(address app, address account) external view returns (int256 liquidity);

    function getLiquidityAt(address app, address account, uint256[] memory timestamps)
        external
        view
        returns (int256 liquidity);

    function getSettledRemoteTotalLiquidity(address app, uint32 eid) external view returns (int256 liquidity);

    function getFinalizedRemoteTotalLiquidity(address app, uint32 eid) external view returns (int256 liquidity);

    function getRemoteTotalLiquidityAt(address app, uint32 eid, uint256 timestamp)
        external
        view
        returns (int256 liquidity);

    function getSettledRemoteLiquidity(address app, uint32 eid, address account)
        external
        view
        returns (int256 liquidity);

    function getFinalizedRemoteLiquidity(address app, uint32 eid, address account)
        external
        view
        returns (int256 liquidity);

    function getRemoteLiquidityAt(address app, uint32 eid, address account, uint256 timestamp)
        external
        view
        returns (int256 liquidity);

    function getSettledRemoteDataHash(address app, uint32 eid, bytes32 key) external view returns (bytes32 value);

    function getFinalizedRemoteDataHash(address app, uint32 eid, bytes32 key) external view returns (bytes32 value);

    function getRemoteDataHashAt(address app, uint32 eid, bytes32 key, uint256 timestamp)
        external
        view
        returns (bytes32 value);

    function getLastSyncedLiquidityRoot(uint32 eid) external view returns (bytes32 root, uint256 timestamp);

    function getLastSettledLiquidityRoot(address app, uint32 eid)
        external
        view
        returns (bytes32 root, uint256 timestamp);

    function getLastFinalizedLiquidityRoot(address app, uint32 eid)
        external
        view
        returns (bytes32 root, uint256 timestamp);

    function getLastSyncedDataRoot(uint32 eid) external view returns (bytes32 root, uint256 timestamp);

    function getLastSettledDataRoot(address app, uint32 eid) external view returns (bytes32 root, uint256 timestamp);

    function getLastFinalizedDataRoot(address app, uint32 eid)
        external
        view
        returns (bytes32 root, uint256 timestamp);

    function isLiquiditySettled(address app, uint32 eid, uint256 timestamp) external view returns (bool);

    function isDataSettled(address app, uint32 eid, uint256 timestamp) external view returns (bool);

    function areRootsFinalized(address app, uint32 eid, uint256 timestamp) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function registerApp(bool syncMappedAccountsOnly, bool useCallbacks, address settler) external;

    function updateSyncMappedAccountsOnly(bool syncMappedAccountsOnly) external;

    function updateUseCallbacks(bool useCallbacks) external;

    function updateSettler(address settler) external;

    function updateLocalLiquidity(address account, int256 liquidity)
        external
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

    function updateLocalData(bytes32 key, bytes memory value)
        external
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

    function updateRemoteApp(uint32 eid, address remoteApp) external;

    function settleLiquidity(SettleLiquidityParams memory params) external;

    function settleData(SettleDataParams memory params) external;

    function updateSettlerWhitelisted(address account, bool whitelisted) external;

    function setSynchronizer(address _synchronizer) external;

    function updateMaxLoop(uint256 _maxLoop) external;

    function onReceiveRoots(uint32 eid, bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp) external;

    function onReceiveMapRemoteAccountRequests(uint32 _fromEid, address _localApp, bytes memory _message) external;

    function requestMapRemoteAccounts(
        uint32 eid,
        address remoteApp,
        address[] memory remotes,
        address[] memory locals,
        uint128 gasLimit
    ) external payable;
}
