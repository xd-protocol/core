// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ISynchronizerCallbacks } from "src/interfaces/ISynchronizerCallbacks.sol";

contract AppMock is ISynchronizerCallbacks {
    address immutable synchronizer;

    mapping(uint32 eid => mapping(address account => int256)) _remoteLiquidity;
    mapping(uint32 eid => int256) _remoteTotalLiquidity;
    mapping(uint32 eid => mapping(bytes32 key => bytes value)) _remoteData;

    constructor(address _synchronizer) {
        synchronizer = _synchronizer;
    }

    function remoteLiquidity(uint32 eid, address account) external view returns (int256) {
        return _remoteLiquidity[eid][account];
    }

    function remoteTotalLiquidity(uint32 eid) external view returns (int256) {
        return _remoteTotalLiquidity[eid];
    }

    function remoteData(uint32 eid, bytes32 key) external view returns (bytes memory) {
        return _remoteData[eid][key];
    }

    fallback() external {
        address target = synchronizer;
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := call(gas(), target, 0, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }

    function onUpdateLiquidity(uint32 eid, uint256, address account, int256 liquidity) external {
        _remoteLiquidity[eid][account] = liquidity;
    }

    function onUpdateTotalLiquidity(uint32 eid, uint256, int256 totalLiquidity) external {
        _remoteTotalLiquidity[eid] = totalLiquidity;
    }

    function onUpdateData(uint32 eid, uint256, bytes32 key, bytes memory value) external {
        _remoteData[eid][key] = value;
    }
}
