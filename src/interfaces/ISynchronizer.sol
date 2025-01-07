// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILayerZeroReceiver } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";

interface ISynchronizer is ILayerZeroReceiver {
    struct ChainConfig {
        uint32 targetEid;
        uint16 confirmations;
        address to;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function READ_CHANNEL() external view returns (uint32);

    function chainConfigs() external view returns (ChainConfig[] memory);

    function quoteSync(uint128 gasLimit, uint32 calldataSize) external view returns (MessagingFee memory fee);

    function quoteRequestUpdateRemoteAccounts(
        uint32 eid,
        address app,
        address remoteApp,
        address[] memory locals,
        address[] memory remotes,
        uint128 gasLimit
    ) external view returns (MessagingFee memory fee);

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

    function liquidityBatchRoot(address app, uint32 eid, uint256 batchId) external view returns (bytes32);

    function lastLiquidityBatchId(address app, uint32 eid) external view returns (uint256);

    function dataBatchRoot(address app, uint32 eid, uint256 batchId) external view returns (bytes32);

    function lastDataBatchId(address app, uint32 eid) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function registerApp(bool syncContracts) external;

    function updateSyncContracts(bool syncContracts) external;

    function updateLocalLiquidity(address account, int256 liquidity)
        external
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

    function updateLocalData(bytes32 key, bytes memory value)
        external
        returns (uint256 mainTreeIndex, uint256 appTreeIndex);

    function updateRemoteApp(uint32 eid, address remoteApp) external;

    function settleLiquidity(
        address app,
        uint32 eid,
        uint256 timestamp,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        address[] calldata accounts,
        int256[] calldata liquidity
    ) external;

    function settleData(
        address app,
        uint32 eid,
        uint256 timestamp,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external;

    function createLiquidityBatch(
        address app,
        uint32 eid,
        uint256 timestamp,
        address[] calldata accounts,
        int256[] calldata liquidity
    ) external;

    function submitLiquidity(
        address app,
        uint32 eid,
        uint256 batchId,
        address[] memory accounts,
        int256[] memory liquidity
    ) external;

    function settleLiquidityBatched(
        address app,
        uint32 eid,
        uint256 batchId,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof
    ) external;

    function createDataBatch(
        address app,
        uint32 eid,
        uint256 timestamp,
        bytes32[] calldata keys,
        bytes[] calldata values
    ) external;

    function submitData(address app, uint32 eid, uint256 batchId, bytes32[] memory keys, bytes[] memory values)
        external;

    function settleDataBatched(
        address app,
        uint32 eid,
        uint256 batchId,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof
    ) external;

    function configChains(ChainConfig[] memory configs) external;

    function sync(uint128 gasLimit, uint32 calldataSize) external payable returns (MessagingReceipt memory fee);

    function requestUpdateRemoteAccounts(
        uint32[] memory eids,
        address[] memory remoteApps,
        address[][] memory remotes,
        address[][] memory locals,
        uint128[] memory gasLimits
    ) external payable;
}
