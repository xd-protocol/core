// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISynchronizerCallbacks {
    function onMapAccounts(uint32 eid, address remoteAccount, address localAccount) external;

    function onUpdateLiquidity(uint32 eid, uint256 timestamp, address account, int256 liquidity) external;

    function onUpdateTotalLiquidity(uint32 eid, uint256 timestamp, int256 totalLiquidity) external;

    function onUpdateData(uint32 eid, uint256 timestamp, bytes32 key, bytes memory value) external;
}
