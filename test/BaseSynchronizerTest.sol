// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    ILayerZeroEndpointV2,
    MessagingParams,
    MessagingReceipt,
    MessagingFee,
    Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { ILayerZeroReceiver } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { IAppMock } from "./mocks/IAppMock.sol";

abstract contract BaseSynchronizerTest is TestHelperOz5 {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    struct Storage {
        MerkleTreeLib.Tree appLiquidityTree;
        MerkleTreeLib.Tree appDataTree;
        MerkleTreeLib.Tree mainLiquidityTree;
        MerkleTreeLib.Tree mainDataTree;
        mapping(address account => int256) liquidity;
        mapping(address account => mapping(uint256 timestamp => int256)) liquidityAt;
        mapping(address account => uint256[]) liquidityTimestamps;
        int256 totalLiquidity;
        mapping(uint256 timestamp => int256) totalLiquidityAt;
        uint256[] totalLiquidityTimestamps;
        mapping(bytes32 key => bytes) data;
        mapping(bytes32 key => mapping(uint256 timestamp => bytes)) dataAt;
        mapping(bytes32 key => uint256[]) dataTimestamps;
    }

    uint32 constant EID_LOCAL = 1;
    uint32 constant EID_REMOTE = 2;
    uint16 constant CMD_SYNC = 1;

    ISynchronizer local;
    address localApp;
    Storage localStorage;
    address localSettler;

    ISynchronizer remote;
    address remoteApp;
    Storage remoteStorage;
    address remoteSettler;

    mapping(uint32 fromEid => mapping(uint32 toEid => mapping(address fromAccount => address toAccount))) mappedAccounts;

    function initialize(Storage storage s) internal {
        s.appLiquidityTree.root = bytes32(0);
        s.appLiquidityTree.size = 0;
        s.appDataTree.root = bytes32(0);
        s.appDataTree.size = 0;
        s.mainLiquidityTree.root = bytes32(0);
        s.mainLiquidityTree.size = 0;
        s.mainDataTree.root = bytes32(0);
        s.mainDataTree.size = 0;
    }

    function _updateLocalLiquidity(
        ISynchronizer synchronizer,
        address app,
        Storage storage s,
        address[] memory users,
        bytes32 seed
    ) internal returns (address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) {
        address[] memory _accounts = new address[](users.length);

        uint256 size;
        for (uint256 i; i < 256; ++i) {
            uint256 timestamp = vm.getBlockTimestamp();
            address user = users[uint256(seed) % users.length];
            int256 l = (int256(uint256(seed)) / 1000);
            totalLiquidity -= s.liquidity[user];
            totalLiquidity += l;
            s.liquidity[user] = l;
            s.liquidityAt[user][timestamp] = l;
            s.liquidityTimestamps[user].push(timestamp);
            s.totalLiquidity = totalLiquidity;
            s.totalLiquidityAt[timestamp] = totalLiquidity;
            s.totalLiquidityTimestamps.push(timestamp);

            changePrank(app, app);
            (, uint256 index) = synchronizer.updateLocalLiquidity(user, l);
            _accounts[index] = user;
            if (size <= index) {
                size = index + 1;
            }
            assertEq(synchronizer.getLocalLiquidity(address(app), user), l);
            assertEq(synchronizer.getLocalTotalLiquidity(address(app)), totalLiquidity);

            s.appLiquidityTree.update(bytes32(uint256(uint160(user))), bytes32(uint256(l)));
            assertEq(synchronizer.getLocalLiquidityRoot(address(app)), s.appLiquidityTree.root);
            s.mainLiquidityTree.update(bytes32(uint256(uint160(address(app)))), s.appLiquidityTree.root);
            assertEq(synchronizer.getMainLiquidityRoot(), s.mainLiquidityTree.root);

            skip(uint256(seed) % 1000);
            seed = keccak256(abi.encodePacked(seed, i));
        }

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];
            for (uint256 j; j < s.liquidityTimestamps[user].length; ++j) {
                uint256 timestamp = s.liquidityTimestamps[user][j];
                assertEq(
                    synchronizer.getLocalLiquidityAt(address(app), user, timestamp), s.liquidityAt[user][timestamp]
                );
            }
        }
        for (uint256 i; i < s.totalLiquidityTimestamps.length; ++i) {
            uint256 timestamp = s.totalLiquidityTimestamps[i];
            assertEq(synchronizer.getLocalTotalLiquidityAt(address(app), timestamp), s.totalLiquidityAt[timestamp]);
        }

        accounts = new address[](size);
        liquidity = new int256[](size);
        for (uint256 i; i < size; ++i) {
            address account = _accounts[i];
            accounts[i] = account;
            liquidity[i] = s.liquidity[account];
        }
    }

    function _updateLocalData(ISynchronizer synchronizer, address app, Storage storage s, bytes32 seed)
        internal
        returns (bytes32[] memory keys, bytes[] memory values)
    {
        keys = new bytes32[](256);
        values = new bytes[](256);

        for (uint256 i; i < 256; ++i) {
            uint256 timestamp = vm.getBlockTimestamp();
            keys[i] = seed;
            values[i] = abi.encodePacked(keccak256(abi.encodePacked(keys[i], i)));
            s.data[keys[i]] = values[i];
            s.dataAt[keys[i]][timestamp] = values[i];
            s.dataTimestamps[keys[i]].push(timestamp);

            changePrank(app, app);
            synchronizer.updateLocalData(keys[i], values[i]);
            assertEq(synchronizer.getLocalDataHash(address(app), keys[i]), keccak256(values[i]));

            s.appDataTree.update(keys[i], keccak256(values[i]));
            assertEq(synchronizer.getLocalDataRoot(address(app)), s.appDataTree.root);
            s.mainDataTree.update(bytes32(uint256(uint160(address(app)))), s.appDataTree.root);
            assertEq(synchronizer.getMainDataRoot(), s.mainDataTree.root);

            seed = keccak256(abi.encodePacked(values[i], i));
        }
        for (uint256 i; i < keys.length; ++i) {
            bytes32 key = keys[i];
            for (uint256 j; j < s.dataTimestamps[key].length; ++j) {
                uint256 timestamp = s.dataTimestamps[key][j];
                assertEq(
                    synchronizer.getLocalDataHashAt(address(app), key, timestamp), keccak256(s.dataAt[key][timestamp])
                );
            }
        }
    }

    function _sync(ISynchronizer _local)
        internal
        returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp)
    {
        ISynchronizer[] memory _remotes = new ISynchronizer[](1);
        _remotes[0] = address(_local) == address(local) ? remote : local;
        (bytes32[] memory liquidityRoots, bytes32[] memory dataRoots, uint256[] memory timestamps) =
            _sync(_local, _remotes);
        return (liquidityRoots[0], dataRoots[0], timestamps[0]);
    }

    function _sync(ISynchronizer _local, ISynchronizer[] memory _remotes)
        internal
        returns (bytes32[] memory liquidityRoots, bytes32[] memory dataRoots, uint256[] memory timestamps)
    {
        liquidityRoots = new bytes32[](_remotes.length);
        dataRoots = new bytes32[](_remotes.length);
        timestamps = new uint256[](_remotes.length);

        uint128 gasLimit = 200_000 * uint128(_remotes.length);
        uint32 calldataSize = 128 * uint32(_remotes.length);
        MessagingFee memory fee = _local.quoteSync(gasLimit, calldataSize);
        _local.sync{ value: fee.nativeFee }(gasLimit, calldataSize);
        skip(1);

        bytes[] memory responses = new bytes[](_remotes.length);
        for (uint256 i; i < _remotes.length; ++i) {
            (liquidityRoots[i], dataRoots[i], timestamps[i]) = _remotes[i].getMainRoots();
            responses[i] = abi.encode(liquidityRoots[i], dataRoots[i], timestamps[i]);
        }
        bytes memory payload = _local.lzReduce(_local.getSyncCmd(), responses);

        verifyPackets(_eid(_local), bytes32(uint256(uint160(address(_local)))), 0, address(0), payload);

        for (uint256 i; i < _remotes.length; ++i) {
            uint32 eid = _eid(_remotes[i]);
            (bytes32 _liquidityRoot, uint256 _liquidityTimestamp) = _local.getLastSyncedLiquidityRoot(eid);
            assertEq(_liquidityRoot, liquidityRoots[i]);
            assertEq(_liquidityTimestamp, timestamps[i]);
            (bytes32 _dataRoot, uint256 _dataTimestamp) = _local.getLastSyncedDataRoot(eid);
            assertEq(_dataRoot, dataRoots[i]);
            assertEq(_dataTimestamp, timestamps[i]);
        }
    }

    function _requestMapRemoteAccounts(
        ISynchronizer _local,
        address _localApp,
        ISynchronizer _remote,
        address _remoteApp,
        address[] memory contracts
    ) internal {
        ISynchronizer[] memory remotes = new ISynchronizer[](1);
        remotes[0] = _remote;
        address[] memory remoteApps = new address[](1);
        remoteApps[0] = _remoteApp;
        _requestMapRemoteAccounts(_local, _localApp, remotes, remoteApps, contracts);
    }

    function _requestMapRemoteAccounts(
        ISynchronizer _local,
        address _localApp,
        ISynchronizer[] memory remotes,
        address[] memory remoteApps,
        address[] memory contracts
    ) internal {
        changePrank(_localApp, _localApp);
        uint32 fromEid = _local.endpoint().eid();
        for (uint32 i; i < remotes.length; ++i) {
            ISynchronizer _remote = remotes[i];
            uint32 toEid = _remote.endpoint().eid();
            address[] memory from = new address[](contracts.length);
            address[] memory to = new address[](from.length);
            for (uint256 j; j < to.length; ++j) {
                from[j] = contracts[j];
                to[j] = contracts[(j + 1) % to.length];
                mappedAccounts[fromEid][toEid][from[j]] = to[j];
                IAppMock(remoteApps[i]).setShouldMapAccounts(fromEid, from[j], to[j], true);
            }

            uint128 gasLimit = uint128(150_000 * to.length);
            MessagingFee memory fee =
                _local.quoteRequestMapRemoteAccounts(toEid, _localApp, remoteApps[i], from, to, gasLimit);
            _local.requestMapRemoteAccounts{ value: fee.nativeFee }(toEid, remoteApps[i], from, to, gasLimit);
            verifyPackets(toEid, address(_remote));

            for (uint256 j; j < to.length; ++j) {
                assertEq(
                    _remote.getMappedAccount(remoteApps[i], fromEid, from[j]), mappedAccounts[fromEid][toEid][from[j]]
                );
            }
        }
    }

    function _eid(ISynchronizer synchronizer) internal view returns (uint32) {
        return ILayerZeroEndpointV2(synchronizer.endpoint()).eid();
    }

    function _getMainProof(address app, bytes32 appRoot, uint256 mainIndex) internal pure returns (bytes32[] memory) {
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = bytes32(uint256(uint160(app)));
        bytes32[] memory values = new bytes32[](1);
        values[0] = appRoot;
        return MerkleTreeLib.getProof(keys, values, mainIndex);
    }
}
