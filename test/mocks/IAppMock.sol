// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ISynchronizerCallbacks } from "src/interfaces/ISynchronizerCallbacks.sol";
import { ISynchronizerAccountMapper } from "src/interfaces/ISynchronizerAccountMapper.sol";

interface IAppMock is ISynchronizerCallbacks, ISynchronizerAccountMapper {
    function remoteLiquidity(uint32 eid, address account) external view returns (int256);

    function remoteTotalLiquidity(uint32 eid) external view returns (int256);

    function remoteData(uint32 eid, bytes32 key) external view returns (bytes memory);

    function setShouldMapAccounts(uint32 eid, address remote, address local, bool shouldMap) external;
}
