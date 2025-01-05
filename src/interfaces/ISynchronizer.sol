// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISynchronizer {
    struct ChainConfig {
        uint32 targetEid;
        uint16 confirmations;
        address to;
    }

    function chainConfigs() external view returns (ChainConfig[] memory);

    function getAppSetting(address app) external view returns (bool registered, bool syncContracts);

    function getLocalAccount(address app, uint32 eid, address remote) external view returns (address local);

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

    function registerApp(bool syncContracts) external;

    function updateSyncContracts(bool syncContracts) external;

    function updateLocalLiquidity(address account, int256 liquidity)
        external
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

    function updateLocalData(bytes32 key, bytes memory value)
        external
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);
}
