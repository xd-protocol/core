// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { RemoteAppChronicle } from "../../src/chronicles/RemoteAppChronicle.sol";
import { IRemoteAppChronicle } from "../../src/interfaces/IRemoteAppChronicle.sol";
import { ILiquidityMatrix } from "../../src/interfaces/ILiquidityMatrix.sol";
import { ILiquidityMatrixHook } from "../../src/interfaces/ILiquidityMatrixHook.sol";

/**
 * @title RemoteAppChronicleTest
 * @notice Comprehensive tests for RemoteAppChronicle functionality
 * @dev Tests all major functions including constructor, settlement operations,
 *      view functions, access control, and hook integration
 */
contract RemoteAppChronicleTest is Test {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    RemoteAppChronicle chronicle;
    address liquidityMatrix;
    address app;
    address settler;
    address unauthorizedUser;
    bytes32 constant CHAIN_UID = keccak256("test_chain");
    uint256 constant VERSION = 1;
    uint64 constant TIMESTAMP_1 = 1000;
    uint64 constant TIMESTAMP_2 = 2000;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SettleLiquidity(uint64 indexed timestamp, bytes32 indexed liquidityRoot);
    event SettleData(uint64 indexed timestamp, bytes32 indexed dataRoot);
    event OnSettleLiquidityFailure(uint64 indexed timestamp, address indexed account, int256 liquidity, bytes reason);
    event OnSettleTotalLiquidityFailure(uint64 indexed timestamp, int256 totalLiquidity, bytes reason);
    event OnSettleDataFailure(uint64 indexed timestamp, bytes32 indexed key, bytes value, bytes reason);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        liquidityMatrix = makeAddr("liquidityMatrix");
        app = makeAddr("app");
        settler = makeAddr("settler");
        unauthorizedUser = makeAddr("unauthorizedUser");

        // Mock LiquidityMatrix.getAppSetting to return our settler
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getAppSetting.selector, app),
            abi.encode(true, false, false, settler) // registered, syncMappedAccountsOnly, useHook, settler
        );

        // Mock LiquidityMatrix.getRemoteApp to return valid remote app info
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getRemoteApp.selector, app, CHAIN_UID),
            abi.encode(app, uint256(0)) // remoteApp, appIndex
        );

        // Mock getMappedAccount to return zero address (no mapping)
        vm.mockCall(
            liquidityMatrix, abi.encodeWithSelector(ILiquidityMatrix.getMappedAccount.selector), abi.encode(address(0))
        );

        chronicle = new RemoteAppChronicle(liquidityMatrix, app, CHAIN_UID, VERSION);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public {
        RemoteAppChronicle newChronicle = new RemoteAppChronicle(liquidityMatrix, app, CHAIN_UID, VERSION);

        assertEq(newChronicle.liquidityMatrix(), liquidityMatrix);
        assertEq(newChronicle.app(), app);
        assertEq(newChronicle.chainUID(), CHAIN_UID);
        assertEq(newChronicle.version(), VERSION);
    }

    function test_constructor_withDifferentParams() public {
        address differentMatrix = makeAddr("differentMatrix");
        address differentApp = makeAddr("differentApp");
        bytes32 differentChainUID = keccak256("different_chain");
        uint256 differentVersion = 5;

        RemoteAppChronicle newChronicle =
            new RemoteAppChronicle(differentMatrix, differentApp, differentChainUID, differentVersion);

        assertEq(newChronicle.liquidityMatrix(), differentMatrix);
        assertEq(newChronicle.app(), differentApp);
        assertEq(newChronicle.chainUID(), differentChainUID);
        assertEq(newChronicle.version(), differentVersion);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIAL STATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialState() public {
        // Initial settlement status should be false
        assertFalse(chronicle.isLiquiditySettled(TIMESTAMP_1));
        assertFalse(chronicle.isDataSettled(TIMESTAMP_1));
        assertFalse(chronicle.isFinalized(TIMESTAMP_1));

        // Initial liquidity should be 0
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), 0);
        assertEq(chronicle.getLiquidityAt(makeAddr("account"), TIMESTAMP_1), 0);

        // Initial data should be empty
        assertEq(chronicle.getDataAt(keccak256("key"), TIMESTAMP_1).length, 0);

        // Last timestamps should be 0 (empty)
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), 0);
        assertEq(chronicle.getLastSettledDataTimestamp(), 0);
        assertEq(chronicle.getLastFinalizedTimestamp(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        settleLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleLiquidity() public {
        bytes32 liquidityRoot = keccak256("test_liquidity_root"); // Use standard test root
        address[] memory accounts = new address[](2);
        int256[] memory liquidity = new int256[](2);
        accounts[0] = makeAddr("alice");
        accounts[1] = makeAddr("bob");
        liquidity[0] = 1000;
        liquidity[1] = 500;

        // For single-node Merkle tree: root = keccak256(abi.encodePacked(key, value))
        // where key = bytes32(uint256(uint160(app))) and value = liquidityRoot
        bytes32 expectedTopRoot = keccak256(abi.encodePacked(bytes32(uint256(uint160(app))), liquidityRoot));

        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSignature("getRemoteLiquidityRootAt(bytes32,uint256,uint64)", CHAIN_UID, VERSION, TIMESTAMP_1),
            abi.encode(expectedTopRoot)
        );

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            liquidityRoot: liquidityRoot,
            proof: new bytes32[](0) // Empty proof for simplicity
         });

        // For this test, we'll create a scenario where the liquidityRoot equals the topLiquidityRoot
        // making the Merkle proof verification trivial (empty proof, root equals value)
        // This simulates a single-node tree where the app's root is the top root

        vm.prank(settler);
        vm.expectEmit(true, true, false, true);
        emit SettleLiquidity(TIMESTAMP_1, liquidityRoot);

        chronicle.settleLiquidity(params);

        // Verify settlement status
        assertTrue(chronicle.isLiquiditySettled(TIMESTAMP_1));
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), TIMESTAMP_1);

        // Verify liquidity values
        assertEq(chronicle.getLiquidityAt(accounts[0], TIMESTAMP_1), liquidity[0]);
        assertEq(chronicle.getLiquidityAt(accounts[1], TIMESTAMP_1), liquidity[1]);
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), liquidity[0] + liquidity[1]);
    }

    function test_settleLiquidity_revertUnauthorized() public {
        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: new address[](0),
            liquidity: new int256[](0),
            liquidityRoot: bytes32(0),
            proof: new bytes32[](0)
        });

        vm.prank(unauthorizedUser);
        vm.expectRevert(IRemoteAppChronicle.Forbidden.selector);
        chronicle.settleLiquidity(params);
    }

    function test_settleLiquidity_revertAlreadySettled() public {
        // First settlement
        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: new address[](1),
            liquidity: new int256[](1),
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });
        params.accounts[0] = makeAddr("alice");
        params.liquidity[0] = 100;

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        // Second settlement should revert
        vm.prank(settler);
        vm.expectRevert(IRemoteAppChronicle.LiquidityAlreadySettled.selector);
        chronicle.settleLiquidity(params);
    }

    function test_settleLiquidity_revertRootNotReceived() public {
        // Mock that no root is received
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSignature("getRemoteLiquidityRootAt(bytes32,uint256,uint64)", CHAIN_UID, VERSION, TIMESTAMP_1),
            abi.encode(bytes32(0)) // No root received
        );

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: new address[](0),
            liquidity: new int256[](0),
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        vm.expectRevert(IRemoteAppChronicle.RootNotReceived.selector);
        chronicle.settleLiquidity(params);
    }

    function test_settleLiquidity_revertRemoteAppNotSet() public {
        // Mock that we have a remote root (to pass the first check)
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSignature("getRemoteLiquidityRootAt(bytes32,uint256,uint64)", CHAIN_UID, VERSION, TIMESTAMP_1),
            abi.encode(keccak256("some_root"))
        );

        // Mock that remote app is not set - use specific parameters
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getRemoteApp.selector, app, CHAIN_UID),
            abi.encode(address(0), uint256(0)) // No remote app set
        );

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: new address[](0),
            liquidity: new int256[](0),
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        vm.expectRevert(IRemoteAppChronicle.RemoteAppNotSet.selector);
        chronicle.settleLiquidity(params);
    }

    function test_settleLiquidity_withAccountMapping() public {
        address remoteAccount = makeAddr("remoteAccount");
        address localAccount = makeAddr("localAccount");
        int256 liquidityAmount = 1000;

        // Mock account mapping
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getMappedAccount.selector, app, CHAIN_UID, remoteAccount),
            abi.encode(localAccount)
        );

        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        accounts[0] = remoteAccount;
        liquidity[0] = liquidityAmount;

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        // Liquidity should be stored under the mapped local account
        assertEq(chronicle.getLiquidityAt(localAccount, TIMESTAMP_1), liquidityAmount);
        assertEq(chronicle.getLiquidityAt(remoteAccount, TIMESTAMP_1), 0);
    }

    function test_settleLiquidity_withSyncMappedAccountsOnly() public {
        // Mock app setting to sync mapped accounts only
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getAppSetting.selector, app),
            abi.encode(true, true, false, settler) // syncMappedAccountsOnly = true
        );

        address unmappedAccount = makeAddr("unmappedAccount");
        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        accounts[0] = unmappedAccount;
        liquidity[0] = 1000;

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        // Unmapped account should be skipped
        assertEq(chronicle.getLiquidityAt(unmappedAccount, TIMESTAMP_1), 0);
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        settleData() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleData() public {
        bytes32 dataRoot = keccak256("test_data_root"); // Use standard test root
        bytes32[] memory keys = new bytes32[](2);
        bytes[] memory values = new bytes[](2);
        keys[0] = keccak256("key1");
        keys[1] = keccak256("key2");
        values[0] = "value1";
        values[1] = "value2";

        _setupValidDataSettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleDataParams memory params = RemoteAppChronicle.SettleDataParams({
            timestamp: TIMESTAMP_1,
            keys: keys,
            values: values,
            dataRoot: dataRoot,
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        vm.expectEmit(true, true, false, true);
        emit SettleData(TIMESTAMP_1, dataRoot);

        chronicle.settleData(params);

        // Verify settlement status
        assertTrue(chronicle.isDataSettled(TIMESTAMP_1));
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_1);

        // Verify data values
        assertEq(chronicle.getDataAt(keys[0], TIMESTAMP_1), values[0]);
        assertEq(chronicle.getDataAt(keys[1], TIMESTAMP_1), values[1]);
    }

    function test_settleData_revertUnauthorized() public {
        RemoteAppChronicle.SettleDataParams memory params = RemoteAppChronicle.SettleDataParams({
            timestamp: TIMESTAMP_1,
            keys: new bytes32[](0),
            values: new bytes[](0),
            dataRoot: bytes32(0),
            proof: new bytes32[](0)
        });

        vm.prank(unauthorizedUser);
        vm.expectRevert(IRemoteAppChronicle.Forbidden.selector);
        chronicle.settleData(params);
    }

    function test_settleData_revertAlreadySettled() public {
        // First settlement
        _setupValidDataSettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleDataParams memory params = RemoteAppChronicle.SettleDataParams({
            timestamp: TIMESTAMP_1,
            keys: new bytes32[](1),
            values: new bytes[](1),
            dataRoot: keccak256("test_data_root"),
            proof: new bytes32[](0)
        });
        params.keys[0] = keccak256("key");
        params.values[0] = "value";

        vm.prank(settler);
        chronicle.settleData(params);

        // Second settlement should revert
        vm.prank(settler);
        vm.expectRevert(IRemoteAppChronicle.DataAlreadySettled.selector);
        chronicle.settleData(params);
    }

    function test_settleData_revertRootNotReceived() public {
        // Mock that no root is received
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSignature("getRemoteDataRootAt(bytes32,uint256,uint64)", CHAIN_UID, VERSION, TIMESTAMP_1),
            abi.encode(bytes32(0)) // No root received
        );

        RemoteAppChronicle.SettleDataParams memory params = RemoteAppChronicle.SettleDataParams({
            timestamp: TIMESTAMP_1,
            keys: new bytes32[](0),
            values: new bytes[](0),
            dataRoot: keccak256("test_data_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        vm.expectRevert(IRemoteAppChronicle.RootNotReceived.selector);
        chronicle.settleData(params);
    }

    /*//////////////////////////////////////////////////////////////
                        FINALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_finalization_bothSettled() public {
        // Settle liquidity first
        _setupAndSettleLiquidity(TIMESTAMP_1);

        assertFalse(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), 0);

        // Settle data - should trigger finalization
        _setupAndSettleData(TIMESTAMP_1);

        assertTrue(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);
    }

    function test_finalization_reverseOrder() public {
        // Settle data first
        _setupAndSettleData(TIMESTAMP_1);

        assertFalse(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), 0);

        // Settle liquidity - should trigger finalization
        _setupAndSettleLiquidity(TIMESTAMP_1);

        assertTrue(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);
    }

    function test_finalization_multipleTimestamps() public {
        // Settle both for TIMESTAMP_1
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_1);

        // Settle only liquidity for TIMESTAMP_2
        _setupAndSettleLiquidity(TIMESTAMP_2);

        assertTrue(chronicle.isFinalized(TIMESTAMP_1));
        assertFalse(chronicle.isFinalized(TIMESTAMP_2));
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getTotalLiquidityAt_multipleTimestamps() public {
        // Settle different amounts at different timestamps
        _setupAndSettleLiquidityWithAmount(TIMESTAMP_1, 1000);
        _setupAndSettleLiquidityWithAmount(TIMESTAMP_2, 2000);

        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), 1000);
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_2), 2000);

        // Query between timestamps should return the earlier value
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1 + 500), 1000);
    }

    function test_getLiquidityAt_multipleAccounts() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        address[] memory accounts = new address[](2);
        int256[] memory liquidity = new int256[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        liquidity[0] = 1000;
        liquidity[1] = 500;

        _setupAndSettleLiquidityWithAccounts(TIMESTAMP_1, accounts, liquidity);

        assertEq(chronicle.getLiquidityAt(alice, TIMESTAMP_1), 1000);
        assertEq(chronicle.getLiquidityAt(bob, TIMESTAMP_1), 500);
        assertEq(chronicle.getLiquidityAt(makeAddr("charlie"), TIMESTAMP_1), 0);
    }

    function test_getDataAt_multipleKeys() public {
        bytes32 key1 = keccak256("config");
        bytes32 key2 = keccak256("metadata");
        bytes memory value1 = "config_data";
        bytes memory value2 = "metadata_content";

        bytes32[] memory keys = new bytes32[](2);
        bytes[] memory values = new bytes[](2);
        keys[0] = key1;
        keys[1] = key2;
        values[0] = value1;
        values[1] = value2;

        _setupAndSettleDataWithKeysValues(TIMESTAMP_1, keys, values);

        assertEq(chronicle.getDataAt(key1, TIMESTAMP_1), value1);
        assertEq(chronicle.getDataAt(key2, TIMESTAMP_1), value2);
        assertEq(chronicle.getDataAt(keccak256("nonexistent"), TIMESTAMP_1).length, 0);
    }

    function test_timestampQueries() public {
        // Settle at multiple timestamps
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_1);

        _setupAndSettleLiquidity(TIMESTAMP_2);
        // Don't settle data for TIMESTAMP_2

        // Test settled timestamp queries
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), TIMESTAMP_2);
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_1);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);

        // Test timestamp-at queries
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_2 + 500), TIMESTAMP_2);
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_2 + 500), TIMESTAMP_1);
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_2 + 500), TIMESTAMP_1);

        // Test queries before first settlement
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_1 - 1), 0);
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_1 - 1), 0);
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_1 - 1), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleLiquidity_withHooks() public {
        // Mock app setting to enable hooks
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getAppSetting.selector, app),
            abi.encode(true, false, true, settler) // useHook = true
        );

        // Mock successful hook calls
        vm.mockCall(app, abi.encodeWithSelector(ILiquidityMatrixHook.onSettleLiquidity.selector), abi.encode());
        vm.mockCall(app, abi.encodeWithSelector(ILiquidityMatrixHook.onSettleTotalLiquidity.selector), abi.encode());

        _setupAndSettleLiquidity(TIMESTAMP_1);

        // Should not emit failure events
        assertTrue(chronicle.isLiquiditySettled(TIMESTAMP_1));
    }

    function test_settleLiquidity_hookFailures() public {
        // Mock app setting to enable hooks
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getAppSetting.selector, app),
            abi.encode(true, false, true, settler) // useHook = true
        );

        // Mock hook calls to revert
        vm.mockCallRevert(app, abi.encodeWithSelector(ILiquidityMatrixHook.onSettleLiquidity.selector), "Hook failed");
        vm.mockCallRevert(
            app, abi.encodeWithSelector(ILiquidityMatrixHook.onSettleTotalLiquidity.selector), "Total hook failed"
        );

        address alice = makeAddr("alice");
        int256 liquidityAmount = 1000;

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        accounts[0] = alice;
        liquidity[0] = liquidityAmount;

        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);

        // Should emit failure events but continue with settlement
        vm.expectEmit(true, true, false, true);
        emit OnSettleLiquidityFailure(TIMESTAMP_1, alice, liquidityAmount, "Hook failed");

        vm.expectEmit(true, false, false, true);
        emit OnSettleTotalLiquidityFailure(TIMESTAMP_1, liquidityAmount, "Total hook failed");

        chronicle.settleLiquidity(params);

        // Settlement should still succeed despite hook failures
        assertTrue(chronicle.isLiquiditySettled(TIMESTAMP_1));
        assertEq(chronicle.getLiquidityAt(alice, TIMESTAMP_1), liquidityAmount);
    }

    function test_settleData_withHooks() public {
        // Mock app setting to enable hooks
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getAppSetting.selector, app),
            abi.encode(true, false, true, settler) // useHook = true
        );

        // Mock successful hook calls
        vm.mockCall(app, abi.encodeWithSelector(ILiquidityMatrixHook.onSettleData.selector), abi.encode());

        _setupAndSettleData(TIMESTAMP_1);

        assertTrue(chronicle.isDataSettled(TIMESTAMP_1));
    }

    function test_settleData_hookFailures() public {
        // Mock app setting to enable hooks
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getAppSetting.selector, app),
            abi.encode(true, false, true, settler) // useHook = true
        );

        // Mock hook calls to revert
        vm.mockCallRevert(app, abi.encodeWithSelector(ILiquidityMatrixHook.onSettleData.selector), "Data hook failed");

        bytes32 key = keccak256("testkey");
        bytes memory value = "testvalue";

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = key;
        values[0] = value;

        _setupValidDataSettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleDataParams memory params = RemoteAppChronicle.SettleDataParams({
            timestamp: TIMESTAMP_1,
            keys: keys,
            values: values,
            dataRoot: keccak256("test_data_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);

        // Should emit failure event but continue with settlement
        vm.expectEmit(true, true, false, true);
        emit OnSettleDataFailure(TIMESTAMP_1, key, value, "Data hook failed");

        chronicle.settleData(params);

        // Settlement should still succeed despite hook failure
        assertTrue(chronicle.isDataSettled(TIMESTAMP_1));
        assertEq(chronicle.getDataAt(key, TIMESTAMP_1), value);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_settleLiquidity_emptyArrays() public {
        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: new address[](0),
            liquidity: new int256[](0),
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        assertTrue(chronicle.isLiquiditySettled(TIMESTAMP_1));
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), 0);
    }

    function test_settleData_emptyArrays() public {
        _setupValidDataSettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleDataParams memory params = RemoteAppChronicle.SettleDataParams({
            timestamp: TIMESTAMP_1,
            keys: new bytes32[](0),
            values: new bytes[](0),
            dataRoot: keccak256("test_data_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleData(params);

        assertTrue(chronicle.isDataSettled(TIMESTAMP_1));
    }

    function test_settleLiquidity_negativeLiquidity() public {
        address alice = makeAddr("alice");
        int256 negativeLiquidity = -500;

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        accounts[0] = alice;
        liquidity[0] = negativeLiquidity;

        _setupAndSettleLiquidityWithAccounts(TIMESTAMP_1, accounts, liquidity);

        assertEq(chronicle.getLiquidityAt(alice, TIMESTAMP_1), negativeLiquidity);
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), negativeLiquidity);
    }

    function test_settleData_emptyValues() public {
        bytes32 key = keccak256("emptykey");
        bytes memory emptyValue = "";

        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = key;
        values[0] = emptyValue;

        _setupAndSettleDataWithKeysValues(TIMESTAMP_1, keys, values);

        assertEq(chronicle.getDataAt(key, TIMESTAMP_1), emptyValue);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_complexSettlementScenario() public {
        // Multiple accounts with mixed positive/negative liquidity
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address charlie = makeAddr("charlie");

        address[] memory accounts = new address[](3);
        int256[] memory liquidity = new int256[](3);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = charlie;
        liquidity[0] = 1000;
        liquidity[1] = -200;
        liquidity[2] = 500;

        _setupAndSettleLiquidityWithAccounts(TIMESTAMP_1, accounts, liquidity);

        // Multiple data keys with different types
        bytes32[] memory keys = new bytes32[](3);
        bytes[] memory values = new bytes[](3);
        keys[0] = keccak256("config");
        keys[1] = keccak256("metadata");
        keys[2] = keccak256("empty");
        values[0] = abi.encode(uint256(42), true, "test");
        values[1] = "metadata_string";
        values[2] = "";

        _setupAndSettleDataWithKeysValues(TIMESTAMP_1, keys, values);

        // Verify final state
        assertTrue(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLiquidityAt(alice, TIMESTAMP_1), 1000);
        assertEq(chronicle.getLiquidityAt(bob, TIMESTAMP_1), -200);
        assertEq(chronicle.getLiquidityAt(charlie, TIMESTAMP_1), 500);
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), 1300);

        assertEq(chronicle.getDataAt(keys[0], TIMESTAMP_1), values[0]);
        assertEq(chronicle.getDataAt(keys[1], TIMESTAMP_1), values[1]);
        assertEq(chronicle.getDataAt(keys[2], TIMESTAMP_1), values[2]);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setupValidLiquiditySettlement() internal {
        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);
    }

    function _setupValidLiquiditySettlementForTimestamp(uint64 timestamp) internal {
        bytes32 liquidityRoot = keccak256("test_liquidity_root");
        bytes32 expectedTopRoot = keccak256(abi.encodePacked(bytes32(uint256(uint160(app))), liquidityRoot));

        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSignature("getRemoteLiquidityRootAt(bytes32,uint256,uint64)", CHAIN_UID, VERSION, timestamp),
            abi.encode(expectedTopRoot)
        );
    }

    function _setupValidDataSettlement() internal {
        _setupValidDataSettlementForTimestamp(TIMESTAMP_1);
    }

    function _setupValidDataSettlementForTimestamp(uint64 timestamp) internal {
        bytes32 dataRoot = keccak256("test_data_root");
        bytes32 expectedTopRoot = keccak256(abi.encodePacked(bytes32(uint256(uint160(app))), dataRoot));

        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSignature("getRemoteDataRootAt(bytes32,uint256,uint64)", CHAIN_UID, VERSION, timestamp),
            abi.encode(expectedTopRoot)
        );
    }

    function _setupAndSettleLiquidity(uint64 timestamp) internal {
        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        accounts[0] = makeAddr("defaultAccount");
        liquidity[0] = 1000;

        _setupAndSettleLiquidityWithAccounts(timestamp, accounts, liquidity);
    }

    function _setupAndSettleLiquidityWithAmount(uint64 timestamp, int256 amount) internal {
        _setupValidLiquiditySettlementForTimestamp(timestamp);

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        accounts[0] = makeAddr("defaultAccount");
        liquidity[0] = amount;

        _setupAndSettleLiquidityWithAccounts(timestamp, accounts, liquidity);
    }

    function _setupAndSettleLiquidityWithAccounts(
        uint64 timestamp,
        address[] memory accounts,
        int256[] memory liquidity
    ) internal {
        _setupValidLiquiditySettlementForTimestamp(timestamp);

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: timestamp,
            accounts: accounts,
            liquidity: liquidity,
            liquidityRoot: keccak256("test_liquidity_root"), // Match the helper function
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);
    }

    function _setupAndSettleData(uint64 timestamp) internal {
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = keccak256("defaultKey");
        values[0] = "defaultValue";

        _setupAndSettleDataWithKeysValues(timestamp, keys, values);
    }

    function _setupAndSettleDataWithKeysValues(uint64 timestamp, bytes32[] memory keys, bytes[] memory values)
        internal
    {
        _setupValidDataSettlementForTimestamp(timestamp);

        RemoteAppChronicle.SettleDataParams memory params = RemoteAppChronicle.SettleDataParams({
            timestamp: timestamp,
            keys: keys,
            values: values,
            dataRoot: keccak256("test_data_root"), // Match the helper function
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleData(params);
    }
}
