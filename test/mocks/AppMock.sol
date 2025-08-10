// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IAppMock } from "./IAppMock.sol";

contract AppMock is IAppMock {
    address immutable liquidityMatrix;
    mapping(bytes32 chainUID => mapping(address remoteAccount => mapping(address localAccont => bool))) public
        shouldMapAccounts;

    mapping(bytes32 chainUID => mapping(address account => int256)) _remoteLiquidity;
    mapping(bytes32 chainUID => int256) _remoteTotalLiquidity;
    mapping(bytes32 chainUID => mapping(bytes32 key => bytes value)) _remoteData;

    constructor(address _liquidityMatrix) {
        liquidityMatrix = _liquidityMatrix;
    }

    function remoteLiquidity(bytes32 chainUID, address account) external view returns (int256) {
        return _remoteLiquidity[chainUID][account];
    }

    function remoteTotalLiquidity(bytes32 chainUID) external view returns (int256) {
        return _remoteTotalLiquidity[chainUID];
    }

    function remoteData(bytes32 chainUID, bytes32 key) external view returns (bytes memory) {
        return _remoteData[chainUID][key];
    }

    function setShouldMapAccounts(bytes32 chainUID, address remote, address local, bool shouldMap) external {
        shouldMapAccounts[chainUID][remote][local] = shouldMap;
    }

    function onMapAccounts(bytes32 chainUID, address remoteAccount, address localAccount) external {
        // Empty
    }

    function onSettleLiquidity(bytes32 chainUID, uint256, uint64, address account) external {
        _remoteLiquidity[chainUID][account] = 0; // TODO
    }

    function onSettleTotalLiquidity(bytes32 chainUID, uint256, uint64) external {
        _remoteTotalLiquidity[chainUID] = 0;
    }

    function onSettleData(bytes32 chainUID, uint256, uint64, bytes32 key) external {
        _remoteData[chainUID][key] = "";
    }
}
