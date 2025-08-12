// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import {
    ILayerZeroEndpointV2,
    MessagingParams,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IGateway } from "src/interfaces/IGateway.sol";
import { IGatewayApp } from "src/interfaces/IGatewayApp.sol";
import { ILocalAppChronicle } from "src/interfaces/ILocalAppChronicle.sol";
import { IRemoteAppChronicle } from "src/interfaces/IRemoteAppChronicle.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { RemoteAppChronicle } from "src/chronicles/RemoteAppChronicle.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { ILayerZeroReceiver } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { IAppMock } from "../mocks/IAppMock.sol";

abstract contract LiquidityMatrixTestHelper is TestHelperOz5 {
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

    uint128 constant SYNC_GAS_LIMIT = 300_000;
    uint128 constant MAP_REMOTE_ACCOUNTS_GAS_LIMIT = 100_000;

    address localSyncer = makeAddr("localSyncer");
    ILiquidityMatrix local;
    address localApp;
    Storage localStorage;
    address localSettler;

    address remoteSyncer = makeAddr("remoteSyncer");
    ILiquidityMatrix remote;
    address remoteApp;
    Storage remoteStorage;
    address remoteSettler;

    mapping(bytes32 fromChainUID => mapping(bytes32 toChainUID => mapping(address fromAccount => address toAccount)))
        mappedAccounts;

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
        ILiquidityMatrix liquidityMatrix,
        address app,
        Storage storage s,
        address[] memory users,
        bytes32 seed
    )
        internal
        returns (uint256[] memory indices, address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity)
    {
        uint256 size = 256;
        indices = new uint256[](size);
        accounts = new address[](size);
        liquidity = new int256[](size);

        for (uint256 i; i < size; ++i) {
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
            (, uint256 index) = liquidityMatrix.updateLocalLiquidity(user, l);
            indices[i] = index;
            accounts[i] = user;
            liquidity[i] = l;
            assertEq(liquidityMatrix.getLocalLiquidity(address(app), user), l);
            assertEq(liquidityMatrix.getLocalTotalLiquidity(address(app)), totalLiquidity);

            s.appLiquidityTree.update(bytes32(uint256(uint160(user))), bytes32(uint256(l)));
            assertEq(liquidityMatrix.getLocalLiquidityRoot(address(app)), s.appLiquidityTree.root);
            s.mainLiquidityTree.update(bytes32(uint256(uint160(address(app)))), s.appLiquidityTree.root);
            // Note: getMainLiquidityRoot() removed in chronicle-based architecture
            // The top liquidity tree root can be obtained via getTopRoots() if needed

            // Advance time by at least 1 second to ensure different timestamps
            skip(1 + (uint256(seed) % 1000));
            seed = keccak256(abi.encodePacked(seed, i));
        }

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];
            for (uint256 j; j < s.liquidityTimestamps[user].length; ++j) {
                uint256 timestamp = s.liquidityTimestamps[user][j];
                assertEq(
                    liquidityMatrix.getLocalLiquidityAt(address(app), user, uint64(timestamp)),
                    s.liquidityAt[user][timestamp]
                );
            }
        }
        for (uint256 i; i < s.totalLiquidityTimestamps.length; ++i) {
            uint256 timestamp = s.totalLiquidityTimestamps[i];
            assertEq(
                liquidityMatrix.getLocalTotalLiquidityAt(address(app), uint64(timestamp)), s.totalLiquidityAt[timestamp]
            );
        }
    }

    function _updateLocalData(ILiquidityMatrix liquidityMatrix, address app, Storage storage s, bytes32 seed)
        internal
        returns (uint256[] memory indices, bytes32[] memory keys, bytes[] memory values)
    {
        uint256 size = 256;
        indices = new uint256[](size);
        keys = new bytes32[](size);
        values = new bytes[](size);

        for (uint256 i; i < size; ++i) {
            uint256 timestamp = vm.getBlockTimestamp();
            keys[i] = seed;
            values[i] = abi.encodePacked(keccak256(abi.encodePacked(keys[i], i)));
            s.data[keys[i]] = values[i];
            s.dataAt[keys[i]][timestamp] = values[i];
            s.dataTimestamps[keys[i]].push(timestamp);

            changePrank(app, app);
            (, uint256 index) = liquidityMatrix.updateLocalData(keys[i], values[i]);
            indices[i] = index;
            // Note: getLocalDataHash() removed - data hash now stored internally in chronicles

            s.appDataTree.update(keys[i], keccak256(values[i]));
            assertEq(liquidityMatrix.getLocalDataRoot(address(app)), s.appDataTree.root);
            s.mainDataTree.update(bytes32(uint256(uint160(address(app)))), s.appDataTree.root);
            // Note: getMainDataRoot() removed in chronicle-based architecture
            // The top data tree root can be obtained via getTopRoots() if needed

            seed = keccak256(abi.encodePacked(values[i], i));
        }
        // Note: getLocalDataHashAt() removed - data hash verification now handled internally in chronicles
        // The test originally verified historical data hash values
    }

    function _sync(address _syncer, ILiquidityMatrix _local)
        internal
        returns (bytes32 liquidityRoot, bytes32 dataRoot, uint256 timestamp)
    {
        ILiquidityMatrix[] memory _remotes = new ILiquidityMatrix[](1);
        _remotes[0] = address(_local) == address(local) ? remote : local;
        (bytes32[] memory liquidityRoots, bytes32[] memory dataRoots, uint256[] memory timestamps) =
            _sync(_syncer, _local, _remotes);
        return (liquidityRoots[0], dataRoots[0], timestamps[0]);
    }

    function _sync(address _syncer, ILiquidityMatrix _local, ILiquidityMatrix[] memory _remotes)
        internal
        returns (bytes32[] memory liquidityRoots, bytes32[] memory dataRoots, uint256[] memory timestamps)
    {
        (, address txOrigin, address msgSender) = vm.readCallers();
        changePrank(_syncer, _syncer);

        liquidityRoots = new bytes32[](_remotes.length);
        dataRoots = new bytes32[](_remotes.length);
        timestamps = new uint256[](_remotes.length);

        uint128 gasLimit = SYNC_GAS_LIMIT * uint128(_remotes.length);

        // Use LiquidityMatrix's sync directly (it's now a gateway app)
        uint256 fee = _local.quoteSync(gasLimit);
        _local.sync{ value: fee }(abi.encode(gasLimit, msg.sender));

        bytes[] memory responses = new bytes[](_remotes.length);
        uint32[] memory remoteEids = new uint32[](_remotes.length);
        address[] memory remotes = new address[](_remotes.length);
        for (uint256 i; i < _remotes.length; ++i) {
            uint256 version;
            (version, liquidityRoots[i], dataRoots[i], timestamps[i]) = _remotes[i].getTopRoots();
            responses[i] = abi.encode(version, liquidityRoots[i], dataRoots[i], timestamps[i]);
            remoteEids[i] = uint32(i + 2);
            remotes[i] = address(_remotes[i]);
        }

        // Save current prank state and temporarily stop it
        (, address currentTxOrigin, address currentMsgSender) = vm.readCallers();
        vm.stopPrank();

        _executeSync(address(_local.gateway()), EID_LOCAL, address(_local), remoteEids, remotes);

        // Restore the original prank state if there was one
        if (currentMsgSender != address(0)) {
            vm.startPrank(currentTxOrigin, currentMsgSender);
        }

        for (uint256 i; i < _remotes.length; ++i) {
            bytes32 chainUID = _eid(_remotes[i]);
            (bytes32 _liquidityRoot, uint256 _liquidityTimestamp) = _local.getLastReceivedRemoteLiquidityRoot(chainUID);
            assertEq(_liquidityRoot, liquidityRoots[i], "Liquidity root mismatch");

            // Only check liquidity timestamp if liquidity root is non-zero
            if (liquidityRoots[i] != bytes32(0)) {
                assertEq(_liquidityTimestamp, timestamps[i], "Liquidity timestamp mismatch");
            }

            (bytes32 _dataRoot, uint256 _dataTimestamp) = _local.getLastReceivedRemoteDataRoot(chainUID);
            assertEq(_dataRoot, dataRoots[i], "Data root mismatch");

            // Only check data timestamp if data root is non-zero
            if (dataRoots[i] != bytes32(0)) {
                assertEq(_dataTimestamp, timestamps[i], "Data timestamp mismatch");
            }
        }
        changePrank(txOrigin, msgSender);
    }

    function _requestMapRemoteAccounts(
        ILiquidityMatrix _local,
        address _localApp,
        ILiquidityMatrix _remote,
        address _remoteApp,
        address[] memory contracts
    ) internal {
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](1);
        remotes[0] = _remote;
        address[] memory remoteApps = new address[](1);
        remoteApps[0] = _remoteApp;
        _requestMapRemoteAccounts(_local, _localApp, remotes, remoteApps, contracts);
    }

    function _requestMapRemoteAccounts(
        ILiquidityMatrix _local,
        address _localApp,
        ILiquidityMatrix[] memory remotes,
        address[] memory remoteApps,
        address[] memory contracts
    ) internal {
        changePrank(_localApp, _localApp);
        bytes32 fromChainUID = _eid(_local);
        for (uint32 i; i < remotes.length; ++i) {
            ILiquidityMatrix _remote = remotes[i];
            bytes32 toChainUID = _eid(_remote);
            address[] memory from = new address[](contracts.length);
            address[] memory to = new address[](from.length);
            for (uint256 j; j < to.length; ++j) {
                from[j] = contracts[j];
                to[j] = contracts[(j + 1) % to.length];
                mappedAccounts[fromChainUID][toChainUID][from[j]] = to[j];
                IAppMock(remoteApps[i]).setShouldMapAccounts(fromChainUID, from[j], to[j], true);
            }

            uint128 gasLimit = MAP_REMOTE_ACCOUNTS_GAS_LIMIT * uint128(to.length);

            // Quote the fee for mapping accounts
            uint256 fee = _local.quoteRequestMapRemoteAccounts(toChainUID, _localApp, remoteApps[i], from, to, gasLimit);

            _local.requestMapRemoteAccounts{ value: fee }(
                toChainUID, remoteApps[i], from, to, abi.encode(gasLimit, _localApp)
            );

            // Verify packets sent to the remote gateway - this delivers the message
            this.verifyPackets(uint32(uint256(toChainUID)), addressToBytes32(address(_remote.gateway())));

            for (uint256 j; j < to.length; ++j) {
                assertEq(
                    _remote.getMappedAccount(remoteApps[i], fromChainUID, from[j]),
                    mappedAccounts[fromChainUID][toChainUID][from[j]]
                );
            }
        }
    }

    function _eid(ILiquidityMatrix liquidityMatrix) internal view virtual returns (bytes32) {
        // In the test environment, we can determine the eid based on the contract address
        if (address(liquidityMatrix) == address(local)) {
            return bytes32(uint256(EID_LOCAL));
        } else if (address(liquidityMatrix) == address(remote)) {
            return bytes32(uint256(EID_REMOTE));
        } else {
            revert("Unknown LiquidityMatrix");
        }
    }

    function _eid(address addr) internal view virtual returns (bytes32) {
        // For LiquidityMatrix addresses, we need to check which endpoint they're associated with
        // This is a simplified approach for testing
        if (address(local) != address(0) && addr == address(local)) {
            return bytes32(uint256(EID_LOCAL));
        } else if (address(remote) != address(0) && addr == address(remote)) {
            return bytes32(uint256(EID_REMOTE));
        } else {
            revert("Unknown address");
        }
    }

    function _getMainProof(address app, bytes32 appRoot, uint256 mainIndex) internal pure returns (bytes32[] memory) {
        bytes32[] memory keys = new bytes32[](1);
        keys[0] = bytes32(uint256(uint160(app)));
        bytes32[] memory values = new bytes32[](1);
        values[0] = appRoot;
        return MerkleTreeLib.getProof(keys, values, mainIndex);
    }

    function _executeSync(
        address gateway,
        uint32 localEid,
        address localReader,
        uint32[] memory remoteEids,
        address[] memory remoteReaders
    ) internal {
        if (remoteEids.length != remoteReaders.length) revert("Invalid lengths");

        bytes memory callData = abi.encodeWithSelector(ILiquidityMatrix.getTopRoots.selector);
        IGatewayApp.Request[] memory requests = new IGatewayApp.Request[](remoteReaders.length);
        bytes[] memory responses = new bytes[](remoteReaders.length);
        for (uint256 i; i < remoteReaders.length; ++i) {
            requests[i] = IGatewayApp.Request({
                chainUID: bytes32(uint256(remoteEids[i])),
                timestamp: uint64(block.timestamp),
                target: address(remoteReaders[i])
            });
            (, bytes memory response) = remoteReaders[i].call(callData);
            responses[i] = response;
        }

        // Simulate the gateway calling reduce and then onRead
        bytes memory payload = IGatewayApp(localReader).reduce(requests, callData, responses);
        this.verifyPackets(localEid, addressToBytes32(address(gateway)), 0, address(0), payload);
    }

    // Helper function to settle liquidity with automatic proof generation
    function _settleLiquidity(
        ILiquidityMatrix localMatrix,
        ILiquidityMatrix remoteMatrix,
        address app,
        bytes32 chainUID,
        uint64 timestamp,
        address[] memory accounts,
        int256[] memory liquidity
    ) internal {
        _settleLiquidity(localMatrix, remoteMatrix, app, chainUID, timestamp, accounts, liquidity, "");
    }

    function _settleLiquidity(
        ILiquidityMatrix localMatrix,
        ILiquidityMatrix remoteMatrix,
        address app,
        bytes32 chainUID,
        uint64 timestamp,
        address[] memory accounts,
        int256[] memory liquidity,
        bytes memory expectedError
    ) internal {
        (address _remoteApp, uint256 remoteAppIndex) = localMatrix.getRemoteApp(app, chainUID);

        bytes32 appLiquidityRoot =
            ILocalAppChronicle(remoteMatrix.getCurrentLocalAppChronicle(_remoteApp)).getLiquidityRoot();

        // Create a simple top tree with just this app for testing
        bytes32[] memory appKeys = new bytes32[](1);
        bytes32[] memory appRoots = new bytes32[](1);
        appKeys[0] = bytes32(uint256(uint160(_remoteApp)));
        appRoots[0] = appLiquidityRoot;
        // Get the proof for this app in the top tree
        bytes32[] memory proof = MerkleTreeLib.getProof(appKeys, appRoots, remoteAppIndex);

        // Get the RemoteAppChronicle and settle liquidity
        address chronicle = localMatrix.getCurrentRemoteAppChronicle(app, chainUID);
        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }
        RemoteAppChronicle(chronicle).settleLiquidity(
            RemoteAppChronicle.SettleLiquidityParams({
                timestamp: timestamp,
                accounts: accounts,
                liquidity: liquidity,
                liquidityRoot: appLiquidityRoot,
                proof: proof
            })
        );
    }

    // Helper function to settle data with automatic proof generation
    function _settleData(
        ILiquidityMatrix localMatrix,
        ILiquidityMatrix remoteMatrix,
        address app,
        bytes32 chainUID,
        uint64 timestamp,
        bytes32[] memory keys,
        bytes[] memory values
    ) internal {
        _settleData(localMatrix, remoteMatrix, app, chainUID, timestamp, keys, values, "");
    }

    function _settleData(
        ILiquidityMatrix localMatrix,
        ILiquidityMatrix remoteMatrix,
        address app,
        bytes32 chainUID,
        uint64 timestamp,
        bytes32[] memory keys,
        bytes[] memory values,
        bytes memory expectedError
    ) internal {
        (address _remoteApp, uint256 remoteAppIndex) = localMatrix.getRemoteApp(app, chainUID);

        bytes32 appDataRoot = ILocalAppChronicle(remoteMatrix.getCurrentLocalAppChronicle(_remoteApp)).getDataRoot();

        // Create a simple top tree with just this app for testing
        bytes32[] memory appKeys = new bytes32[](1);
        bytes32[] memory appRoots = new bytes32[](1);
        appKeys[0] = bytes32(uint256(uint160(_remoteApp)));
        appRoots[0] = appDataRoot;

        // Get the proof for this app in the top tree
        bytes32[] memory proof = MerkleTreeLib.getProof(appKeys, appRoots, remoteAppIndex);

        // Get the RemoteAppChronicle and settle data
        address chronicle = localMatrix.getCurrentRemoteAppChronicle(app, chainUID);
        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }
        RemoteAppChronicle(chronicle).settleData(
            RemoteAppChronicle.SettleDataParams({
                timestamp: timestamp,
                keys: keys,
                values: values,
                dataRoot: appDataRoot,
                proof: proof
            })
        );
    }
}
