// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IAppMock } from "./IAppMock.sol";
import { ILiquidityMatrix } from "../../src/interfaces/ILiquidityMatrix.sol";
import { RemoteAppChronicle } from "../../src/RemoteAppChronicle.sol";

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

    function onSettleLiquidity(bytes32 chainUID, uint256, /* version */ uint64 timestamp, address account) external {
        // Get the liquidity from the chronicle
        address chronicle = ILiquidityMatrix(liquidityMatrix).getCurrentRemoteAppChronicle(address(this), chainUID);
        _remoteLiquidity[chainUID][account] = RemoteAppChronicle(chronicle).getLiquidityAt(account, timestamp);
    }

    function onSettleTotalLiquidity(bytes32 chainUID, uint256, /* version */ uint64 timestamp) external {
        // Get the total liquidity from the chronicle
        address chronicle = ILiquidityMatrix(liquidityMatrix).getCurrentRemoteAppChronicle(address(this), chainUID);
        _remoteTotalLiquidity[chainUID] = RemoteAppChronicle(chronicle).getTotalLiquidityAt(timestamp);
    }

    function onSettleData(bytes32 chainUID, uint256, /* version */ uint64 timestamp, bytes32 key) external {
        // Get the data from the chronicle
        address chronicle = ILiquidityMatrix(liquidityMatrix).getCurrentRemoteAppChronicle(address(this), chainUID);
        _remoteData[chainUID][key] = RemoteAppChronicle(chronicle).getDataAt(key, timestamp);
    }
}
