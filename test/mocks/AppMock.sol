// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IAppMock } from "./IAppMock.sol";

contract AppMock is IAppMock {
    address immutable liquidityMatrix;
    mapping(uint32 remoteEid => mapping(address remoteAccount => mapping(address localAccont => bool))) public
        shouldMapAccounts;

    mapping(uint32 eid => mapping(address account => int256)) _remoteLiquidity;
    mapping(uint32 eid => int256) _remoteTotalLiquidity;
    mapping(uint32 eid => mapping(bytes32 key => bytes value)) _remoteData;

    constructor(address _liquidityMatrix) {
        liquidityMatrix = _liquidityMatrix;
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

    function setShouldMapAccounts(uint32 eid, address remote, address local, bool shouldMap) external {
        shouldMapAccounts[eid][remote][local] = shouldMap;
    }

    function onMapAccounts(uint32 eid, address remoteAccount, address localAccount) external {
        // Empty
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
