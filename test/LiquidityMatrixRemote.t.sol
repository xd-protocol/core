// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ArrayLib } from "src/libraries/ArrayLib.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { LiquidityMatrixTestHelper } from "./helpers/LiquidityMatrixTestHelper.sol";
import { SettlerMock } from "./mocks/SettlerMock.sol";

contract LiquidityMatrixRemoteTest is LiquidityMatrixTestHelper {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    address owner = makeAddr("owner");
    address[] users;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        local = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[EID_LOCAL], localSyncer, owner);
        remote = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[EID_REMOTE], remoteSyncer, owner);
        localApp = address(new AppMock(address(local)));
        remoteApp = address(new AppMock(address(remote)));
        localSettler = address(new SettlerMock(address(local)));
        remoteSettler = address(new SettlerMock(address(remote)));
        address[] memory oapps = new address[](2);
        oapps[0] = address(local);
        oapps[1] = address(remote);
        wireOApps(address[](oapps));

        vm.deal(localApp, 10_000e18);
        vm.deal(remoteApp, 10_000e18);

        local.updateSettlerWhitelisted(localSettler, true);
        remote.updateSettlerWhitelisted(remoteSettler, true);

        ILiquidityMatrix.ChainConfig[] memory configs = new ILiquidityMatrix.ChainConfig[](1);
        configs[0] = ILiquidityMatrix.ChainConfig(EID_REMOTE, 0);
        local.configChains(configs);
        configs[0] = ILiquidityMatrix.ChainConfig(EID_LOCAL, 0);
        remote.configChains(configs);

        changePrank(localApp, localApp);
        local.registerApp(false, true, localSettler);
        local.updateRemoteApp(EID_REMOTE, address(remoteApp));

        changePrank(remoteApp, remoteApp);
        remote.registerApp(false, true, remoteSettler);
        remote.updateRemoteApp(EID_LOCAL, address(localApp));

        initialize(localStorage);
        initialize(remoteStorage);

        for (uint256 i; i < 100; ++i) {
            users.push(makeAddr(string.concat("account", vm.toString(i))));
        }

        vm.deal(localSyncer, 10_000e18);
        vm.deal(remoteSyncer, 10_000e18);
        vm.deal(users[0], 10_000e18);
        changePrank(users[0], users[0]);
    }

    function test_updateRemoteApp() public {
        changePrank(address(localApp), address(localApp));
        local.updateRemoteApp(EID_REMOTE, address(remoteApp));

        assertEq(local.getRemoteApp(address(localApp), EID_REMOTE), address(remoteApp));
    }

    function test_settleLiquidity_withEmptyData(bytes32 seed) public {
        assertEq(local.getSettledTotalLiquidity(address(localApp)), 0);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), 0);

        (, address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        (bytes32 liquidityRoot,, uint256 timestamp) = _sync(localSyncer, local);

        changePrank(localSettler, localSettler);
        (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(EID_REMOTE);
        local.settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(address(localApp), EID_REMOTE, rootTimestamp, accounts, liquidity)
        );

        for (uint256 i; i < accounts.length; ++i) {
            assertEq(
                local.getSettledRemoteLiquidity(localApp, EID_REMOTE, accounts[i]), remoteStorage.liquidity[accounts[i]]
            ); // settled
            assertEq(IAppMock(localApp).remoteLiquidity(EID_REMOTE, accounts[i]), remoteStorage.liquidity[accounts[i]]); // settled
        }
        assertEq(local.getSettledRemoteTotalLiquidity(localApp, EID_REMOTE), totalLiquidity);
        assertEq(IAppMock(localApp).remoteTotalLiquidity(EID_REMOTE), totalLiquidity);

        (bytes32 _liquidityRoot, uint256 _timestamp) = local.getLastSettledLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.getSettledTotalLiquidity(address(localApp)), totalLiquidity);
        assertEq(local.isLiquidityRootSettled(address(localApp), EID_REMOTE, timestamp), true);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), true);

        (_liquidityRoot, _timestamp) = local.getLastFinalizedLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), totalLiquidity);
        assertEq(local.areRootsFinalized(address(localApp), EID_REMOTE, timestamp), true);
    }

    function test_settleLiquidity_withDataUpdated(bytes32 seed) public {
        assertEq(local.getSettledTotalLiquidity(address(localApp)), 0);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), 0);

        (, address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        (, bytes32[] memory keys, bytes[] memory values) = _updateLocalData(remote, remoteApp, remoteStorage, seed);
        (bytes32 liquidityRoot,, uint256 timestamp) = _sync(localSyncer, local);

        changePrank(localSettler, localSettler);
        (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(EID_REMOTE);
        local.settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(address(localApp), EID_REMOTE, rootTimestamp, accounts, liquidity)
        );

        for (uint256 i; i < accounts.length; ++i) {
            assertEq(
                local.getSettledRemoteLiquidity(localApp, EID_REMOTE, accounts[i]), remoteStorage.liquidity[accounts[i]]
            ); // settled
            assertEq(IAppMock(localApp).remoteLiquidity(EID_REMOTE, accounts[i]), remoteStorage.liquidity[accounts[i]]); // settled
        }
        assertEq(local.getSettledRemoteTotalLiquidity(localApp, EID_REMOTE), totalLiquidity);
        assertEq(IAppMock(localApp).remoteTotalLiquidity(EID_REMOTE), totalLiquidity);

        (bytes32 _liquidityRoot, uint256 _timestamp) = local.getLastSettledLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.getSettledTotalLiquidity(address(localApp)), totalLiquidity);
        assertEq(local.isLiquidityRootSettled(address(localApp), EID_REMOTE, timestamp), true);
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), false);

        (_liquidityRoot, _timestamp) = local.getLastFinalizedLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, bytes32(0));
        assertEq(_timestamp, 0);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), 0);
        assertEq(local.areRootsFinalized(address(localApp), EID_REMOTE, timestamp), false);

        changePrank(localSettler, localSettler);
        local.settleData(ILiquidityMatrix.SettleDataParams(address(localApp), EID_REMOTE, rootTimestamp, keys, values));
        assertEq(local.isDataRootSettled(address(localApp), EID_REMOTE, timestamp), true);

        (_liquidityRoot, _timestamp) = local.getLastFinalizedLiquidityRoot(address(localApp), EID_REMOTE);
        assertEq(_liquidityRoot, liquidityRoot);
        assertEq(_timestamp, timestamp);
        assertEq(local.getFinalizedTotalLiquidity(address(localApp)), totalLiquidity);
        assertEq(local.areRootsFinalized(address(localApp), EID_REMOTE, timestamp), true);
    }

    function test_settleLiquidity_withSyncMappedAccountsOnlyOff(bytes32 seed) public {
        initialize(remoteStorage);
        (, address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        _sync(localSyncer, local);

        changePrank(localSettler, localSettler);
        (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(EID_REMOTE);
        local.settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(address(localApp), EID_REMOTE, rootTimestamp, accounts, liquidity)
        );

        for (uint256 i; i < accounts.length; ++i) {
            assertEq(
                local.getSettledRemoteLiquidity(localApp, EID_REMOTE, accounts[i]), remoteStorage.liquidity[accounts[i]]
            ); // settled
            assertEq(IAppMock(localApp).remoteLiquidity(EID_REMOTE, accounts[i]), remoteStorage.liquidity[accounts[i]]); // settled
        }
        assertEq(local.getSettledRemoteTotalLiquidity(localApp, EID_REMOTE), totalLiquidity); // settled
        assertEq(IAppMock(localApp).remoteTotalLiquidity(EID_REMOTE), totalLiquidity); // settled
    }

    function test_settleLiquidity_withSyncMappedAccountsOnlyOn(bytes32 seed) public {
        // turn on syncMappedAccountsOnly
        changePrank(localApp, localApp);
        local.updateSyncMappedAccountsOnly(true);

        (, address[] memory accounts, int256[] memory liquidity,) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        _sync(localSyncer, local);

        changePrank(localSettler, localSettler);
        (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(EID_REMOTE);
        local.settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(address(localApp), EID_REMOTE, rootTimestamp, accounts, liquidity)
        );

        for (uint256 i; i < accounts.length; ++i) {
            assertEq(local.getSettledRemoteLiquidity(localApp, EID_REMOTE, accounts[i]), 0); // not settled
            assertEq(IAppMock(localApp).remoteLiquidity(EID_REMOTE, accounts[i]), 0); // not settled
        }
        assertEq(local.getSettledRemoteTotalLiquidity(localApp, EID_REMOTE), 0); // not settled
        assertEq(IAppMock(localApp).remoteTotalLiquidity(EID_REMOTE), 0); // not settled
    }

    function test_settleLiquidity_withUseCallbacksOff(bytes32 seed) public {
        // turn off useCallbacks
        changePrank(localApp, localApp);
        local.updateUseCallbacks(false);

        initialize(remoteStorage);
        (, address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        _sync(localSyncer, local);

        changePrank(localSettler, localSettler);
        (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(EID_REMOTE);
        local.settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(address(localApp), EID_REMOTE, rootTimestamp, accounts, liquidity)
        );

        for (uint256 i; i < accounts.length; ++i) {
            assertEq(
                local.getSettledRemoteLiquidity(localApp, EID_REMOTE, accounts[i]), remoteStorage.liquidity[accounts[i]]
            );
            assertEq(IAppMock(localApp).remoteLiquidity(EID_REMOTE, accounts[i]), 0); // since callback not used
        }
        assertEq(local.getSettledRemoteTotalLiquidity(localApp, EID_REMOTE), totalLiquidity);
        assertEq(IAppMock(localApp).remoteTotalLiquidity(EID_REMOTE), 0); // since callback not used
    }

    function test_settleLiquidity_withAccountsMapped(bytes32 seed) public {
        _requestMapRemoteAccounts(remote, remoteApp, local, localApp, users);
        for (uint256 i; i < users.length; ++i) {
            assertNotEq(mappedAccounts[EID_REMOTE][EID_LOCAL][users[i]], address(0));
        }

        (, address[] memory accounts, int256[] memory liquidity, int256 totalLiquidity) =
            _updateLocalLiquidity(remote, remoteApp, remoteStorage, users, seed);
        _sync(localSyncer, local);

        changePrank(localSettler, localSettler);
        (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(EID_REMOTE);
        local.settleLiquidity(
            ILiquidityMatrix.SettleLiquidityParams(address(localApp), EID_REMOTE, rootTimestamp, accounts, liquidity)
        );

        for (uint256 i; i < accounts.length; ++i) {
            address mapped = local.getMappedAccount(localApp, EID_REMOTE, accounts[i]);
            assertEq(mapped, mappedAccounts[EID_REMOTE][EID_LOCAL][accounts[i]]);
            assertEq(
                local.getSettledRemoteLiquidity(localApp, EID_REMOTE, mapped), remoteStorage.liquidity[accounts[i]]
            );
            assertEq(IAppMock(localApp).remoteLiquidity(EID_REMOTE, mapped), remoteStorage.liquidity[accounts[i]]);
        }
        assertEq(IAppMock(localApp).remoteTotalLiquidity(EID_REMOTE), totalLiquidity);
    }

    function test_settleData(bytes32 seed) public {
        (, bytes32[] memory keys, bytes[] memory values) = _updateLocalData(remote, remoteApp, remoteStorage, seed);
        _sync(localSyncer, local);

        changePrank(localSettler, localSettler);
        (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(EID_REMOTE);
        local.settleData(ILiquidityMatrix.SettleDataParams(address(localApp), EID_REMOTE, rootTimestamp, keys, values));

        for (uint256 i; i < keys.length; ++i) {
            assertEq(local.getSettledRemoteDataHash(localApp, EID_REMOTE, keys[i]), keccak256(values[i]));
            assertEq(IAppMock(localApp).remoteData(EID_REMOTE, keys[i]), values[i]);
        }
    }
}
