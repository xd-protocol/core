// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILayerZeroReceiver } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppReducer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReducer.sol";

interface ILiquidityMatrix is ILayerZeroReceiver, IOAppCore, IOAppReducer {
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

    function chainConfigs() external view returns (uint32[] memory eids, uint16[] memory confirmations);

    function quoteSync(uint128 gasLimit, uint32 calldataSize) external view returns (uint256 fee);

    function quoteSync(uint32[] memory eids, uint128 gasLimit, uint32 calldataSize) external view returns (uint256 fee);

    function quoteRequestMapRemoteAccounts(
        uint32 eid,
        address app,
        address remoteApp,
        address[] memory remotes,
        address[] memory locals,
        uint128 gasLimit
    ) external view returns (uint256 fee);

    function getSyncCmd() external view returns (bytes memory);

    function getSyncCmd(uint32[] memory eids) external view returns (bytes memory);

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

    function isLiquidityRootSettled(address app, uint32 eid, uint256 timestamp) external view returns (bool);

    function isDataRootSettled(address app, uint32 eid, uint256 timestamp) external view returns (bool);

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

    function configChains(uint32[] memory eids, uint16[] memory confirmations) external;

    function updateSettlerWhitelisted(address account, bool whitelisted) external;

    function sync(uint128 gasLimit, uint32 calldataSize) external payable returns (MessagingReceipt memory fee);

    function sync(uint32[] memory eids, uint128 gasLimit, uint32 calldataSize) external payable returns (MessagingReceipt memory fee);

    function requestMapRemoteAccounts(
        uint32 eid,
        address remoteApp,
        address[] memory remotes,
        address[] memory locals,
        uint128 gasLimit
    ) external payable;
}
