// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { ISynchronizerCallbacks } from "src/interfaces/ISynchronizerCallbacks.sol";

interface IAppMock is ISynchronizer, ISynchronizerCallbacks {
    function remoteLiquidity(uint32 eid, address account) external view returns (int256);

    function remoteTotalLiquidity(uint32 eid) external view returns (int256);

    function remoteData(uint32 eid, bytes32 key) external view returns (bytes memory);
}
