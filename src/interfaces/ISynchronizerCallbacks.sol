// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISynchronizerCallbacks {
    function onUpdateLiquidity(uint32 eid, address account, int256 liquidity) external;

    function onUpdateTotalLiquidity(uint32 eid, int256 totalLiquidity) external;

    function onUpdateData(uint32 eid, bytes32 key, bytes memory value) external;
}
