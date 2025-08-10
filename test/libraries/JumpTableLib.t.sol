// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import { JumpTableLib } from "src/libraries/JumpTableLib.sol";

contract JumpTableLibTest is Test {
    using JumpTableLib for JumpTableLib.JumpTable;

    JumpTableLib.JumpTable internal table;

    /*//////////////////////////////////////////////////////////////
                            APPEND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_append_empty() public {
        assertEq(table.length(), 0);
        assertTrue(table.isEmpty());

        table.append(100);

        assertEq(table.length(), 1);
        assertFalse(table.isEmpty());
        assertEq(table.valueAt(0), 100);
    }

    function test_append_multiple() public {
        table.append(100);
        table.append(200);
        table.append(300);

        assertEq(table.length(), 3);
        assertEq(table.valueAt(0), 100);
        assertEq(table.valueAt(1), 200);
        assertEq(table.valueAt(2), 300);
    }

    function test_append_revertNotIncreasing() public {
        table.append(100);

        // Equal value should revert
        vm.expectRevert(JumpTableLib.ValueNotIncreasing.selector);
        this.callAppend(100);

        // Lower value should revert
        vm.expectRevert(JumpTableLib.ValueNotIncreasing.selector);
        this.callAppend(50);
    }

    function test_append_largeGap() public {
        table.append(100);
        table.append(1_000_000);

        assertEq(table.length(), 2);
        assertEq(table.valueAt(0), 100);
        assertEq(table.valueAt(1), 1_000_000);
    }

    function testFuzz_append(uint64[] memory values) public {
        vm.assume(values.length > 0 && values.length <= 100);

        // Sort values and make them strictly increasing
        for (uint256 i = 0; i < values.length - 1; i++) {
            for (uint256 j = i + 1; j < values.length; j++) {
                if (values[i] >= values[j]) {
                    uint64 temp = values[i];
                    values[i] = values[j];
                    values[j] = temp;
                }
            }
        }

        // Make strictly increasing, handle overflow
        uint256 validLength = values.length;
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] <= values[i - 1]) {
                if (values[i - 1] == type(uint64).max) {
                    // Can't increment further, truncate array
                    validLength = i;
                    break;
                }
                values[i] = values[i - 1] + 1;
            }
        }

        // Append valid values only
        for (uint256 i = 0; i < validLength; i++) {
            table.append(values[i]);
        }

        assertEq(table.length(), validLength);

        // Verify all values
        for (uint256 i = 0; i < validLength; i++) {
            assertEq(table.valueAt(i), values[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        FIND UPPER BOUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_findUpperBound_empty() public view {
        assertEq(table.findUpperBound(100), 0);
        assertEq(table.findUpperBound(0), 0);
        assertEq(table.findUpperBound(type(uint64).max), 0);
    }

    function test_findUpperBound_singleElement() public {
        table.append(100);

        assertEq(table.findUpperBound(50), 0); // 50 < 100, upper bound is index 0
        assertEq(table.findUpperBound(100), 1); // 100 == 100, upper bound is past end
        assertEq(table.findUpperBound(150), 1); // 150 > 100, upper bound is past end
    }

    function test_findUpperBound_multipleElements() public {
        table.append(100);
        table.append(200);
        table.append(300);
        table.append(400);

        // Before first element
        assertEq(table.findUpperBound(50), 0);

        // Between elements
        assertEq(table.findUpperBound(150), 1); // Upper bound is 200 at index 1
        assertEq(table.findUpperBound(250), 2); // Upper bound is 300 at index 2
        assertEq(table.findUpperBound(350), 3); // Upper bound is 400 at index 3

        // Equal to elements
        assertEq(table.findUpperBound(100), 1); // Upper bound is 200 at index 1
        assertEq(table.findUpperBound(200), 2); // Upper bound is 300 at index 2
        assertEq(table.findUpperBound(300), 3); // Upper bound is 400 at index 3
        assertEq(table.findUpperBound(400), 4); // No upper bound, returns length

        // After last element
        assertEq(table.findUpperBound(500), 4); // No upper bound, returns length
    }

    function test_findUpperBound_largeArray() public {
        // Add 100 elements: 10, 20, 30, ..., 1000
        for (uint64 i = 1; i <= 100; i++) {
            table.append(i * 10);
        }

        assertEq(table.length(), 100);

        // Test various points
        assertEq(table.findUpperBound(5), 0); // Before first
        assertEq(table.findUpperBound(15), 1); // Between first and second
        assertEq(table.findUpperBound(100), 10); // Equal to 10th element
        assertEq(table.findUpperBound(505), 50); // Between 50th and 51st
        assertEq(table.findUpperBound(995), 99); // Between last two
        assertEq(table.findUpperBound(1000), 100); // Equal to last
        assertEq(table.findUpperBound(1001), 100); // After last
    }

    function test_findUpperBound_binaryLifting() public {
        // Test that binary lifting works correctly with powers of 2
        for (uint64 i = 0; i < 32; i++) {
            table.append(uint64(1) << i);
        }

        // Test finding upper bounds for values just below powers of 2
        for (uint64 i = 1; i < 32; i++) {
            uint64 value = (uint64(1) << i) - 1;
            uint256 upperBound = table.findUpperBound(value);
            assertEq(upperBound, i);
            assertEq(table.valueAt(upperBound), uint64(1) << i);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESSOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_valueAt() public {
        table.append(100);
        table.append(200);
        table.append(300);

        assertEq(table.valueAt(0), 100);
        assertEq(table.valueAt(1), 200);
        assertEq(table.valueAt(2), 300);

        // Out of bounds should revert
        vm.expectRevert(JumpTableLib.IndexOutOfBounds.selector);
        this.callValueAt(3);
    }

    function test_length() public {
        assertEq(table.length(), 0);

        table.append(100);
        assertEq(table.length(), 1);

        table.append(200);
        assertEq(table.length(), 2);

        table.append(300);
        assertEq(table.length(), 3);
    }

    function test_isEmpty() public {
        assertTrue(table.isEmpty());

        table.append(100);
        assertFalse(table.isEmpty());
    }

    function test_getValues() public {
        table.append(100);
        table.append(200);
        table.append(300);

        uint64[] memory values = table.getValues();
        assertEq(values.length, 3);
        assertEq(values[0], 100);
        assertEq(values[1], 200);
        assertEq(values[2], 300);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_edgeCase_maxValues() public {
        table.append(0);
        table.append(1);
        table.append(type(uint64).max - 1);
        table.append(type(uint64).max);

        assertEq(table.findUpperBound(0), 1);
        assertEq(table.findUpperBound(1), 2);
        assertEq(table.findUpperBound(type(uint64).max - 2), 2);
        assertEq(table.findUpperBound(type(uint64).max - 1), 3);
        assertEq(table.findUpperBound(type(uint64).max), 4);
    }

    function test_edgeCase_consecutiveValues() public {
        for (uint64 i = 1; i <= 10; i++) {
            table.append(i);
        }

        for (uint64 i = 0; i < 10; i++) {
            assertEq(table.findUpperBound(i), i);
        }
        assertEq(table.findUpperBound(10), 10);
    }

    /*//////////////////////////////////////////////////////////////
                            GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gas_append() public {
        uint256 gasStart;
        uint256 gasUsed;

        // Measure gas for different array sizes
        for (uint64 i = 1; i <= 100; i++) {
            gasStart = gasleft();
            table.append(i * 100);
            gasUsed = gasStart - gasleft();

            // Gas should be reasonable even for large arrays
            // Note: Gas increases as array grows due to jump table updates
            assertLt(gasUsed, 1_000_000);
        }
    }

    function test_gas_findUpperBound() public {
        // Create large array
        for (uint64 i = 1; i <= 1000; i++) {
            table.append(i * 100);
        }

        uint256 gasStart = gasleft();
        table.findUpperBound(50_000); // Middle of array
        uint256 gasUsed = gasStart - gasleft();

        // Should use O(log N) gas due to binary lifting
        assertLt(gasUsed, 50_000);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_invariant_sortedArray() public {
        table.append(100);
        table.append(200);
        table.append(300);
        table.append(400);

        uint64[] memory values = table.getValues();
        for (uint256 i = 1; i < values.length; i++) {
            assertTrue(values[i] > values[i - 1], "Array not strictly increasing");
        }
    }

    function test_invariant_findUpperBoundCorrectness() public {
        table.append(100);
        table.append(200);
        table.append(300);

        // For any value, findUpperBound should return the correct index
        for (uint64 target = 0; target <= 400; target += 10) {
            uint256 upperBound = table.findUpperBound(target);

            // Verify the invariant:
            // All elements before upperBound should be <= target
            for (uint256 i = 0; i < upperBound && i < table.length(); i++) {
                assertTrue(table.valueAt(i) <= target, "Element before upper bound too large");
            }

            // Element at upperBound (if exists) should be > target
            if (upperBound < table.length()) {
                assertTrue(table.valueAt(upperBound) > target, "Upper bound element not greater than target");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Helper functions to make calls external for expectRevert
    function callAppend(uint64 value) external {
        table.append(value);
    }

    function callValueAt(uint256 index) external view returns (uint64) {
        return table.valueAt(index);
    }
}
