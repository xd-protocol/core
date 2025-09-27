// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ArrayLib } from "../../src/libraries/ArrayLib.sol";

contract ArrayLibTest is Test {
    using ArrayLib for uint256[];

    uint256[] internal values;
    uint256[] internal indices;

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Reset arrays for each test
        delete values;
        delete indices;
    }

    /*//////////////////////////////////////////////////////////////
                    insertSortedIndex() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_insertSortedIndex_emptyArray() public {
        values.push(100);

        indices.insertSortedIndex(values, 0);

        assertEq(indices.length, 1);
        assertEq(indices[0], 0);
    }

    function test_insertSortedIndex_chronological() public {
        // Add values in chronological order
        values.push(100);
        values.push(200);
        values.push(300);

        indices.insertSortedIndex(values, 0);
        indices.insertSortedIndex(values, 1);
        indices.insertSortedIndex(values, 2);

        // Indices should be in order [0, 1, 2]
        assertEq(indices.length, 3);
        assertEq(indices[0], 0);
        assertEq(indices[1], 1);
        assertEq(indices[2], 2);
    }

    function test_insertSortedIndex_reverseOrder() public {
        // Add values in reverse order
        values.push(300);
        values.push(200);
        values.push(100);

        indices.insertSortedIndex(values, 0);
        indices.insertSortedIndex(values, 1);
        indices.insertSortedIndex(values, 2);

        // Indices should be sorted by values: [2, 1, 0]
        // Because values[2]=100, values[1]=200, values[0]=300
        assertEq(indices.length, 3);
        assertEq(indices[0], 2); // Points to 100
        assertEq(indices[1], 1); // Points to 200
        assertEq(indices[2], 0); // Points to 300

        // Verify the values through indices
        assertEq(values[indices[0]], 100);
        assertEq(values[indices[1]], 200);
        assertEq(values[indices[2]], 300);
    }

    function test_insertSortedIndex_outOfOrder() public {
        // Add values out of order
        values.push(200); // index 0
        values.push(100); // index 1
        values.push(300); // index 2
        values.push(150); // index 3

        indices.insertSortedIndex(values, 0); // 200
        indices.insertSortedIndex(values, 1); // 100
        indices.insertSortedIndex(values, 2); // 300
        indices.insertSortedIndex(values, 3); // 150

        // Indices should be sorted by values: [1, 3, 0, 2]
        // values[1]=100, values[3]=150, values[0]=200, values[2]=300
        assertEq(indices.length, 4);
        assertEq(values[indices[0]], 100);
        assertEq(values[indices[1]], 150);
        assertEq(values[indices[2]], 200);
        assertEq(values[indices[3]], 300);
    }

    function test_insertSortedIndex_duplicates() public {
        values.push(100);
        values.push(100);
        values.push(100);

        indices.insertSortedIndex(values, 0);
        indices.insertSortedIndex(values, 1);
        indices.insertSortedIndex(values, 2);

        assertEq(indices.length, 3);
        // All point to value 100
        assertEq(values[indices[0]], 100);
        assertEq(values[indices[1]], 100);
        assertEq(values[indices[2]], 100);
    }

    /*//////////////////////////////////////////////////////////////
                    findFloorIndex() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_findFloorIndex_emptyArray() public view {
        (uint256 index, bool found) = indices.findFloorIndex(values, 100);

        assertEq(index, 0);
        assertFalse(found);
    }

    function test_findFloorIndex_singleElement() public {
        values.push(100);
        indices.push(0);

        // Target less than min
        (uint256 index, bool found) = indices.findFloorIndex(values, 50);
        assertEq(index, 0);
        assertFalse(found);

        // Exact match
        (index, found) = indices.findFloorIndex(values, 100);
        assertEq(index, 0);
        assertTrue(found);
        assertEq(values[index], 100);

        // Target greater than max
        (index, found) = indices.findFloorIndex(values, 150);
        assertEq(index, 0);
        assertTrue(found);
        assertEq(values[index], 100);
    }

    function test_findFloorIndex_sortedArray() public {
        // Create sorted values and indices
        values.push(100);
        values.push(200);
        values.push(300);
        values.push(400);

        indices.push(0);
        indices.push(1);
        indices.push(2);
        indices.push(3);

        // Test various targets
        (uint256 index, bool found) = indices.findFloorIndex(values, 50);
        assertFalse(found);

        (index, found) = indices.findFloorIndex(values, 100);
        assertTrue(found);
        assertEq(index, 0);
        assertEq(values[index], 100);

        (index, found) = indices.findFloorIndex(values, 150);
        assertTrue(found);
        assertEq(index, 0);
        assertEq(values[index], 100);

        (index, found) = indices.findFloorIndex(values, 250);
        assertTrue(found);
        assertEq(index, 1);
        assertEq(values[index], 200);

        (index, found) = indices.findFloorIndex(values, 400);
        assertTrue(found);
        assertEq(index, 3);
        assertEq(values[index], 400);

        (index, found) = indices.findFloorIndex(values, 500);
        assertTrue(found);
        assertEq(index, 3);
        assertEq(values[index], 400);
    }

    function test_findFloorIndex_unsortedValues() public {
        // Values are unsorted
        values.push(300); // index 0
        values.push(100); // index 1
        values.push(400); // index 2
        values.push(200); // index 3

        // But indices maintain sorted order
        indices.push(1); // points to 100
        indices.push(3); // points to 200
        indices.push(0); // points to 300
        indices.push(2); // points to 400

        // Test floor queries
        (uint256 index, bool found) = indices.findFloorIndex(values, 150);
        assertTrue(found);
        assertEq(index, 1); // Points to values[1] = 100
        assertEq(values[index], 100);

        (index, found) = indices.findFloorIndex(values, 250);
        assertTrue(found);
        assertEq(index, 3); // Points to values[3] = 200
        assertEq(values[index], 200);

        (index, found) = indices.findFloorIndex(values, 350);
        assertTrue(found);
        assertEq(index, 0); // Points to values[0] = 300
        assertEq(values[index], 300);

        (index, found) = indices.findFloorIndex(values, 500);
        assertTrue(found);
        assertEq(index, 2); // Points to values[2] = 400
        assertEq(values[index], 400);
    }

    function test_findFloorIndex_duplicateValues() public {
        values.push(100);
        values.push(200);
        values.push(200); // Duplicate
        values.push(200); // Duplicate
        values.push(300);

        indices.push(0); // 100
        indices.push(1); // 200
        indices.push(2); // 200
        indices.push(3); // 200
        indices.push(4); // 300

        // Query for 200 should return one of the 200s
        (uint256 index, bool found) = indices.findFloorIndex(values, 200);
        assertTrue(found);
        assertEq(values[index], 200);

        // Query for 250 should return one of the 200s
        (index, found) = indices.findFloorIndex(values, 250);
        assertTrue(found);
        assertEq(values[index], 200);
    }

    /*//////////////////////////////////////////////////////////////
                    EXISTING FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_last_emptyArray() public view {
        assertEq(values.last(), 0);
    }

    function test_last_singleElement() public {
        values.push(100);
        assertEq(values.last(), 100);
    }

    function test_last_multipleElements() public {
        values.push(100);
        values.push(200);
        values.push(300);
        assertEq(values.last(), 300);
    }

    function test_findFloor_emptyArray() public view {
        assertEq(values.findFloor(100), 0);
    }

    function test_findFloor_sortedArray() public {
        values.push(100);
        values.push(200);
        values.push(300);

        assertEq(values.findFloor(50), 0);
        assertEq(values.findFloor(100), 100);
        assertEq(values.findFloor(150), 100);
        assertEq(values.findFloor(200), 200);
        assertEq(values.findFloor(250), 200);
        assertEq(values.findFloor(300), 300);
        assertEq(values.findFloor(350), 300);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_integration_dualArrayPattern() public {
        // Simulate the dual array pattern used in TimestampArrayLib

        // Add timestamps out of order
        values.push(500);
        values.push(200);
        values.push(700);
        values.push(100);
        values.push(400);
        values.push(600);
        values.push(300);

        // Build sorted indices
        for (uint256 i = 0; i < values.length; i++) {
            indices.insertSortedIndex(values, i);
        }

        // Verify indices are correctly sorted
        assertEq(values[indices[0]], 100);
        assertEq(values[indices[1]], 200);
        assertEq(values[indices[2]], 300);
        assertEq(values[indices[3]], 400);
        assertEq(values[indices[4]], 500);
        assertEq(values[indices[5]], 600);
        assertEq(values[indices[6]], 700);

        // Test floor queries
        (uint256 index, bool found) = indices.findFloorIndex(values, 250);
        assertTrue(found);
        assertEq(values[index], 200);

        (index, found) = indices.findFloorIndex(values, 550);
        assertTrue(found);
        assertEq(values[index], 500);

        (index, found) = indices.findFloorIndex(values, 1000);
        assertTrue(found);
        assertEq(values[index], 700);
    }

    function testFuzz_insertAndFind(uint256[] memory randomValues) public {
        vm.assume(randomValues.length > 0 && randomValues.length <= 100);

        // Add all values
        for (uint256 i = 0; i < randomValues.length; i++) {
            values.push(randomValues[i] % 10_000); // Bound values for reasonable range
        }

        // Build sorted indices
        for (uint256 i = 0; i < values.length; i++) {
            indices.insertSortedIndex(values, i);
        }

        // Verify indices maintain sorted order
        for (uint256 i = 1; i < indices.length; i++) {
            assertTrue(values[indices[i]] >= values[indices[i - 1]]);
        }

        // Test floor query for middle value
        if (indices.length > 0) {
            uint256 midIndex = indices[indices.length / 2];
            uint256 midValue = values[midIndex];

            (uint256 foundIndex, bool found) = indices.findFloorIndex(values, midValue);
            assertTrue(found);
            assertTrue(values[foundIndex] <= midValue);
        }
    }
}
