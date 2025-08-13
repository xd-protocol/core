// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { LocalAppChronicle } from "../../src/chronicles/LocalAppChronicle.sol";
import { ILocalAppChronicle } from "../../src/interfaces/ILocalAppChronicle.sol";
import { ILiquidityMatrix } from "../../src/interfaces/ILiquidityMatrix.sol";

/**
 * @title LocalAppChronicleTest
 * @notice Comprehensive tests for LocalAppChronicle functionality
 * @dev Tests all major functions including constructor, liquidity management,
 *      data storage, historical queries, and access control
 */
contract LocalAppChronicleTest is Test {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    LocalAppChronicle chronicle;
    address liquidityMatrix;
    address app;
    address unauthorizedUser;
    uint256 constant VERSION = 1;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateLiquidity(
        uint256 topTreeIndex, address indexed account, uint256 appTreeIndex, uint64 indexed timestamp
    );

    event UpdateData(
        uint256 topTreeIndex, bytes32 indexed key, bytes32 hash, uint256 appTreeIndex, uint64 indexed timestamp
    );

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        liquidityMatrix = makeAddr("liquidityMatrix");
        app = makeAddr("app");
        unauthorizedUser = makeAddr("unauthorizedUser");

        // Mock LiquidityMatrix behavior for updateTopLiquidityTree and updateTopDataTree
        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.updateTopLiquidityTree.selector),
            abi.encode(uint256(42)) // Return arbitrary tree index
        );

        vm.mockCall(
            liquidityMatrix,
            abi.encodeWithSelector(ILiquidityMatrix.updateTopDataTree.selector),
            abi.encode(uint256(24)) // Return arbitrary tree index
        );

        chronicle = new LocalAppChronicle(liquidityMatrix, app, VERSION);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public {
        LocalAppChronicle newChronicle = new LocalAppChronicle(liquidityMatrix, app, VERSION);

        assertEq(newChronicle.liquidityMatrix(), liquidityMatrix);
        assertEq(newChronicle.app(), app);
        assertEq(newChronicle.version(), VERSION);
    }

    function test_constructor_withDifferentParams() public {
        address differentMatrix = makeAddr("differentMatrix");
        address differentApp = makeAddr("differentApp");
        uint256 differentVersion = 5;

        LocalAppChronicle newChronicle = new LocalAppChronicle(differentMatrix, differentApp, differentVersion);

        assertEq(newChronicle.liquidityMatrix(), differentMatrix);
        assertEq(newChronicle.app(), differentApp);
        assertEq(newChronicle.version(), differentVersion);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIAL STATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialState() public {
        // Initial tree roots should be non-zero (empty tree has a specific root)
        bytes32 liquidityRoot = chronicle.getLiquidityRoot();
        bytes32 dataRoot = chronicle.getDataRoot();
        assertTrue(liquidityRoot != bytes32(0));
        assertTrue(dataRoot != bytes32(0));

        // Initial total liquidity should be 0
        assertEq(chronicle.getTotalLiquidity(), 0);

        // Initial account liquidity should be 0
        address testAccount = makeAddr("testAccount");
        assertEq(chronicle.getLiquidity(testAccount), 0);

        // Initial data should be empty
        bytes32 testKey = keccak256("testKey");
        assertEq(chronicle.getData(testKey).length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        updateLiquidity() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateLiquidity() public {
        address account = makeAddr("account");
        int256 liquidity = 100;

        vm.prank(app);
        vm.expectEmit(true, true, true, true);
        emit UpdateLiquidity(42, account, 0, uint64(block.timestamp));

        (uint256 topTreeIndex, uint256 appTreeIndex) = chronicle.updateLiquidity(account, liquidity);

        assertEq(topTreeIndex, 42);
        assertEq(appTreeIndex, 0);
        assertEq(chronicle.getLiquidity(account), liquidity);
        assertEq(chronicle.getTotalLiquidity(), liquidity);
    }

    function test_updateLiquidity_multipleAccounts() public {
        address account1 = makeAddr("account1");
        address account2 = makeAddr("account2");
        int256 liquidity1 = 100;
        int256 liquidity2 = 200;

        vm.prank(app);
        chronicle.updateLiquidity(account1, liquidity1);

        vm.prank(app);
        chronicle.updateLiquidity(account2, liquidity2);

        assertEq(chronicle.getLiquidity(account1), liquidity1);
        assertEq(chronicle.getLiquidity(account2), liquidity2);
        assertEq(chronicle.getTotalLiquidity(), liquidity1 + liquidity2);
    }

    function test_updateLiquidity_overwriteValue() public {
        address account = makeAddr("account");
        int256 initialLiquidity = 100;
        int256 newLiquidity = 150;

        vm.prank(app);
        chronicle.updateLiquidity(account, initialLiquidity);

        vm.prank(app);
        chronicle.updateLiquidity(account, newLiquidity);

        assertEq(chronicle.getLiquidity(account), newLiquidity);
        assertEq(chronicle.getTotalLiquidity(), newLiquidity);
    }

    function test_updateLiquidity_negativeLiquidity() public {
        address account = makeAddr("account");
        int256 liquidity = -50;

        vm.prank(app);
        chronicle.updateLiquidity(account, liquidity);

        assertEq(chronicle.getLiquidity(account), liquidity);
        assertEq(chronicle.getTotalLiquidity(), liquidity);
    }

    function test_updateLiquidity_zeroLiquidity() public {
        address account = makeAddr("account");
        int256 initialLiquidity = 100;

        vm.prank(app);
        chronicle.updateLiquidity(account, initialLiquidity);

        vm.prank(app);
        chronicle.updateLiquidity(account, 0);

        assertEq(chronicle.getLiquidity(account), 0);
        assertEq(chronicle.getTotalLiquidity(), 0);
    }

    function test_updateLiquidity_byLiquidityMatrix() public {
        address account = makeAddr("account");
        int256 liquidity = 100;

        vm.prank(liquidityMatrix);
        (uint256 topTreeIndex, uint256 appTreeIndex) = chronicle.updateLiquidity(account, liquidity);

        assertEq(topTreeIndex, 42);
        assertEq(appTreeIndex, 0);
        assertEq(chronicle.getLiquidity(account), liquidity);
    }

    function test_updateLiquidity_revertUnauthorized() public {
        address account = makeAddr("account");
        int256 liquidity = 100;

        vm.prank(unauthorizedUser);
        vm.expectRevert(ILocalAppChronicle.Forbidden.selector);
        chronicle.updateLiquidity(account, liquidity);
    }

    function testFuzz_updateLiquidity(address account, int256 liquidity) public {
        vm.assume(account != address(0));

        vm.prank(app);
        chronicle.updateLiquidity(account, liquidity);

        assertEq(chronicle.getLiquidity(account), liquidity);
        assertEq(chronicle.getTotalLiquidity(), liquidity);
    }

    /*//////////////////////////////////////////////////////////////
                        updateData() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateData() public {
        bytes32 key = keccak256("testKey");
        bytes memory value = "testValue";

        vm.prank(app);
        vm.expectEmit(true, true, true, true);
        emit UpdateData(24, key, keccak256(value), 0, uint64(block.timestamp));

        (uint256 topTreeIndex, uint256 appTreeIndex) = chronicle.updateData(key, value);

        assertEq(topTreeIndex, 24);
        assertEq(appTreeIndex, 0);
        assertEq(chronicle.getData(key), value);
    }

    function test_updateData_multipleKeys() public {
        bytes32 key1 = keccak256("key1");
        bytes32 key2 = keccak256("key2");
        bytes memory value1 = "value1";
        bytes memory value2 = "value2";

        vm.prank(app);
        chronicle.updateData(key1, value1);

        vm.prank(app);
        chronicle.updateData(key2, value2);

        assertEq(chronicle.getData(key1), value1);
        assertEq(chronicle.getData(key2), value2);
    }

    function test_updateData_overwriteValue() public {
        bytes32 key = keccak256("testKey");
        bytes memory initialValue = "initialValue";
        bytes memory newValue = "newValue";

        vm.prank(app);
        chronicle.updateData(key, initialValue);

        vm.prank(app);
        chronicle.updateData(key, newValue);

        assertEq(chronicle.getData(key), newValue);
    }

    function test_updateData_emptyValue() public {
        bytes32 key = keccak256("testKey");
        bytes memory emptyValue = "";

        vm.prank(app);
        chronicle.updateData(key, emptyValue);

        assertEq(chronicle.getData(key), emptyValue);
    }

    function test_updateData_largeValue() public {
        bytes32 key = keccak256("testKey");
        bytes memory largeValue = new bytes(1000);
        for (uint256 i = 0; i < 1000; i++) {
            largeValue[i] = bytes1(uint8(i % 256));
        }

        vm.prank(app);
        chronicle.updateData(key, largeValue);

        assertEq(chronicle.getData(key), largeValue);
    }

    function test_updateData_byLiquidityMatrix() public {
        bytes32 key = keccak256("testKey");
        bytes memory value = "testValue";

        vm.prank(liquidityMatrix);
        (uint256 topTreeIndex, uint256 appTreeIndex) = chronicle.updateData(key, value);

        assertEq(topTreeIndex, 24);
        assertEq(appTreeIndex, 0);
        assertEq(chronicle.getData(key), value);
    }

    function test_updateData_revertUnauthorized() public {
        bytes32 key = keccak256("testKey");
        bytes memory value = "testValue";

        vm.prank(unauthorizedUser);
        vm.expectRevert(ILocalAppChronicle.Forbidden.selector);
        chronicle.updateData(key, value);
    }

    function testFuzz_updateData(bytes32 key, bytes memory value) public {
        vm.prank(app);
        chronicle.updateData(key, value);

        assertEq(chronicle.getData(key), value);
    }

    /*//////////////////////////////////////////////////////////////
                        HISTORICAL QUERY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getTotalLiquidityAt() public {
        address account1 = makeAddr("account1");
        address account2 = makeAddr("account2");

        uint256 timestamp1 = block.timestamp;

        vm.prank(app);
        chronicle.updateLiquidity(account1, 100);

        vm.warp(timestamp1 + 100);
        uint256 timestamp2 = block.timestamp;

        vm.prank(app);
        chronicle.updateLiquidity(account2, 200);

        // Check historical total liquidity
        assertEq(chronicle.getTotalLiquidityAt(timestamp1), 100);
        assertEq(chronicle.getTotalLiquidityAt(timestamp2), 300);
        assertEq(chronicle.getTotalLiquidity(), 300);
    }

    function test_getLiquidityAt() public {
        address account = makeAddr("account");

        uint256 timestamp1 = block.timestamp;

        vm.prank(app);
        chronicle.updateLiquidity(account, 100);

        vm.warp(timestamp1 + 100);
        uint256 timestamp2 = block.timestamp;

        vm.prank(app);
        chronicle.updateLiquidity(account, 200);

        // Check historical account liquidity
        assertEq(chronicle.getLiquidityAt(account, timestamp1), 100);
        assertEq(chronicle.getLiquidityAt(account, timestamp2), 200);
        assertEq(chronicle.getLiquidity(account), 200);
    }

    function test_getDataAt() public {
        bytes32 key = keccak256("testKey");
        bytes memory initialValue = "initialValue";
        bytes memory newValue = "newValue";

        uint256 timestamp1 = block.timestamp;

        vm.prank(app);
        chronicle.updateData(key, initialValue);

        vm.warp(timestamp1 + 100);
        uint256 timestamp2 = block.timestamp;

        vm.prank(app);
        chronicle.updateData(key, newValue);

        // Check historical data
        assertEq(chronicle.getDataAt(key, timestamp1), initialValue);
        assertEq(chronicle.getDataAt(key, timestamp2), newValue);
        assertEq(chronicle.getData(key), newValue);
    }

    function test_historicalQueries_beforeFirstUpdate() public {
        address account = makeAddr("account");
        bytes32 key = keccak256("testKey");

        // Set an early timestamp (before any updates)
        uint256 earlyTimestamp = 1000;

        vm.warp(2000); // Set current time to a later point

        vm.prank(app);
        chronicle.updateLiquidity(account, 100);

        vm.prank(app);
        chronicle.updateData(key, "value");

        // Queries before any updates should return zero/empty values
        assertEq(chronicle.getTotalLiquidityAt(earlyTimestamp), 0);
        assertEq(chronicle.getLiquidityAt(account, earlyTimestamp), 0);
        assertEq(chronicle.getDataAt(key, earlyTimestamp).length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        MERKLE TREE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_merkleRoots_changOnUpdates() public {
        bytes32 initialLiquidityRoot = chronicle.getLiquidityRoot();
        bytes32 initialDataRoot = chronicle.getDataRoot();

        address account = makeAddr("account");
        bytes32 key = keccak256("testKey");

        vm.prank(app);
        chronicle.updateLiquidity(account, 100);

        bytes32 liquidityRootAfterLiquidityUpdate = chronicle.getLiquidityRoot();
        assertFalse(liquidityRootAfterLiquidityUpdate == initialLiquidityRoot);

        vm.prank(app);
        chronicle.updateData(key, "value");

        bytes32 dataRootAfterDataUpdate = chronicle.getDataRoot();
        assertFalse(dataRootAfterDataUpdate == initialDataRoot);
    }

    function test_merkleRoots_deterministicForSameState() public {
        LocalAppChronicle chronicle2 = new LocalAppChronicle(liquidityMatrix, app, VERSION);

        address account = makeAddr("account");
        bytes32 key = keccak256("testKey");
        bytes memory value = "testValue";
        int256 liquidity = 100;

        // Update both chronicles with same data
        vm.prank(app);
        chronicle.updateLiquidity(account, liquidity);
        vm.prank(app);
        chronicle.updateData(key, value);

        vm.prank(app);
        chronicle2.updateLiquidity(account, liquidity);
        vm.prank(app);
        chronicle2.updateData(key, value);

        // Roots should be identical
        assertEq(chronicle.getLiquidityRoot(), chronicle2.getLiquidityRoot());
        assertEq(chronicle.getDataRoot(), chronicle2.getDataRoot());
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_complexLiquidityScenario() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address charlie = makeAddr("charlie");

        // Initial setup
        vm.prank(app);
        chronicle.updateLiquidity(alice, 1000);
        vm.prank(app);
        chronicle.updateLiquidity(bob, 500);

        assertEq(chronicle.getTotalLiquidity(), 1500);

        // Bob reduces liquidity
        vm.prank(app);
        chronicle.updateLiquidity(bob, 200);

        assertEq(chronicle.getTotalLiquidity(), 1200);

        // Add Charlie with negative liquidity
        vm.prank(app);
        chronicle.updateLiquidity(charlie, -300);

        assertEq(chronicle.getTotalLiquidity(), 900);

        // Final verification
        assertEq(chronicle.getLiquidity(alice), 1000);
        assertEq(chronicle.getLiquidity(bob), 200);
        assertEq(chronicle.getLiquidity(charlie), -300);
    }

    function test_complexDataScenario() public {
        bytes32 key1 = keccak256("config");
        bytes32 key2 = keccak256("metadata");
        bytes32 key3 = keccak256("settings");

        // Store different types of data
        vm.prank(app);
        chronicle.updateData(key1, abi.encode(uint256(123), true, "config"));

        vm.prank(app);
        chronicle.updateData(key2, "metadata_string");

        vm.prank(app);
        chronicle.updateData(key3, new bytes(0)); // empty data

        // Verify data retrieval
        (uint256 configNum, bool configBool, string memory configStr) =
            abi.decode(chronicle.getData(key1), (uint256, bool, string));

        assertEq(configNum, 123);
        assertTrue(configBool);
        assertEq(configStr, "config");
        assertEq(chronicle.getData(key2), "metadata_string");
        assertEq(chronicle.getData(key3).length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateLiquidity_maxValues() public {
        address account = makeAddr("account");

        vm.prank(app);
        chronicle.updateLiquidity(account, type(int256).max);

        assertEq(chronicle.getLiquidity(account), type(int256).max);
        assertEq(chronicle.getTotalLiquidity(), type(int256).max);
    }

    function test_updateLiquidity_minValues() public {
        address account = makeAddr("account");

        vm.prank(app);
        chronicle.updateLiquidity(account, type(int256).min);

        assertEq(chronicle.getLiquidity(account), type(int256).min);
        assertEq(chronicle.getTotalLiquidity(), type(int256).min);
    }

    function test_updateData_sameValueTwice() public {
        bytes32 key = keccak256("testKey");
        bytes memory value = "sameValue";

        vm.prank(app);
        (uint256 topTreeIndex1, uint256 appTreeIndex1) = chronicle.updateData(key, value);

        vm.prank(app);
        (uint256 topTreeIndex2, uint256 appTreeIndex2) = chronicle.updateData(key, value);

        // Should still work and produce same results
        assertEq(topTreeIndex1, topTreeIndex2);
        assertEq(appTreeIndex1, appTreeIndex2);
        assertEq(chronicle.getData(key), value);
    }

    function test_gasUsage_multipleLiquidityUpdates() public {
        address account = makeAddr("account");

        uint256 gasBefore = gasleft();
        vm.prank(app);
        chronicle.updateLiquidity(account, 100);
        uint256 firstUpdateGas = gasBefore - gasleft();

        gasBefore = gasleft();
        vm.prank(app);
        chronicle.updateLiquidity(account, 200);
        uint256 secondUpdateGas = gasBefore - gasleft();

        // Second update should use similar gas (no significant optimization expected)
        console.log("First update gas:", firstUpdateGas);
        console.log("Second update gas:", secondUpdateGas);
    }
}
