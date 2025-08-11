// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { SnapshotsLib } from "../../src/libraries/SnapshotsLib.sol";

contract SnapshotsLibTest is Test {
    using SnapshotsLib for SnapshotsLib.Snapshots;

    SnapshotsLib.Snapshots private snapshots;

    /*//////////////////////////////////////////////////////////////
                               BASIC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_set_and_get_single() public {
        snapshots.set(bytes32(uint256(100)));

        assertEq(uint256(snapshots.get()), 100);
        assertEq(uint256(snapshots.get(block.timestamp)), 100);
        assertEq(uint256(snapshots.get(block.timestamp + 1)), 100);
    }

    function test_set_and_get_multiple_sequential() public {
        // Set values at different timestamps
        vm.warp(1000);
        snapshots.set(bytes32(uint256(100)));

        vm.warp(2000);
        snapshots.set(bytes32(uint256(200)));

        vm.warp(3000);
        snapshots.set(bytes32(uint256(300)));

        // Test get() at various timestamps
        assertEq(uint256(snapshots.get(500)), 0); // Before first snapshot
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(1500)), 100);
        assertEq(uint256(snapshots.get(2000)), 200);
        assertEq(uint256(snapshots.get(2500)), 200);
        assertEq(uint256(snapshots.get(3000)), 300);
        assertEq(uint256(snapshots.get(4000)), 300);
    }

    function test_get_empty_snapshots() public view {
        assertEq(uint256(snapshots.get(block.timestamp)), 0);
        assertEq(uint256(snapshots.get()), 0);
        assertEq(snapshots.getAsInt(), 0);
        assertEq(snapshots.getAsInt(block.timestamp), 0);
    }

    /*//////////////////////////////////////////////////////////////
                         PAST TIMESTAMP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_set_past_timestamp_single() public {
        vm.warp(3000);

        // Set a value at current timestamp
        snapshots.set(bytes32(uint256(300)), 3000);

        // Set a value in the past
        snapshots.set(bytes32(uint256(100)), 1000);

        // Verify both values
        assertEq(uint256(snapshots.get(999)), 0);
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(2000)), 100);
        assertEq(uint256(snapshots.get(3000)), 300);
        assertEq(uint256(snapshots.get(4000)), 300);
    }

    function test_set_past_timestamp_multiple() public {
        vm.warp(5000);

        // Set values out of order
        snapshots.set(bytes32(uint256(500)), 5000);
        snapshots.set(bytes32(uint256(100)), 1000);
        snapshots.set(bytes32(uint256(300)), 3000);
        snapshots.set(bytes32(uint256(200)), 2000);
        snapshots.set(bytes32(uint256(400)), 4000);

        // Verify all values are correctly ordered
        assertEq(uint256(snapshots.get(500)), 0);
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(1500)), 100);
        assertEq(uint256(snapshots.get(2000)), 200);
        assertEq(uint256(snapshots.get(2500)), 200);
        assertEq(uint256(snapshots.get(3000)), 300);
        assertEq(uint256(snapshots.get(3500)), 300);
        assertEq(uint256(snapshots.get(4000)), 400);
        assertEq(uint256(snapshots.get(4500)), 400);
        assertEq(uint256(snapshots.get(5000)), 500);
        assertEq(uint256(snapshots.get(6000)), 500);
    }

    function test_set_past_timestamp_insert_beginning() public {
        vm.warp(5000);

        // Set some values
        snapshots.set(bytes32(uint256(200)), 2000);
        snapshots.set(bytes32(uint256(300)), 3000);
        snapshots.set(bytes32(uint256(400)), 4000);

        // Insert at the beginning
        snapshots.set(bytes32(uint256(100)), 1000);

        // Verify correct ordering
        assertEq(uint256(snapshots.get(500)), 0);
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(2000)), 200);
        assertEq(uint256(snapshots.get(3000)), 300);
        assertEq(uint256(snapshots.get(4000)), 400);
    }

    function test_set_past_timestamp_insert_middle() public {
        vm.warp(5000);

        // Set values with a gap
        snapshots.set(bytes32(uint256(100)), 1000);
        snapshots.set(bytes32(uint256(300)), 3000);
        snapshots.set(bytes32(uint256(500)), 5000);

        // Insert in the middle
        snapshots.set(bytes32(uint256(200)), 2000);
        snapshots.set(bytes32(uint256(400)), 4000);

        // Verify correct ordering
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(2000)), 200);
        assertEq(uint256(snapshots.get(3000)), 300);
        assertEq(uint256(snapshots.get(4000)), 400);
        assertEq(uint256(snapshots.get(5000)), 500);
    }

    function test_set_past_timestamp_complex_sequence() public {
        vm.warp(10_000);

        // Complex insertion pattern
        snapshots.set(bytes32(uint256(5000)), 5000);
        snapshots.set(bytes32(uint256(9000)), 9000);
        snapshots.set(bytes32(uint256(1000)), 1000);
        snapshots.set(bytes32(uint256(7000)), 7000);
        snapshots.set(bytes32(uint256(3000)), 3000);
        snapshots.set(bytes32(uint256(6000)), 6000);
        snapshots.set(bytes32(uint256(2000)), 2000);
        snapshots.set(bytes32(uint256(8000)), 8000);
        snapshots.set(bytes32(uint256(4000)), 4000);

        // Verify all values are correctly ordered
        for (uint256 i = 1; i <= 9; i++) {
            uint256 timestamp = i * 1000;
            assertEq(uint256(snapshots.get(timestamp)), timestamp);
            assertEq(uint256(snapshots.get(timestamp + 500)), timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_update_existing_timestamp() public {
        vm.warp(3000);

        // Set initial values
        snapshots.set(bytes32(uint256(100)), 1000);
        snapshots.set(bytes32(uint256(200)), 2000);
        snapshots.set(bytes32(uint256(300)), 3000);

        // Update existing timestamp
        snapshots.set(bytes32(uint256(999)), 2000);

        // Verify update
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(2000)), 999);
        assertEq(uint256(snapshots.get(3000)), 300);
    }

    function test_update_last_timestamp() public {
        vm.warp(3000);

        // Set initial values
        snapshots.set(bytes32(uint256(100)), 1000);
        snapshots.set(bytes32(uint256(200)), 2000);
        snapshots.set(bytes32(uint256(300)), 3000);

        // Update last timestamp
        snapshots.set(bytes32(uint256(999)), 3000);

        // Verify update
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(2000)), 200);
        assertEq(uint256(snapshots.get(3000)), 999);
        assertEq(uint256(snapshots.get(4000)), 999);
    }

    function test_update_past_timestamp() public {
        vm.warp(5000);

        // Set initial values
        snapshots.set(bytes32(uint256(100)), 1000);
        snapshots.set(bytes32(uint256(200)), 2000);
        snapshots.set(bytes32(uint256(300)), 3000);

        // Update past timestamp
        snapshots.set(bytes32(uint256(999)), 1000);

        // Verify update
        assertEq(uint256(snapshots.get(1000)), 999);
        assertEq(uint256(snapshots.get(2000)), 200);
        assertEq(uint256(snapshots.get(3000)), 300);
    }

    /*//////////////////////////////////////////////////////////////
                           INT CONVERSION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setAsInt_and_getAsInt() public {
        vm.warp(1000);
        snapshots.setAsInt(-100);

        vm.warp(2000);
        snapshots.setAsInt(200);

        vm.warp(3000);
        snapshots.setAsInt(-300);

        assertEq(snapshots.getAsInt(1000), -100);
        assertEq(snapshots.getAsInt(2000), 200);
        assertEq(snapshots.getAsInt(3000), -300);
        assertEq(snapshots.getAsInt(), -300);
    }

    function test_setAsInt_with_timestamp() public {
        vm.warp(5000);

        // Set values with specific timestamps
        snapshots.setAsInt(-100, 1000);
        snapshots.setAsInt(200, 3000);
        snapshots.setAsInt(-150, 2000); // Insert in past

        assertEq(snapshots.getAsInt(500), 0);
        assertEq(snapshots.getAsInt(1000), -100);
        assertEq(snapshots.getAsInt(1500), -100);
        assertEq(snapshots.getAsInt(2000), -150);
        assertEq(snapshots.getAsInt(2500), -150);
        assertEq(snapshots.getAsInt(3000), 200);
        assertEq(snapshots.getAsInt(4000), 200);
    }

    /*//////////////////////////////////////////////////////////////
                          EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_set_same_value_different_timestamps() public {
        vm.warp(5000);

        // Set same value at different timestamps
        snapshots.set(bytes32(uint256(100)), 1000);
        snapshots.set(bytes32(uint256(100)), 2000);
        snapshots.set(bytes32(uint256(100)), 3000);

        // All should return the same value
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(2000)), 100);
        assertEq(uint256(snapshots.get(3000)), 100);
    }

    function test_set_zero_value() public {
        vm.warp(1000);
        snapshots.set(bytes32(uint256(0)));

        // Zero value should be stored
        assertEq(uint256(snapshots.get(1000)), 0);
        assertEq(uint256(snapshots.get()), 0);
    }

    function test_set_max_value() public {
        uint256 maxValue = type(uint256).max;
        vm.warp(1000);
        snapshots.set(bytes32(maxValue));

        assertEq(uint256(snapshots.get(1000)), maxValue);
        assertEq(uint256(snapshots.get()), maxValue);
    }

    function test_binary_search_boundaries() public {
        vm.warp(10_000);

        // Set values at specific timestamps to test binary search
        for (uint256 i = 1; i <= 10; i++) {
            snapshots.set(bytes32(i * 100), i * 1000);
        }

        // Test exact boundaries
        assertEq(uint256(snapshots.get(999)), 0);
        assertEq(uint256(snapshots.get(1000)), 100);
        assertEq(uint256(snapshots.get(10_000)), 1000);
        assertEq(uint256(snapshots.get(10_001)), 1000);

        // Test mid-points
        for (uint256 i = 1; i < 10; i++) {
            uint256 midpoint = i * 1000 + 500;
            assertEq(uint256(snapshots.get(midpoint)), i * 100);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_set_and_get(uint256 value, uint256 timestamp) public {
        vm.assume(timestamp > 0 && timestamp < type(uint64).max);
        vm.warp(timestamp);

        snapshots.set(bytes32(value));

        assertEq(uint256(snapshots.get(timestamp)), value);
        assertEq(uint256(snapshots.get(timestamp + 1)), value);
        assertEq(uint256(snapshots.get()), value);
    }

    function testFuzz_set_past_timestamps(uint256[5] memory values, uint256[5] memory timestamps) public {
        // Ensure timestamps are valid and different
        for (uint256 i = 0; i < 5; i++) {
            timestamps[i] = bound(timestamps[i], i + 1, 1_000_000 + i);
        }

        // Set the latest timestamp as current time
        uint256 maxTimestamp = 0;
        for (uint256 i = 0; i < 5; i++) {
            if (timestamps[i] > maxTimestamp) {
                maxTimestamp = timestamps[i];
            }
        }
        vm.warp(maxTimestamp + 1);

        // Set values in random order
        for (uint256 i = 0; i < 5; i++) {
            snapshots.set(bytes32(values[i]), timestamps[i]);
        }

        // Verify each value can be retrieved
        for (uint256 i = 0; i < 5; i++) {
            // Find the expected value by simulating what SnapshotsLib does:
            // It returns the value at the highest timestamp <= query timestamp
            // If multiple values are set at the same timestamp, the last one wins

            // Build a map of final values at each unique timestamp
            uint256 expectedValue = 0;
            uint256 highestValidTimestamp = 0;

            // Check all snapshots to find what value would be stored at each timestamp
            for (uint256 j = 0; j < 5; j++) {
                if (timestamps[j] <= timestamps[i]) {
                    // This value could be a candidate
                    if (timestamps[j] > highestValidTimestamp) {
                        // New highest timestamp
                        highestValidTimestamp = timestamps[j];
                        expectedValue = values[j];
                    } else if (timestamps[j] == highestValidTimestamp) {
                        // Same timestamp - the later set value wins (higher index)
                        expectedValue = values[j];
                    }
                }
            }

            assertEq(uint256(snapshots.get(timestamps[i])), expectedValue);
        }
    }

    function testFuzz_setAsInt(int256 value, uint256 timestamp) public {
        vm.assume(timestamp > 0 && timestamp < type(uint64).max);
        vm.warp(timestamp);

        snapshots.setAsInt(value);

        assertEq(snapshots.getAsInt(timestamp), value);
        assertEq(snapshots.getAsInt(), value);
    }

    /*//////////////////////////////////////////////////////////////
                         STRESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_large_number_of_snapshots() public {
        vm.warp(100_000);

        // Set 100 snapshots
        for (uint256 i = 1; i <= 100; i++) {
            snapshots.set(bytes32(i * 10), i * 100);
        }

        // Verify some key points
        assertEq(uint256(snapshots.get(50)), 0); // Before first
        assertEq(uint256(snapshots.get(100)), 10); // First
        assertEq(uint256(snapshots.get(5000)), 500); // Middle
        assertEq(uint256(snapshots.get(10_000)), 1000); // Last
        assertEq(uint256(snapshots.get(20_000)), 1000); // After last
    }

    function test_alternating_past_future_inserts() public {
        vm.warp(10_000);

        // Alternate between inserting in past and appending
        snapshots.set(bytes32(uint256(5000)), 5000);
        snapshots.set(bytes32(uint256(7000)), 7000); // Append
        snapshots.set(bytes32(uint256(3000)), 3000); // Past
        snapshots.set(bytes32(uint256(9000)), 9000); // Append
        snapshots.set(bytes32(uint256(1000)), 1000); // Past
        snapshots.set(bytes32(uint256(8000)), 8000); // Past but after 7000
        snapshots.set(bytes32(uint256(2000)), 2000); // Past

        // Verify ordering is maintained
        uint256 lastValue = 0;
        for (uint256 i = 1; i <= 9; i++) {
            if (i == 4 || i == 6) continue; // Skip missing timestamps
            uint256 timestamp = i * 1000;
            uint256 value = uint256(snapshots.get(timestamp));
            assertEq(value, timestamp);
            assertGe(value, lastValue);
            lastValue = value;
        }
    }
}
