// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ILiquidityMatrixCallbacks } from "src/interfaces/ILiquidityMatrixCallbacks.sol";
import { ILiquidityMatrixAccountMapper } from "src/interfaces/ILiquidityMatrixAccountMapper.sol";

interface IAppMock is ILiquidityMatrixCallbacks, ILiquidityMatrixAccountMapper {
    function remoteLiquidity(uint32 eid, address account) external view returns (int256);

    function remoteTotalLiquidity(uint32 eid) external view returns (int256);

    function remoteData(uint32 eid, bytes32 key) external view returns (bytes memory);

    function setShouldMapAccounts(uint32 eid, address remote, address local, bool shouldMap) external;
}
