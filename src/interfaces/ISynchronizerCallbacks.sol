// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISynchronizerCallbacks {
    function onUpdateValue(uint32 eid, bytes32 tag, int256 value) external;

    function onUpdateSum(uint32 eid, int256 sum) external;
}
