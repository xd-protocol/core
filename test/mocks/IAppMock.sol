// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ILiquidityMatrixCallbacks } from "src/interfaces/ILiquidityMatrixCallbacks.sol";
import { ILiquidityMatrixAccountMapper } from "src/interfaces/ILiquidityMatrixAccountMapper.sol";

interface IAppMock is ILiquidityMatrixCallbacks, ILiquidityMatrixAccountMapper {
    function remoteLiquidity(bytes32 chainUID, address account) external view returns (int256);

    function remoteTotalLiquidity(bytes32 chainUID) external view returns (int256);

    function remoteData(bytes32 chainUID, bytes32 key) external view returns (bytes memory);

    function setShouldMapAccounts(bytes32 chainUID, address remote, address local, bool shouldMap) external;
}
