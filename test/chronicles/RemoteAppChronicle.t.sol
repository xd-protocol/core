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
    uint64 constant TIMESTAMP_3 = 3000;

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
        bool[] memory isContract = new bool[](2);
        accounts[0] = makeAddr("alice");
        accounts[1] = makeAddr("bob");
        liquidity[0] = 1000;
        liquidity[1] = 500;
        isContract[0] = false; // alice is EOA
        isContract[1] = false; // bob is EOA

        // For single-node Merkle tree: root = keccak256(abi.encodePacked(key, value))
        // where key = bytes32(uint256(uint160(app))) and value = liquidityRoot
        bytes32 expectedTopRoot = keccak256(abi.encodePacked(bytes32(uint256(uint160(app))), liquidityRoot));

        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSignature("getRemoteLiquidityRootAt(bytes32,uint256,uint64)", CHAIN_UID, VERSION, TIMESTAMP_1),
            abi.encode(expectedTopRoot)
        );

        // Calculate total liquidity for test
        int256 totalLiq = 0;
        for (uint256 i = 0; i < liquidity.length; i++) {
            totalLiq += liquidity[i];
        }

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: totalLiq,
            liquidityRoot: liquidityRoot,
            proof: new bytes32[](0)
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
            isContract: new bool[](0),
            totalLiquidity: 0,
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
            isContract: new bool[](1),
            totalLiquidity: 100,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });
        params.accounts[0] = makeAddr("alice");
        params.liquidity[0] = 100;
        params.isContract[0] = false;

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
            isContract: new bool[](0),
            totalLiquidity: 0,
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
            isContract: new bool[](0),
            totalLiquidity: 0,
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
        bool[] memory isContract = new bool[](1);
        accounts[0] = remoteAccount;
        liquidity[0] = liquidityAmount;
        isContract[0] = false; // EOA

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: liquidityAmount,
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
        bool[] memory isContract = new bool[](1);
        accounts[0] = unmappedAccount;
        liquidity[0] = 1000;
        isContract[0] = false; // EOA

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: 1000,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        // NEW BEHAVIOR: Unmapped EOA is always tracked regardless of syncMappedAccountsOnly
        assertEq(chronicle.getLiquidityAt(unmappedAccount, TIMESTAMP_1), 1000);
        // Total liquidity is also set to settler's provided value
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), 1000);
    }

    /*//////////////////////////////////////////////////////////////
                CONTRACT MAPPING TESTS  
    //////////////////////////////////////////////////////////////*/

    function test_settleLiquidity_unmappedContract_skipped() public {
        // NEW BEHAVIOR: Unmapped contracts are tracked when syncMappedAccountsOnly=false (default)
        address contractAccount = makeAddr("contractAccount");
        int256 liquidityAmount = 1000;

        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        bool[] memory isContract = new bool[](1);
        accounts[0] = contractAccount;
        liquidity[0] = liquidityAmount;
        isContract[0] = true; // Mark as contract

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: liquidityAmount,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        // NEW BEHAVIOR: Contract is tracked when syncMappedAccountsOnly=false
        assertEq(chronicle.getLiquidityAt(contractAccount, TIMESTAMP_1), liquidityAmount);
        // Total liquidity is also set
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), liquidityAmount);
    }

    function test_settleLiquidity_unmappedContract_skipped_syncMappedAccountsOnlyTrue() public {
        // Even with syncMappedAccountsOnly=true, unmapped contracts should be skipped
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getAppSetting.selector, app),
            abi.encode(true, true, false, settler) // syncMappedAccountsOnly = true
        );

        address contractAccount = makeAddr("contractAccount");
        int256 liquidityAmount = 1000;

        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        bool[] memory isContract = new bool[](1);
        accounts[0] = contractAccount;
        liquidity[0] = liquidityAmount;
        isContract[0] = true; // Mark as contract

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: liquidityAmount,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        // Contract should be skipped - liquidity not settled
        assertEq(chronicle.getLiquidityAt(contractAccount, TIMESTAMP_1), 0);
        // But total liquidity is still set
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), liquidityAmount);
    }

    function test_settleLiquidity_mappedContract_settled() public {
        // Mapped contracts should be settled using their mapped address
        address remoteContract = makeAddr("remoteContract");
        address localContract = makeAddr("localContract");
        int256 liquidityAmount = 1000;

        // Mock contract mapping
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getMappedAccount.selector, app, CHAIN_UID, remoteContract),
            abi.encode(localContract)
        );

        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        bool[] memory isContract = new bool[](1);
        accounts[0] = remoteContract;
        liquidity[0] = liquidityAmount;
        isContract[0] = true; // Mark as contract

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: liquidityAmount,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        // Liquidity should be stored under the mapped local contract
        assertEq(chronicle.getLiquidityAt(localContract, TIMESTAMP_1), liquidityAmount);
        assertEq(chronicle.getLiquidityAt(remoteContract, TIMESTAMP_1), 0);
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), liquidityAmount);
    }

    function test_settleLiquidity_mixedAccountTypes() public {
        // Test with mix of EOAs and contracts (mapped and unmapped)
        address eoaUnmapped = makeAddr("eoaUnmapped");
        address eoaMapped = makeAddr("eoaMapped");
        address eoaMappedLocal = makeAddr("eoaMappedLocal");
        address contractUnmapped = makeAddr("contractUnmapped");
        address contractMapped = makeAddr("contractMapped");
        address contractMappedLocal = makeAddr("contractMappedLocal");

        // Mock mappings
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getMappedAccount.selector, app, CHAIN_UID, eoaMapped),
            abi.encode(eoaMappedLocal)
        );
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getMappedAccount.selector, app, CHAIN_UID, contractMapped),
            abi.encode(contractMappedLocal)
        );

        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        address[] memory accounts = new address[](4);
        int256[] memory liquidity = new int256[](4);
        bool[] memory isContract = new bool[](4);

        accounts[0] = eoaUnmapped;
        liquidity[0] = 100;
        isContract[0] = false;

        accounts[1] = eoaMapped;
        liquidity[1] = 200;
        isContract[1] = false;

        accounts[2] = contractUnmapped;
        liquidity[2] = 300;
        isContract[2] = true;

        accounts[3] = contractMapped;
        liquidity[3] = 400;
        isContract[3] = true;

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: 1000,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);

        // EOA unmapped: uses original address
        assertEq(chronicle.getLiquidityAt(eoaUnmapped, TIMESTAMP_1), 100);

        // EOA mapped: uses mapped address
        assertEq(chronicle.getLiquidityAt(eoaMappedLocal, TIMESTAMP_1), 200);
        assertEq(chronicle.getLiquidityAt(eoaMapped, TIMESTAMP_1), 0);

        // Contract unmapped: tracked when syncMappedAccountsOnly=false (default)
        assertEq(chronicle.getLiquidityAt(contractUnmapped, TIMESTAMP_1), 300);

        // Contract mapped: uses mapped address
        assertEq(chronicle.getLiquidityAt(contractMappedLocal, TIMESTAMP_1), 400);
        assertEq(chronicle.getLiquidityAt(contractMapped, TIMESTAMP_1), 0);

        // Total liquidity still includes all
        assertEq(chronicle.getTotalLiquidityAt(TIMESTAMP_1), 1000);
    }

    function test_settleLiquidity_arrayLengthMismatch_reverts() public {
        // Test that mismatched array lengths revert
        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        address[] memory accounts = new address[](2);
        int256[] memory liquidity = new int256[](2);
        bool[] memory isContract = new bool[](1); // Wrong length

        accounts[0] = makeAddr("account1");
        accounts[1] = makeAddr("account2");
        liquidity[0] = 100;
        liquidity[1] = 200;
        isContract[0] = false;

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: 300,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        vm.expectRevert(IRemoteAppChronicle.InvalidArrayLengths.selector);
        chronicle.settleLiquidity(params);
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

    function test_getLastSettledLiquidityTimestamp_empty() public view {
        // Should return 0 when no liquidity has been settled
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), 0);
    }

    function test_getLastSettledLiquidityTimestamp_singleSettlement() public {
        // Settle liquidity at TIMESTAMP_1
        _setupAndSettleLiquidity(TIMESTAMP_1);

        // Should return TIMESTAMP_1
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), TIMESTAMP_1);
    }

    function test_getLastSettledLiquidityTimestamp_multipleSettlementsChronological() public {
        // Settle liquidity at multiple timestamps in chronological order
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleLiquidity(TIMESTAMP_2);
        _setupAndSettleLiquidity(TIMESTAMP_3);

        // Should return the maximum timestamp (TIMESTAMP_3)
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), TIMESTAMP_3);
    }

    function test_getLastSettledLiquidityTimestamp_revertOnChronologicalOrder() public {
        // First settle at a later timestamp
        _setupAndSettleLiquidity(TIMESTAMP_2);

        // Attempting to settle at an earlier timestamp should revert
        // RemoteAppChronicle now enforces chronological order
        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: new address[](1),
            liquidity: new int256[](1),
            isContract: new bool[](1),
            totalLiquidity: 100,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });
        params.accounts[0] = makeAddr("alice");
        params.liquidity[0] = 100;
        params.isContract[0] = false;

        vm.prank(settler);
        vm.expectRevert(IRemoteAppChronicle.StaleTimestamp.selector);
        chronicle.settleLiquidity(params);

        // The last timestamp should still be TIMESTAMP_2
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), TIMESTAMP_2);
    }

    function test_getLastSettledLiquidityTimestamp_doesNotChangeOnDataSettlement() public {
        // Settle liquidity at TIMESTAMP_1
        _setupAndSettleLiquidity(TIMESTAMP_1);
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), TIMESTAMP_1);

        // Settle data at TIMESTAMP_2 (without liquidity)
        _setupAndSettleData(TIMESTAMP_2);

        // Should still return TIMESTAMP_1 (last liquidity settlement)
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), TIMESTAMP_1);
    }

    function test_getLastSettledLiquidityTimestamp_handlesGapInTimestamps() public {
        // Settle at non-consecutive timestamps (must be in increasing order due to SnapshotsLib constraint)
        uint64 timestamp1 = 1000;
        uint64 timestamp2 = 5000;
        uint64 timestamp3 = 10_000;

        _setupAndSettleLiquidity(timestamp1);
        _setupAndSettleLiquidity(timestamp2);
        _setupAndSettleLiquidity(timestamp3);

        // Should return the maximum timestamp
        assertEq(chronicle.getLastSettledLiquidityTimestamp(), timestamp3);
    }

    function testFuzz_getLastSettledLiquidityTimestamp(uint64[] memory timestamps) public {
        vm.assume(timestamps.length > 0 && timestamps.length <= 10);

        // Sort timestamps to avoid StaleTimestamp errors from SnapshotsLib
        // Use simple bubble sort for small arrays
        for (uint256 i = 0; i < timestamps.length; i++) {
            for (uint256 j = i + 1; j < timestamps.length; j++) {
                if (timestamps[i] > timestamps[j]) {
                    uint64 temp = timestamps[i];
                    timestamps[i] = timestamps[j];
                    timestamps[j] = temp;
                }
            }
        }

        uint64 maxTimestamp = 0;
        uint64 lastSettled = 0;
        for (uint256 i = 0; i < timestamps.length; i++) {
            // Skip duplicates and timestamps that would cause StaleTimestamp
            if (timestamps[i] <= lastSettled) {
                continue;
            }

            _setupAndSettleLiquidity(timestamps[i]);
            lastSettled = timestamps[i];
            maxTimestamp = timestamps[i];
        }

        // Should always return the maximum settled timestamp
        if (maxTimestamp > 0) {
            assertEq(chronicle.getLastSettledLiquidityTimestamp(), maxTimestamp);
        } else {
            assertEq(chronicle.getLastSettledLiquidityTimestamp(), 0);
        }
    }

    function test_getSettledLiquidityTimestampAt_empty() public view {
        // Should return 0 when no liquidity has been settled
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_1), 0);
        assertEq(chronicle.getSettledLiquidityTimestampAt(0), 0);
        assertEq(chronicle.getSettledLiquidityTimestampAt(type(uint64).max), 0);
    }

    function test_getSettledLiquidityTimestampAt_singleSettlement() public {
        // Settle liquidity at TIMESTAMP_2
        _setupAndSettleLiquidity(TIMESTAMP_2);

        // Query before the settlement should return 0
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_1), 0);

        // Query at exact timestamp should return that timestamp
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_2), TIMESTAMP_2);

        // Query after the settlement should return TIMESTAMP_2
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_3), TIMESTAMP_2);
        assertEq(chronicle.getSettledLiquidityTimestampAt(type(uint64).max), TIMESTAMP_2);
    }

    function test_getSettledLiquidityTimestampAt_multipleSettlements() public {
        // Settle at multiple timestamps
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleLiquidity(TIMESTAMP_2);
        _setupAndSettleLiquidity(TIMESTAMP_3);

        // Query before first settlement
        assertEq(chronicle.getSettledLiquidityTimestampAt(500), 0);

        // Query at exact timestamps
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_1), TIMESTAMP_1);
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_2), TIMESTAMP_2);
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_3), TIMESTAMP_3);

        // Query between timestamps
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_1 + 100), TIMESTAMP_1);
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_2 + 100), TIMESTAMP_2);

        // Query after last timestamp
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_3 + 1000), TIMESTAMP_3);
    }

    function test_getSettledLiquidityTimestampAt_withGaps() public {
        // Settle with large gaps between timestamps
        uint64 timestamp1 = 100;
        uint64 timestamp2 = 10_000;
        uint64 timestamp3 = 50_000;

        _setupAndSettleLiquidity(timestamp1);
        _setupAndSettleLiquidity(timestamp2);
        _setupAndSettleLiquidity(timestamp3);

        // Test various query points
        assertEq(chronicle.getSettledLiquidityTimestampAt(50), 0);
        assertEq(chronicle.getSettledLiquidityTimestampAt(100), timestamp1);
        assertEq(chronicle.getSettledLiquidityTimestampAt(5000), timestamp1);
        assertEq(chronicle.getSettledLiquidityTimestampAt(10_000), timestamp2);
        assertEq(chronicle.getSettledLiquidityTimestampAt(30_000), timestamp2);
        assertEq(chronicle.getSettledLiquidityTimestampAt(50_000), timestamp3);
        assertEq(chronicle.getSettledLiquidityTimestampAt(100_000), timestamp3);
    }

    function test_getSettledLiquidityTimestampAt_boundaryConditions() public {
        // Test with boundary values
        uint64 minTimestamp = 1;
        uint64 maxTimestamp = type(uint64).max - 1;

        _setupAndSettleLiquidity(minTimestamp);
        _setupAndSettleLiquidity(maxTimestamp);

        // Query at 0 should return 0 (before first settlement)
        assertEq(chronicle.getSettledLiquidityTimestampAt(0), 0);

        // Query at minTimestamp should return minTimestamp
        assertEq(chronicle.getSettledLiquidityTimestampAt(minTimestamp), minTimestamp);

        // Query in the middle should return minTimestamp
        assertEq(chronicle.getSettledLiquidityTimestampAt(type(uint64).max / 2), minTimestamp);

        // Query at max should return maxTimestamp
        assertEq(chronicle.getSettledLiquidityTimestampAt(type(uint64).max), maxTimestamp);
    }

    function test_getSettledLiquidityTimestampAt_manySettlements() public {
        // Test with many settlements to verify O(log n) binary search
        uint64[] memory timestamps = new uint64[](20);
        for (uint256 i = 0; i < 20; i++) {
            timestamps[i] = uint64(1000 * (i + 1));
            _setupAndSettleLiquidity(timestamps[i]);
        }

        // Test binary search is working correctly
        assertEq(chronicle.getSettledLiquidityTimestampAt(500), 0);
        assertEq(chronicle.getSettledLiquidityTimestampAt(1500), timestamps[0]);
        assertEq(chronicle.getSettledLiquidityTimestampAt(5500), timestamps[4]);
        assertEq(chronicle.getSettledLiquidityTimestampAt(10_500), timestamps[9]);
        assertEq(chronicle.getSettledLiquidityTimestampAt(15_500), timestamps[14]);
        assertEq(chronicle.getSettledLiquidityTimestampAt(20_500), timestamps[19]);
    }

    function test_getSettledLiquidityTimestampAt_independentFromData() public {
        // Settle liquidity at TIMESTAMP_1 and TIMESTAMP_3
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleLiquidity(TIMESTAMP_3);

        // Settle data at TIMESTAMP_2 (without liquidity)
        _setupAndSettleData(TIMESTAMP_2);

        // Query at TIMESTAMP_2 should return TIMESTAMP_1 (previous liquidity settlement)
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_2), TIMESTAMP_1);

        // Query after TIMESTAMP_3 should still return TIMESTAMP_3
        assertEq(chronicle.getSettledLiquidityTimestampAt(TIMESTAMP_3 + 100), TIMESTAMP_3);
    }

    function testFuzz_getSettledLiquidityTimestampAt(uint64[] memory settlements, uint64 queryTimestamp) public {
        vm.assume(settlements.length > 0 && settlements.length <= 10);

        // Sort settlements to avoid StaleTimestamp
        for (uint256 i = 0; i < settlements.length; i++) {
            for (uint256 j = i + 1; j < settlements.length; j++) {
                if (settlements[i] > settlements[j]) {
                    uint64 temp = settlements[i];
                    settlements[i] = settlements[j];
                    settlements[j] = temp;
                }
            }
        }

        // Settle unique timestamps
        uint64 lastSettled = 0;
        uint64[] memory actuallySettled = new uint64[](settlements.length);
        uint256 settledCount = 0;

        for (uint256 i = 0; i < settlements.length; i++) {
            if (settlements[i] > lastSettled) {
                _setupAndSettleLiquidity(settlements[i]);
                actuallySettled[settledCount] = settlements[i];
                settledCount++;
                lastSettled = settlements[i];
            }
        }

        // Find expected floor value
        uint64 expectedFloor = 0;
        for (uint256 i = 0; i < settledCount; i++) {
            if (actuallySettled[i] <= queryTimestamp) {
                expectedFloor = actuallySettled[i];
            } else {
                break;
            }
        }

        assertEq(chronicle.getSettledLiquidityTimestampAt(queryTimestamp), expectedFloor);
    }

    function test_getLastSettledDataTimestamp_empty() public view {
        // Should return 0 when no data has been settled
        assertEq(chronicle.getLastSettledDataTimestamp(), 0);
    }

    function test_getLastSettledDataTimestamp_singleSettlement() public {
        // Settle data at TIMESTAMP_1
        _setupAndSettleData(TIMESTAMP_1);

        // Should return TIMESTAMP_1
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_1);
    }

    function test_getLastSettledDataTimestamp_multipleSettlementsChronological() public {
        // Settle data at multiple timestamps in chronological order
        _setupAndSettleData(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_2);
        _setupAndSettleData(TIMESTAMP_3);

        // Should return the maximum timestamp (TIMESTAMP_3)
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_3);
    }

    function test_getLastSettledDataTimestamp_doesNotChangeOnLiquiditySettlement() public {
        // Settle data at TIMESTAMP_1
        _setupAndSettleData(TIMESTAMP_1);
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_1);

        // Settle liquidity at TIMESTAMP_2 (without data)
        _setupAndSettleLiquidity(TIMESTAMP_2);

        // Should still return TIMESTAMP_1 (last data settlement)
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_1);
    }

    function test_getLastSettledDataTimestamp_handlesGapInTimestamps() public {
        // Settle at non-consecutive timestamps (must be in increasing order due to SnapshotsLib constraint)
        uint64 timestamp1 = 1000;
        uint64 timestamp2 = 5000;
        uint64 timestamp3 = 10_000;

        _setupAndSettleData(timestamp1);
        _setupAndSettleData(timestamp2);
        _setupAndSettleData(timestamp3);

        // Should return the maximum timestamp
        assertEq(chronicle.getLastSettledDataTimestamp(), timestamp3);
    }

    function test_getLastSettledDataTimestamp_withDifferentDataValues() public {
        // Settle different data at different timestamps
        bytes32[] memory keys1 = new bytes32[](1);
        bytes[] memory values1 = new bytes[](1);
        keys1[0] = keccak256("key1");
        values1[0] = "value1";
        _setupAndSettleDataWithKeysValues(TIMESTAMP_1, keys1, values1);

        bytes32[] memory keys2 = new bytes32[](2);
        bytes[] memory values2 = new bytes[](2);
        keys2[0] = keccak256("key2");
        keys2[1] = keccak256("key3");
        values2[0] = "value2";
        values2[1] = "value3";
        _setupAndSettleDataWithKeysValues(TIMESTAMP_2, keys2, values2);

        // Should return TIMESTAMP_2 regardless of data content
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_2);
    }

    function test_getLastSettledDataTimestamp_emptyDataSettlement() public {
        // Settle with empty data arrays
        bytes32[] memory emptyKeys = new bytes32[](0);
        bytes[] memory emptyValues = new bytes[](0);

        _setupAndSettleDataWithKeysValues(TIMESTAMP_1, emptyKeys, emptyValues);

        // Should still track the timestamp even with empty data
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_1);
    }

    function test_getLastSettledDataTimestamp_revertOnChronologicalOrder() public {
        // First settle at a later timestamp with actual data
        bytes32[] memory keys = new bytes32[](1);
        bytes[] memory values = new bytes[](1);
        keys[0] = keccak256("key1");
        values[0] = "value1";
        _setupAndSettleDataWithKeysValues(TIMESTAMP_2, keys, values);

        // Now try to settle at an earlier timestamp
        // RemoteAppChronicle enforces chronological order
        _setupValidDataSettlementForTimestamp(TIMESTAMP_1);

        RemoteAppChronicle.SettleDataParams memory params = RemoteAppChronicle.SettleDataParams({
            timestamp: TIMESTAMP_1,
            keys: new bytes32[](1),
            values: new bytes[](1),
            dataRoot: keccak256("test_data_root"),
            proof: new bytes32[](0)
        });
        params.keys[0] = keccak256("key1"); // Same key as before
        params.values[0] = "different_value";

        vm.prank(settler);
        vm.expectRevert(IRemoteAppChronicle.StaleTimestamp.selector);
        chronicle.settleData(params);

        // The last timestamp should still be TIMESTAMP_2
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_2);
    }

    function test_getLastSettledDataTimestamp_independentFromFinalization() public {
        // Settle data at TIMESTAMP_1
        _setupAndSettleData(TIMESTAMP_1);
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_1);
        assertFalse(chronicle.isFinalized(TIMESTAMP_1));

        // Settle liquidity at TIMESTAMP_1 to finalize
        _setupAndSettleLiquidity(TIMESTAMP_1);
        assertTrue(chronicle.isFinalized(TIMESTAMP_1));

        // Last data timestamp should remain unchanged
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_1);

        // Settle data at TIMESTAMP_2 without liquidity
        _setupAndSettleData(TIMESTAMP_2);
        assertFalse(chronicle.isFinalized(TIMESTAMP_2));

        // Should now return TIMESTAMP_2
        assertEq(chronicle.getLastSettledDataTimestamp(), TIMESTAMP_2);
    }

    function testFuzz_getLastSettledDataTimestamp(uint64[] memory timestamps) public {
        vm.assume(timestamps.length > 0 && timestamps.length <= 10);

        // Sort timestamps to avoid StaleTimestamp errors
        for (uint256 i = 0; i < timestamps.length; i++) {
            for (uint256 j = i + 1; j < timestamps.length; j++) {
                if (timestamps[i] > timestamps[j]) {
                    uint64 temp = timestamps[i];
                    timestamps[i] = timestamps[j];
                    timestamps[j] = temp;
                }
            }
        }

        uint64 maxTimestamp = 0;
        uint64 lastSettled = 0;
        for (uint256 i = 0; i < timestamps.length; i++) {
            // Skip duplicates and timestamps that would cause StaleTimestamp
            if (timestamps[i] <= lastSettled) {
                continue;
            }

            _setupAndSettleData(timestamps[i]);
            lastSettled = timestamps[i];
            maxTimestamp = timestamps[i];
        }

        // Should always return the maximum settled timestamp
        if (maxTimestamp > 0) {
            assertEq(chronicle.getLastSettledDataTimestamp(), maxTimestamp);
        } else {
            assertEq(chronicle.getLastSettledDataTimestamp(), 0);
        }
    }

    function test_getSettledDataTimestampAt_empty() public view {
        // Should return 0 when no data has been settled
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_1), 0);
        assertEq(chronicle.getSettledDataTimestampAt(0), 0);
        assertEq(chronicle.getSettledDataTimestampAt(type(uint64).max), 0);
    }

    function test_getSettledDataTimestampAt_singleSettlement() public {
        // Settle data at TIMESTAMP_2
        _setupAndSettleData(TIMESTAMP_2);

        // Query before the settlement should return 0
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_1), 0);

        // Query at exact timestamp should return that timestamp
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_2), TIMESTAMP_2);

        // Query after the settlement should return TIMESTAMP_2
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_3), TIMESTAMP_2);
        assertEq(chronicle.getSettledDataTimestampAt(type(uint64).max), TIMESTAMP_2);
    }

    function test_getSettledDataTimestampAt_multipleSettlements() public {
        // Settle at multiple timestamps
        _setupAndSettleData(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_2);
        _setupAndSettleData(TIMESTAMP_3);

        // Query before first settlement
        assertEq(chronicle.getSettledDataTimestampAt(500), 0);

        // Query at exact timestamps
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_1), TIMESTAMP_1);
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_2), TIMESTAMP_2);
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_3), TIMESTAMP_3);

        // Query between timestamps
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_1 + 100), TIMESTAMP_1);
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_2 + 100), TIMESTAMP_2);

        // Query after last timestamp
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_3 + 1000), TIMESTAMP_3);
    }

    function test_getSettledDataTimestampAt_withGaps() public {
        // Settle with large gaps between timestamps
        uint64 timestamp1 = 100;
        uint64 timestamp2 = 10_000;
        uint64 timestamp3 = 50_000;

        _setupAndSettleData(timestamp1);
        _setupAndSettleData(timestamp2);
        _setupAndSettleData(timestamp3);

        // Test various query points
        assertEq(chronicle.getSettledDataTimestampAt(50), 0);
        assertEq(chronicle.getSettledDataTimestampAt(100), timestamp1);
        assertEq(chronicle.getSettledDataTimestampAt(5000), timestamp1);
        assertEq(chronicle.getSettledDataTimestampAt(10_000), timestamp2);
        assertEq(chronicle.getSettledDataTimestampAt(30_000), timestamp2);
        assertEq(chronicle.getSettledDataTimestampAt(50_000), timestamp3);
        assertEq(chronicle.getSettledDataTimestampAt(100_000), timestamp3);
    }

    function test_getSettledDataTimestampAt_boundaryConditions() public {
        // Test with boundary values
        uint64 minTimestamp = 1;
        uint64 maxTimestamp = type(uint64).max - 1;

        _setupAndSettleData(minTimestamp);
        _setupAndSettleData(maxTimestamp);

        // Query at 0 should return 0 (before first settlement)
        assertEq(chronicle.getSettledDataTimestampAt(0), 0);

        // Query at minTimestamp should return minTimestamp
        assertEq(chronicle.getSettledDataTimestampAt(minTimestamp), minTimestamp);

        // Query in the middle should return minTimestamp
        assertEq(chronicle.getSettledDataTimestampAt(type(uint64).max / 2), minTimestamp);

        // Query at max should return maxTimestamp
        assertEq(chronicle.getSettledDataTimestampAt(type(uint64).max), maxTimestamp);
    }

    function test_getSettledDataTimestampAt_manySettlements() public {
        // Test with many settlements to verify O(log n) binary search
        uint64[] memory timestamps = new uint64[](20);
        for (uint256 i = 0; i < 20; i++) {
            timestamps[i] = uint64(1000 * (i + 1));
            _setupAndSettleData(timestamps[i]);
        }

        // Test binary search is working correctly
        assertEq(chronicle.getSettledDataTimestampAt(500), 0);
        assertEq(chronicle.getSettledDataTimestampAt(1500), timestamps[0]);
        assertEq(chronicle.getSettledDataTimestampAt(5500), timestamps[4]);
        assertEq(chronicle.getSettledDataTimestampAt(10_500), timestamps[9]);
        assertEq(chronicle.getSettledDataTimestampAt(15_500), timestamps[14]);
        assertEq(chronicle.getSettledDataTimestampAt(20_500), timestamps[19]);
    }

    function test_getSettledDataTimestampAt_independentFromLiquidity() public {
        // Settle data at TIMESTAMP_1 and TIMESTAMP_3
        _setupAndSettleData(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_3);

        // Settle liquidity at TIMESTAMP_2 (without data)
        _setupAndSettleLiquidity(TIMESTAMP_2);

        // Query at TIMESTAMP_2 should return TIMESTAMP_1 (previous data settlement)
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_2), TIMESTAMP_1);

        // Query after TIMESTAMP_3 should still return TIMESTAMP_3
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_3 + 100), TIMESTAMP_3);
    }

    function test_getSettledDataTimestampAt_withDifferentDataContent() public {
        // Settle different data content at different timestamps
        bytes32[] memory keys1 = new bytes32[](1);
        bytes[] memory values1 = new bytes[](1);
        keys1[0] = keccak256("config");
        values1[0] = "initial_config";
        _setupAndSettleDataWithKeysValues(TIMESTAMP_1, keys1, values1);

        bytes32[] memory keys2 = new bytes32[](2);
        bytes[] memory values2 = new bytes[](2);
        keys2[0] = keccak256("metadata");
        keys2[1] = keccak256("settings");
        values2[0] = "metadata_v1";
        values2[1] = abi.encode(100, true);
        _setupAndSettleDataWithKeysValues(TIMESTAMP_2, keys2, values2);

        bytes32[] memory keys3 = new bytes32[](0);
        bytes[] memory values3 = new bytes[](0);
        _setupAndSettleDataWithKeysValues(TIMESTAMP_3, keys3, values3);

        // All timestamps should be queryable regardless of data content
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_1), TIMESTAMP_1);
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_2), TIMESTAMP_2);
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_3), TIMESTAMP_3);

        // Query between timestamps
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_1 + 500), TIMESTAMP_1);
        assertEq(chronicle.getSettledDataTimestampAt(TIMESTAMP_2 + 500), TIMESTAMP_2);
    }

    function testFuzz_getSettledDataTimestampAt(uint64[] memory settlements, uint64 queryTimestamp) public {
        vm.assume(settlements.length > 0 && settlements.length <= 10);

        // Sort settlements to avoid StaleTimestamp
        for (uint256 i = 0; i < settlements.length; i++) {
            for (uint256 j = i + 1; j < settlements.length; j++) {
                if (settlements[i] > settlements[j]) {
                    uint64 temp = settlements[i];
                    settlements[i] = settlements[j];
                    settlements[j] = temp;
                }
            }
        }

        // Settle unique timestamps
        uint64 lastSettled = 0;
        uint64[] memory actuallySettled = new uint64[](settlements.length);
        uint256 settledCount = 0;

        for (uint256 i = 0; i < settlements.length; i++) {
            if (settlements[i] > lastSettled) {
                _setupAndSettleData(settlements[i]);
                actuallySettled[settledCount] = settlements[i];
                settledCount++;
                lastSettled = settlements[i];
            }
        }

        // Find expected floor value
        uint64 expectedFloor = 0;
        for (uint256 i = 0; i < settledCount; i++) {
            if (actuallySettled[i] <= queryTimestamp) {
                expectedFloor = actuallySettled[i];
            } else {
                break;
            }
        }

        assertEq(chronicle.getSettledDataTimestampAt(queryTimestamp), expectedFloor);
    }

    function test_getLastFinalizedTimestamp_empty() public view {
        // Should return 0 when nothing has been finalized
        assertEq(chronicle.getLastFinalizedTimestamp(), 0);
    }

    function test_getLastFinalizedTimestamp_onlyLiquiditySettled() public {
        // Settle only liquidity at TIMESTAMP_1
        _setupAndSettleLiquidity(TIMESTAMP_1);

        // Should return 0 because data is not settled
        assertFalse(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), 0);
    }

    function test_getLastFinalizedTimestamp_onlyDataSettled() public {
        // Settle only data at TIMESTAMP_1
        _setupAndSettleData(TIMESTAMP_1);

        // Should return 0 because liquidity is not settled
        assertFalse(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), 0);
    }

    function test_getLastFinalizedTimestamp_bothSettledSameTimestamp() public {
        // Settle both liquidity and data at TIMESTAMP_1
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_1);

        // Should return TIMESTAMP_1 as it's finalized
        assertTrue(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);
    }

    function test_getLastFinalizedTimestamp_liquidityThenData() public {
        // Settle liquidity first
        _setupAndSettleLiquidity(TIMESTAMP_1);
        assertEq(chronicle.getLastFinalizedTimestamp(), 0);

        // Then settle data - should trigger finalization
        _setupAndSettleData(TIMESTAMP_1);
        assertTrue(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);
    }

    function test_getLastFinalizedTimestamp_dataThenLiquidity() public {
        // Settle data first
        _setupAndSettleData(TIMESTAMP_1);
        assertEq(chronicle.getLastFinalizedTimestamp(), 0);

        // Then settle liquidity - should trigger finalization
        _setupAndSettleLiquidity(TIMESTAMP_1);
        assertTrue(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);
    }

    function test_getLastFinalizedTimestamp_multipleFinalizations() public {
        // Finalize TIMESTAMP_1
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_1);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);

        // Finalize TIMESTAMP_2
        _setupAndSettleLiquidity(TIMESTAMP_2);
        _setupAndSettleData(TIMESTAMP_2);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_2);

        // Finalize TIMESTAMP_3
        _setupAndSettleLiquidity(TIMESTAMP_3);
        _setupAndSettleData(TIMESTAMP_3);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_3);
    }

    function test_getLastFinalizedTimestamp_partialSettlements() public {
        // Finalize TIMESTAMP_1
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_1);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);

        // Only settle liquidity at TIMESTAMP_2
        _setupAndSettleLiquidity(TIMESTAMP_2);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1); // Still TIMESTAMP_1

        // Complete TIMESTAMP_2 by settling data (must be done before TIMESTAMP_3)
        _setupAndSettleData(TIMESTAMP_2);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_2); // Now TIMESTAMP_2

        // Settle liquidity at TIMESTAMP_3
        _setupAndSettleLiquidity(TIMESTAMP_3);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_2); // Still TIMESTAMP_2

        // Complete TIMESTAMP_3 by settling data
        _setupAndSettleData(TIMESTAMP_3);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_3); // Now TIMESTAMP_3
    }

    function test_getLastFinalizedTimestamp_withGaps() public {
        uint64 timestamp1 = 1000;
        uint64 timestamp2 = 5000;
        uint64 timestamp3 = 10_000;

        // Finalize timestamp1
        _setupAndSettleLiquidity(timestamp1);
        _setupAndSettleData(timestamp1);
        assertEq(chronicle.getLastFinalizedTimestamp(), timestamp1);

        // Finalize timestamp2
        _setupAndSettleLiquidity(timestamp2);
        _setupAndSettleData(timestamp2);
        assertEq(chronicle.getLastFinalizedTimestamp(), timestamp2);

        // Finalize timestamp3 (with gap from timestamp2)
        _setupAndSettleLiquidity(timestamp3);
        _setupAndSettleData(timestamp3);
        assertEq(chronicle.getLastFinalizedTimestamp(), timestamp3);

        // Verify all three are finalized
        assertTrue(chronicle.isFinalized(timestamp1));
        assertTrue(chronicle.isFinalized(timestamp2));
        assertTrue(chronicle.isFinalized(timestamp3));
    }

    function test_getLastFinalizedTimestamp_emptyDataStillFinalizes() public {
        // Settle liquidity with actual data
        _setupAndSettleLiquidity(TIMESTAMP_1);

        // Settle data with empty arrays
        bytes32[] memory emptyKeys = new bytes32[](0);
        bytes[] memory emptyValues = new bytes[](0);
        _setupAndSettleDataWithKeysValues(TIMESTAMP_1, emptyKeys, emptyValues);

        // Should still be finalized
        assertTrue(chronicle.isFinalized(TIMESTAMP_1));
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);
    }

    function test_getLastFinalizedTimestamp_differentDataContent() public {
        // Finalize with different data content at each timestamp
        _setupAndSettleLiquidity(TIMESTAMP_1);
        bytes32[] memory keys1 = new bytes32[](1);
        bytes[] memory values1 = new bytes[](1);
        keys1[0] = keccak256("key1");
        values1[0] = "value1";
        _setupAndSettleDataWithKeysValues(TIMESTAMP_1, keys1, values1);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_1);

        _setupAndSettleLiquidity(TIMESTAMP_2);
        bytes32[] memory keys2 = new bytes32[](2);
        bytes[] memory values2 = new bytes[](2);
        keys2[0] = keccak256("key2");
        keys2[1] = keccak256("key3");
        values2[0] = "value2";
        values2[1] = abi.encode(123, true);
        _setupAndSettleDataWithKeysValues(TIMESTAMP_2, keys2, values2);
        assertEq(chronicle.getLastFinalizedTimestamp(), TIMESTAMP_2);
    }

    function testFuzz_getLastFinalizedTimestamp(uint64[] memory timestamps) public {
        vm.assume(timestamps.length > 0 && timestamps.length <= 10);

        // Sort timestamps to avoid StaleTimestamp errors
        for (uint256 i = 0; i < timestamps.length; i++) {
            for (uint256 j = i + 1; j < timestamps.length; j++) {
                if (timestamps[i] > timestamps[j]) {
                    uint64 temp = timestamps[i];
                    timestamps[i] = timestamps[j];
                    timestamps[j] = temp;
                }
            }
        }

        uint64 maxFinalized = 0;
        uint64 lastSettled = 0;

        for (uint256 i = 0; i < timestamps.length; i++) {
            // Skip duplicates
            if (timestamps[i] <= lastSettled) {
                continue;
            }

            // Randomly decide whether to finalize this timestamp
            bool shouldFinalize = uint256(keccak256(abi.encode(timestamps[i]))) % 2 == 0;

            if (shouldFinalize) {
                _setupAndSettleLiquidity(timestamps[i]);
                _setupAndSettleData(timestamps[i]);
                maxFinalized = timestamps[i];
            } else {
                // Only settle one or the other
                if (uint256(keccak256(abi.encode(timestamps[i], "liquidity"))) % 2 == 0) {
                    _setupAndSettleLiquidity(timestamps[i]);
                } else {
                    _setupAndSettleData(timestamps[i]);
                }
            }

            lastSettled = timestamps[i];
        }

        assertEq(chronicle.getLastFinalizedTimestamp(), maxFinalized);
    }

    function test_getFinalizedTimestampAt_empty() public view {
        // Should return 0 when nothing has been finalized
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_1), 0);
        assertEq(chronicle.getFinalizedTimestampAt(0), 0);
        assertEq(chronicle.getFinalizedTimestampAt(type(uint64).max), 0);
    }

    function test_getFinalizedTimestampAt_singleFinalization() public {
        // Finalize at TIMESTAMP_2
        _setupAndSettleLiquidity(TIMESTAMP_2);
        _setupAndSettleData(TIMESTAMP_2);

        // Query before the finalization should return 0
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_1), 0);

        // Query at exact timestamp returns TIMESTAMP_2
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_2), TIMESTAMP_2);

        // Query after returns TIMESTAMP_2 as the floor
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_3), TIMESTAMP_2);
        assertEq(chronicle.getFinalizedTimestampAt(type(uint64).max), TIMESTAMP_2);
    }

    function test_getFinalizedTimestampAt_multipleFinalizations() public {
        // Finalize at three timestamps
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_1);
        _setupAndSettleLiquidity(TIMESTAMP_2);
        _setupAndSettleData(TIMESTAMP_2);
        _setupAndSettleLiquidity(TIMESTAMP_3);
        _setupAndSettleData(TIMESTAMP_3);

        // Before first
        assertEq(chronicle.getFinalizedTimestampAt(500), 0);

        // Exact
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_1), TIMESTAMP_1);
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_2), TIMESTAMP_2);
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_3), TIMESTAMP_3);

        // Between
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_1 + 100), TIMESTAMP_1);
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_2 + 100), TIMESTAMP_2);

        // After last
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_3 + 1000), TIMESTAMP_3);
    }

    function test_getFinalizedTimestampAt_withGaps() public {
        uint64 t1 = 1000;
        uint64 t2 = 10_000;
        uint64 t3 = 50_000;

        // Finalize with large gaps
        _setupAndSettleLiquidity(t1);
        _setupAndSettleData(t1);
        _setupAndSettleLiquidity(t2);
        _setupAndSettleData(t2);
        _setupAndSettleLiquidity(t3);
        _setupAndSettleData(t3);

        // Queries
        assertEq(chronicle.getFinalizedTimestampAt(500), 0);
        assertEq(chronicle.getFinalizedTimestampAt(1000), t1);
        assertEq(chronicle.getFinalizedTimestampAt(5000), t1);
        assertEq(chronicle.getFinalizedTimestampAt(10_000), t2);
        assertEq(chronicle.getFinalizedTimestampAt(30_000), t2);
        assertEq(chronicle.getFinalizedTimestampAt(50_000), t3);
        assertEq(chronicle.getFinalizedTimestampAt(100_000), t3);
    }

    function test_getFinalizedTimestampAt_ignoresPartialSettlements() public {
        // Finalize at TIMESTAMP_1
        _setupAndSettleLiquidity(TIMESTAMP_1);
        _setupAndSettleData(TIMESTAMP_1);

        // Partial at TIMESTAMP_2 (liquidity only)
        _setupAndSettleLiquidity(TIMESTAMP_2);

        // At TIMESTAMP_2, floor should still be TIMESTAMP_1 (not finalized)
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_2), TIMESTAMP_1);

        // Complete TIMESTAMP_2 finalization
        _setupAndSettleData(TIMESTAMP_2);
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_2), TIMESTAMP_2);

        // Partial at TIMESTAMP_3 (data only)
        _setupAndSettleData(TIMESTAMP_3);

        // At TIMESTAMP_3, floor should be TIMESTAMP_2 (not finalized)
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_3), TIMESTAMP_2);

        // Complete TIMESTAMP_3 finalization
        _setupAndSettleLiquidity(TIMESTAMP_3);
        assertEq(chronicle.getFinalizedTimestampAt(TIMESTAMP_3), TIMESTAMP_3);
    }

    function testFuzz_getFinalizedTimestampAt(uint64[] memory ts, uint64 q) public {
        vm.assume(ts.length > 0 && ts.length <= 10);
        // Sort to respect chronological constraint
        for (uint256 i = 0; i < ts.length; i++) {
            for (uint256 j = i + 1; j < ts.length; j++) {
                if (ts[i] > ts[j]) {
                    uint64 tmp = ts[i];
                    ts[i] = ts[j];
                    ts[j] = tmp;
                }
            }
        }

        uint64 last = 0;
        uint64[] memory finals = new uint64[](ts.length);
        uint256 n = 0;
        for (uint256 i = 0; i < ts.length; i++) {
            if (ts[i] <= last) continue; // skip duplicates
            _setupAndSettleLiquidity(ts[i]);
            _setupAndSettleData(ts[i]);
            finals[n++] = ts[i];
            last = ts[i];
        }

        // Compute expected floor
        uint64 expected = 0;
        for (uint256 i = 0; i < n; i++) {
            if (finals[i] <= q) expected = finals[i];
            else break;
        }

        assertEq(chronicle.getFinalizedTimestampAt(q), expected);
    }

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

        // Setup valid liquidity settlement for the test
        _setupValidLiquiditySettlementForTimestamp(TIMESTAMP_1);

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        bool[] memory isContract = new bool[](1);
        accounts[0] = alice;
        liquidity[0] = liquidityAmount;
        isContract[0] = false; // EOA

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: TIMESTAMP_1,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: liquidityAmount,
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
            isContract: new bool[](0),
            totalLiquidity: 0,
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
                SETTLER-PROVIDED TOTAL LIQUIDITY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test that totalLiquidity value from settler is directly used
     */
    function test_settlerProvidedTotalLiquidity_isUsedDirectly() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        // First settlement
        address[] memory accounts = new address[](2);
        int256[] memory liquidity = new int256[](2);
        accounts[0] = alice;
        accounts[1] = bob;
        liquidity[0] = 100e18;
        liquidity[1] = 200e18;

        // Note: Total liquidity 500e18 is MORE than sum of accounts (300e18)
        // This simulates a situation where there are other accounts not included
        // in this settlement but whose values are known by the settler
        _setupValidLiquiditySettlementForTimestamp(1000);
        _settleLiquidityWithTotal(1000, accounts, liquidity, 500e18);

        // Verify total matches settler's value
        assertEq(chronicle.getTotalLiquidityAt(1000), 500e18, "Total should match settler provided value");

        // Second settlement: Update only Alice
        accounts = new address[](1);
        liquidity = new int256[](1);
        accounts[0] = alice;
        liquidity[0] = 150e18;

        // Total is now 550e18 (including all accounts known to settler)
        _setupValidLiquiditySettlementForTimestamp(2000);
        _settleLiquidityWithTotal(2000, accounts, liquidity, 550e18);

        // Individual balances are tracked correctly
        assertEq(chronicle.getLiquidityAt(alice, 2000), 150e18, "Alice's balance updated");
        assertEq(chronicle.getLiquidityAt(bob, 2000), 200e18, "Bob's balance unchanged");

        // But total matches settler's value which includes all accounts
        assertEq(chronicle.getTotalLiquidityAt(2000), 550e18, "Total matches settler's complete view");
    }

    /**
     * @notice Test that hooks receive the settler-provided total liquidity
     */
    function test_settlerProvidedTotalLiquidity_hooksReceiveTotal() public {
        // Deploy a mock hook contract
        MockHookForTotalLiquidity hook = new MockHookForTotalLiquidity();

        // Make the app actually be our hook contract
        address hookApp = address(hook);

        // Update mock to use hook for the new app address
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getAppSetting.selector, hookApp),
            abi.encode(true, false, true, settler) // useHook = true
        );

        // Mock LiquidityMatrix.getRemoteApp for the new app address
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.getRemoteApp.selector, hookApp, CHAIN_UID),
            abi.encode(hookApp, uint256(0))
        );

        RemoteAppChronicle hookChronicle = new RemoteAppChronicle(liquidityMatrix, hookApp, CHAIN_UID, VERSION);

        address alice = makeAddr("alice");

        // Settle with one account but higher total
        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        accounts[0] = alice;
        liquidity[0] = 100e18;

        // Total includes value of other accounts not in this settlement
        int256 providedTotal = 500e18;

        bytes32 liquidityRoot = keccak256("test_liquidity_root");
        bytes32 expectedTopRoot = keccak256(abi.encodePacked(bytes32(uint256(uint160(hookApp))), liquidityRoot));

        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSignature(
                "getRemoteLiquidityRootAt(bytes32,uint256,uint64)", CHAIN_UID, VERSION, uint64(1000)
            ),
            abi.encode(expectedTopRoot)
        );

        // Create isContract array - all false for EOAs
        bool[] memory isContract = new bool[](accounts.length);

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: 1000,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: providedTotal,
            liquidityRoot: liquidityRoot,
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        hookChronicle.settleLiquidity(params);

        // Verify hook got the total from settler
        assertEq(hook.lastTotalLiquidity(), providedTotal, "Hook received settler-provided total");
    }

    /**
     * @notice Test that empty account lists work with non-zero total liquidity
     */
    function test_settlerProvidedTotalLiquidity_emptyAccountList() public {
        // Settlement with no accounts but non-zero total
        address[] memory accounts = new address[](0);
        int256[] memory liquidity = new int256[](0);

        // This could happen if settler knows the total but isn't updating any accounts
        _setupValidLiquiditySettlementForTimestamp(1000);
        _settleLiquidityWithTotal(1000, accounts, liquidity, 1000e18);

        assertEq(chronicle.getTotalLiquidityAt(1000), 1000e18, "Total set despite no accounts");
    }

    /**
     * @notice Test negative total liquidity handling
     */
    function test_settlerProvidedTotalLiquidity_negative() public {
        address alice = makeAddr("alice");

        address[] memory accounts = new address[](1);
        int256[] memory liquidity = new int256[](1);
        accounts[0] = alice;
        liquidity[0] = -100e18;

        // Total can be more negative than sum of accounts
        _setupValidLiquiditySettlementForTimestamp(1000);
        _settleLiquidityWithTotal(1000, accounts, liquidity, -500e18);

        assertEq(chronicle.getTotalLiquidityAt(1000), -500e18, "Negative total stored correctly");
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

        // Calculate total liquidity
        int256 totalLiq = 0;
        for (uint256 i = 0; i < liquidity.length; i++) {
            totalLiq += liquidity[i];
        }

        // Create isContract array - all false for EOAs
        bool[] memory isContract = new bool[](accounts.length);

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: timestamp,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: totalLiq,
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

    function _settleLiquidityWithTotal(
        uint64 timestamp,
        address[] memory accounts,
        int256[] memory liquidity,
        int256 totalLiquidity
    ) internal {
        // Create isContract array - all false for EOAs
        bool[] memory isContract = new bool[](accounts.length);

        RemoteAppChronicle.SettleLiquidityParams memory params = RemoteAppChronicle.SettleLiquidityParams({
            timestamp: timestamp,
            accounts: accounts,
            liquidity: liquidity,
            isContract: isContract,
            totalLiquidity: totalLiquidity,
            liquidityRoot: keccak256("test_liquidity_root"),
            proof: new bytes32[](0)
        });

        vm.prank(settler);
        chronicle.settleLiquidity(params);
    }
}

// Mock hook contract to verify hook receives correct total liquidity
contract MockHookForTotalLiquidity is ILiquidityMatrixHook {
    int256 public lastTotalLiquidity;

    function onSettleLiquidity(bytes32, uint256, uint64, address) external override { }

    function onMapAccounts(bytes32, address[] memory, address[] memory) external override { }

    function onSettleTotalLiquidity(bytes32, uint256, uint64 timestamp) external override {
        lastTotalLiquidity = RemoteAppChronicle(msg.sender).getTotalLiquidityAt(timestamp);
    }

    function onSettleData(bytes32, uint256, uint64, bytes32) external override { }
}
