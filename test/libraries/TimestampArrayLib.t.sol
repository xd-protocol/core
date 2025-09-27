// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TimestampArrayLib } from "../../src/libraries/TimestampArrayLib.sol";

contract TimestampArrayLibTest is Test {
    using TimestampArrayLib for TimestampArrayLib.TimestampArray;

    TimestampArrayLib.TimestampArray internal timestamps;

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Start with a clean array for each test
    }

    /*//////////////////////////////////////////////////////////////
                            add() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_add_singleTimestamp() public {
        timestamps.add(100);

        assertEq(timestamps.length(), 1);
        assertEq(timestamps.getLast(), 100);
        assertEq(timestamps.at(0), 100);
    }

    function test_add_multipleChronological() public {
        timestamps.add(100);
        timestamps.add(200);
        timestamps.add(300);

        assertEq(timestamps.length(), 3);
        assertEq(timestamps.getLast(), 300);
        assertEq(timestamps.at(0), 100);
        assertEq(timestamps.at(1), 200);
        assertEq(timestamps.at(2), 300);
    }

    function test_add_outOfOrder() public {
        timestamps.add(200);
        timestamps.add(100);
        timestamps.add(300);

        assertEq(timestamps.length(), 3);
        assertEq(timestamps.getLast(), 300); // Should track max correctly

        // Original order preserved in values array
        assertEq(timestamps.at(0), 200);
        assertEq(timestamps.at(1), 100);
        assertEq(timestamps.at(2), 300);
    }

    function test_add_duplicates() public {
        timestamps.add(100);
        timestamps.add(100);
        timestamps.add(100);

        assertEq(timestamps.length(), 3);
        assertEq(timestamps.getLast(), 100);
        assertTrue(timestamps.contains(100));
    }

    function testFuzz_add(uint64[] memory values) public {
        uint64 maxValue = 0;

        for (uint256 i = 0; i < values.length; i++) {
            timestamps.add(values[i]);
            if (values[i] > maxValue) {
                maxValue = values[i];
            }
        }

        assertEq(timestamps.length(), values.length);
        assertEq(timestamps.getLast(), maxValue);
    }

    /*//////////////////////////////////////////////////////////////
                            getLast() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getLast_empty() public view {
        assertEq(timestamps.getLast(), 0);
    }

    function test_getLast_afterAdditions() public {
        timestamps.add(50);
        assertEq(timestamps.getLast(), 50);

        timestamps.add(150);
        assertEq(timestamps.getLast(), 150);

        timestamps.add(75);
        assertEq(timestamps.getLast(), 150); // Should still be 150

        timestamps.add(200);
        assertEq(timestamps.getLast(), 200);
    }

    /*//////////////////////////////////////////////////////////////
                            findFloor() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_findFloor_empty() public view {
        assertEq(timestamps.findFloor(100), 0);
    }

    function test_findFloor_singleElement() public {
        timestamps.add(100);

        assertEq(timestamps.findFloor(50), 0); // Target less than min
        assertEq(timestamps.findFloor(100), 100); // Exact match
        assertEq(timestamps.findFloor(150), 100); // Target greater than max
    }

    function test_findFloor_multipleChronological() public {
        timestamps.add(100);
        timestamps.add(200);
        timestamps.add(300);

        assertEq(timestamps.findFloor(50), 0); // Less than min
        assertEq(timestamps.findFloor(100), 100); // Exact match first
        assertEq(timestamps.findFloor(150), 100); // Between first and second
        assertEq(timestamps.findFloor(200), 200); // Exact match second
        assertEq(timestamps.findFloor(250), 200); // Between second and third
        assertEq(timestamps.findFloor(300), 300); // Exact match third
        assertEq(timestamps.findFloor(350), 300); // Greater than max
    }

    function test_findFloor_outOfOrder() public {
        // Add timestamps out of order to test that findFloor still works
        timestamps.add(300);
        timestamps.add(100);
        timestamps.add(200);

        // Despite out-of-order insertion, findFloor should work correctly
        assertEq(timestamps.findFloor(50), 0); // Less than min
        assertEq(timestamps.findFloor(100), 100); // Exact match
        assertEq(timestamps.findFloor(150), 100); // Between values
        assertEq(timestamps.findFloor(200), 200); // Exact match
        assertEq(timestamps.findFloor(250), 200); // Between values
        assertEq(timestamps.findFloor(300), 300); // Exact match
        assertEq(timestamps.findFloor(350), 300); // Greater than max
    }

    function test_findFloor_complexOutOfOrder() public {
        // Add many timestamps out of order
        timestamps.add(500);
        timestamps.add(200);
        timestamps.add(700);
        timestamps.add(100);
        timestamps.add(400);
        timestamps.add(600);
        timestamps.add(300);

        // Test various floor queries
        assertEq(timestamps.findFloor(50), 0); // Less than min
        assertEq(timestamps.findFloor(100), 100); // Exact match
        assertEq(timestamps.findFloor(150), 100); // Between 100 and 200
        assertEq(timestamps.findFloor(250), 200); // Between 200 and 300
        assertEq(timestamps.findFloor(350), 300); // Between 300 and 400
        assertEq(timestamps.findFloor(450), 400); // Between 400 and 500
        assertEq(timestamps.findFloor(550), 500); // Between 500 and 600
        assertEq(timestamps.findFloor(650), 600); // Between 600 and 700
        assertEq(timestamps.findFloor(700), 700); // Exact match
        assertEq(timestamps.findFloor(800), 700); // Greater than max
    }

    /*//////////////////////////////////////////////////////////////
                            contains() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_contains_empty() public view {
        assertFalse(timestamps.contains(100));
    }

    function test_contains_singleElement() public {
        timestamps.add(100);

        assertTrue(timestamps.contains(100));
        assertFalse(timestamps.contains(99));
        assertFalse(timestamps.contains(101));
    }

    function test_contains_multipleElements() public {
        timestamps.add(100);
        timestamps.add(200);
        timestamps.add(300);

        assertTrue(timestamps.contains(100));
        assertTrue(timestamps.contains(200));
        assertTrue(timestamps.contains(300));
        assertFalse(timestamps.contains(150));
        assertFalse(timestamps.contains(0));
        assertFalse(timestamps.contains(400));
    }

    function test_contains_duplicates() public {
        timestamps.add(100);
        timestamps.add(100);
        timestamps.add(100);

        assertTrue(timestamps.contains(100));
    }

    /*//////////////////////////////////////////////////////////////
                            length() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_length_empty() public view {
        assertEq(timestamps.length(), 0);
    }

    function test_length_afterAdditions() public {
        assertEq(timestamps.length(), 0);

        timestamps.add(100);
        assertEq(timestamps.length(), 1);

        timestamps.add(200);
        assertEq(timestamps.length(), 2);

        timestamps.add(300);
        assertEq(timestamps.length(), 3);
    }

    /*//////////////////////////////////////////////////////////////
                            at() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_at_validIndices() public {
        timestamps.add(100);
        timestamps.add(200);
        timestamps.add(300);

        assertEq(timestamps.at(0), 100);
        assertEq(timestamps.at(1), 200);
        assertEq(timestamps.at(2), 300);
    }

    function test_at_outOfOrder() public {
        timestamps.add(300);
        timestamps.add(100);
        timestamps.add(200);

        // Returns values in insertion order, not sorted order
        assertEq(timestamps.at(0), 300);
        assertEq(timestamps.at(1), 100);
        assertEq(timestamps.at(2), 200);
    }

    function test_at_revertOutOfBounds() public {
        timestamps.add(100);

        // Test that accessing out of bounds index reverts
        // Note: Due to Foundry's expectRevert limitations with library calls at different depths,
        // we test this by attempting the call and catching the revert
        try this.attemptOutOfBoundsAccess() {
            fail("Expected revert for out of bounds access");
        } catch {
            // Expected revert occurred
        }
    }

    function attemptOutOfBoundsAccess() external view {
        timestamps.at(1); // Should revert - index out of bounds
    }

    /*//////////////////////////////////////////////////////////////
                            isEmpty() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_isEmpty_empty() public view {
        assertTrue(timestamps.isEmpty());
    }

    function test_isEmpty_afterAdd() public {
        timestamps.add(100);
        assertFalse(timestamps.isEmpty());
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_integration_settlementSimulation() public {
        // Simulate real-world settlement pattern: mostly chronological with some out-of-order

        // Day 1: Normal chronological settlements
        timestamps.add(1000);
        timestamps.add(1010);
        timestamps.add(1020);

        // Day 2: Late settlement from day 1
        timestamps.add(2000);
        timestamps.add(1015); // Out of order!
        timestamps.add(2010);

        // Verify getLast still returns maximum
        assertEq(timestamps.getLast(), 2010);

        // Verify findFloor works correctly despite out-of-order insertion
        assertEq(timestamps.findFloor(1005), 1000);
        assertEq(timestamps.findFloor(1012), 1010);
        assertEq(timestamps.findFloor(1017), 1015); // Correctly finds the out-of-order element
        assertEq(timestamps.findFloor(1500), 1020);
        assertEq(timestamps.findFloor(2005), 2000);
        assertEq(timestamps.findFloor(3000), 2010);
    }

    function test_integration_highFrequencySettlements() public {
        // Simulate high-frequency settlements (every 4-10 seconds) with occasional out-of-order
        uint64 baseTime = 1_000_000;

        // Add 1000 timestamps (simulating ~1-2 hours of settlements)
        for (uint64 i = 0; i < 1000; i++) {
            uint64 timestamp = baseTime + (i * 5); // Every 5 seconds

            // Occasionally add out-of-order (5% chance)
            if (i > 0 && i % 20 == 0) {
                timestamps.add(timestamp - 10); // Add slightly earlier timestamp
            }

            timestamps.add(timestamp);
        }

        // Verify max is correct
        assertEq(timestamps.getLast(), baseTime + (999 * 5));

        // Verify various floor queries work
        assertEq(timestamps.findFloor(baseTime - 100), 0); // Before first
        assertEq(timestamps.findFloor(baseTime), baseTime); // First element
        assertEq(timestamps.findFloor(baseTime + 2500), baseTime + 2500); // Middle element
        assertEq(timestamps.findFloor(baseTime + 10_000), baseTime + (999 * 5)); // After last
    }
}
