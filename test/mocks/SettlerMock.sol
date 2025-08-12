// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IRemoteAppChronicle } from "src/interfaces/IRemoteAppChronicle.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { RemoteAppChronicle } from "src/chronicles/RemoteAppChronicle.sol";

contract SettlerMock {
    address immutable liquidityMatrix;

    struct State {
        mapping(uint256 index => address) accounts;
        mapping(uint256 index => bytes32) keys;
    }

    uint32 internal constant TRAILING_MASK = uint32(0x80000000);
    uint32 internal constant INDEX_MASK = uint32(0x7fffffff);

    mapping(address app => mapping(bytes32 chainUID => State)) internal _states;

    constructor(address _liquidityMatrix) {
        liquidityMatrix = _liquidityMatrix;
    }

    function settleLiquidity(
        address app,
        bytes32 chainUID,
        uint256 timestamp,
        bytes32[] calldata proof,
        bytes calldata accountsData,
        int256[] calldata liquidity
    ) external {
        State storage state = _states[app][chainUID];

        address[] memory accounts = new address[](liquidity.length);
        uint256 offset;
        for (uint256 i; i < liquidity.length; ++i) {
            // first bit indicates whether an account follows after index and the rest 31 bits represent index
            uint32 _index = uint32(bytes4(accountsData[offset:offset + 4]));
            offset += 4;
            uint32 idx = _index & INDEX_MASK;
            if (_index & TRAILING_MASK > 0) {
                accounts[i] = address(bytes20(accountsData[offset:offset + 20]));
                offset += 20;
                state.accounts[idx] = accounts[i];
            } else {
                accounts[i] = state.accounts[idx];
            }
        }

        // For testing, compute the app's liquidity root from the accounts and liquidity values
        bytes32 liquidityRoot = _computeAppLiquidityRoot(accounts, liquidity);

        // Get the current RemoteAppChronicle for this app and chainUID
        address chronicle = ILiquidityMatrix(liquidityMatrix).getCurrentRemoteAppChronicle(app, chainUID);

        // Call settleLiquidity on the RemoteAppChronicle with Merkle proof
        RemoteAppChronicle(chronicle).settleLiquidity(
            RemoteAppChronicle.SettleLiquidityParams(uint64(timestamp), accounts, liquidity, liquidityRoot, proof)
        );
    }

    function settleData(
        address app,
        bytes32 chainUID,
        uint256 timestamp,
        bytes32[] calldata proof,
        bytes calldata keysData,
        bytes[] calldata values
    ) external {
        State storage state = _states[app][chainUID];

        bytes32[] memory keys = new bytes32[](values.length);
        uint256 offset;
        for (uint256 i; i < values.length; ++i) {
            // first bit indicates whether a key follows after index and the rest 31 bits represent index
            uint32 _index = uint32(bytes4(keysData[offset:offset + 4]));
            offset += 4;
            uint32 idx = _index & INDEX_MASK;
            if (_index & TRAILING_MASK > 0) {
                keys[i] = bytes32(keysData[offset:offset + 32]);
                offset += 32;
                state.keys[idx] = keys[i];
            } else {
                keys[i] = state.keys[idx];
            }
        }

        // For testing, compute the app's data root from the keys and values
        bytes32 dataRoot = _computeAppDataRoot(keys, values);

        // Get the current RemoteAppChronicle for this app and chainUID
        address chronicle = ILiquidityMatrix(liquidityMatrix).getCurrentRemoteAppChronicle(app, chainUID);

        // Call settleData on the RemoteAppChronicle with Merkle proof
        RemoteAppChronicle(chronicle).settleData(
            RemoteAppChronicle.SettleDataParams(uint64(timestamp), keys, values, dataRoot, proof)
        );
    }

    // Helper function to compute app's liquidity root for testing
    function _computeAppLiquidityRoot(address[] memory accounts, int256[] memory liquidity)
        private
        pure
        returns (bytes32)
    {
        if (accounts.length == 0) return bytes32(0);

        // Convert addresses to bytes32 keys and int256 to bytes32 values
        bytes32[] memory keys = new bytes32[](accounts.length);
        bytes32[] memory values = new bytes32[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            keys[i] = bytes32(uint256(uint160(accounts[i])));
            values[i] = bytes32(uint256(liquidity[i]));
        }

        // Use MerkleTreeLib to compute root
        return MerkleTreeLib.computeRoot(keys, values);
    }

    // Helper function to compute app's data root for testing
    function _computeAppDataRoot(bytes32[] memory keys, bytes[] memory values) private pure returns (bytes32) {
        if (keys.length == 0) return bytes32(0);

        // Convert bytes to bytes32 hashes for values
        bytes32[] memory valueHashes = new bytes32[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            valueHashes[i] = keccak256(values[i]);
        }

        // Use MerkleTreeLib to compute root
        return MerkleTreeLib.computeRoot(keys, valueHashes);
    }
}
