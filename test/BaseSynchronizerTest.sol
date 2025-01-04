// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

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
        mapping(uint256 timestamp => int256) totalLiquidityAt;
        uint256[] totalLiquidityTimestamps;
    }

    uint32 constant READ_CHANNEL = 4_294_967_295;
    uint16 constant CMD_SYNC = 1;

    function initialize(Storage storage s) internal {
        s.appLiquidityTree.initialize();
        s.appLiquidityTree.size = 0;
        s.appDataTree.initialize();
        s.appDataTree.size = 0;
        s.mainLiquidityTree.initialize();
        s.mainLiquidityTree.size = 0;
        s.mainDataTree.initialize();
        s.mainDataTree.size = 0;
    }

    function _updateLocalLiquidity(
        ISynchronizer synchronizer,
        IAppMock app,
        Storage storage s,
        address[] memory users,
        bytes32 seed
    ) internal returns (address[] memory accounts) {
        accounts = new address[](users.length);

        uint256 userIndex;
        int256 total;
        for (uint256 i; i < 256; ++i) {
            uint256 timestamp = vm.getBlockTimestamp();
            address user = users[uint256(seed) % 3];
            int256 liquidity = int256(uint256(seed)) / 1000;
            total -= s.liquidity[user];
            total += liquidity;
            s.liquidity[user] = liquidity;
            s.liquidityAt[user][timestamp] = liquidity;
            s.liquidityTimestamps[user].push(timestamp);
            s.totalLiquidityAt[timestamp] = total;
            s.totalLiquidityTimestamps.push(timestamp);

            (, uint256 index) = app.updateLocalLiquidity(user, liquidity);
            if (userIndex == index) {
                accounts[index] = user;
                userIndex++;
            }
            assertEq(synchronizer.getLocalLiquidity(address(app), user), liquidity);
            assertEq(synchronizer.getLocalTotalLiquidity(address(app)), total);

            s.appLiquidityTree.update(bytes32(uint256(uint160(user))), bytes32(uint256(liquidity)));
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
    }

    function _updateLocalData(ISynchronizer synchronizer, IAppMock app, Storage storage s, bytes32 seed)
        internal
        returns (bytes32[] memory keys, bytes[] memory values)
    {
        keys = new bytes32[](256);
        values = new bytes[](256);

        for (uint256 i; i < 256; ++i) {
            keys[i] = seed;
            values[i] = abi.encodePacked(keccak256(abi.encodePacked(keys[i], i)));

            app.updateLocalData(keys[i], values[i]);
            assertEq(synchronizer.getLocalDataHash(address(app), keys[i]), keccak256(values[i]));

            s.appDataTree.update(keys[i], keccak256(values[i]));
            assertEq(synchronizer.getLocalDataRoot(address(app)), s.appDataTree.root);
            s.mainDataTree.update(bytes32(uint256(uint160(address(app)))), s.appDataTree.root);
            assertEq(synchronizer.getMainDataRoot(), s.mainDataTree.root);

            seed = keccak256(abi.encodePacked(values[i], i));
        }
    }

    function _receiveRoots(ILayerZeroReceiver receiver, uint32 eid, bytes32 liquidityRoot, bytes32 dataRoot) internal {
        address endpoint = address(IOAppCore(address(receiver)).endpoint());
        changePrank(endpoint, endpoint);

        Origin memory origin = Origin(READ_CHANNEL, AddressCast.toBytes32(address(receiver)), 0);
        uint32[] memory eids = new uint32[](1);
        eids[0] = eid;
        bytes32[] memory liquidityRoots = new bytes32[](1);
        liquidityRoots[0] = liquidityRoot;
        bytes32[] memory dataRoots = new bytes32[](1);
        dataRoots[0] = dataRoot;
        uint256[] memory timestamps = new uint256[](1);
        timestamps[0] = vm.getBlockTimestamp();

        receiver.lzReceive(
            origin, "", abi.encode(CMD_SYNC, eids, liquidityRoots, dataRoots, timestamps), address(0), ""
        );
    }
}
