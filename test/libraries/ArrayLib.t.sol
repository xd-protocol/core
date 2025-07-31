// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ArrayLib } from "../../src/libraries/ArrayLib.sol";

contract ArrayLibTest is Test {
    using ArrayLib for uint256[];

    uint256[] private testArray;

    function setUp() public {
        // Reset array before each test
        delete testArray;
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC INSERTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_insertSorted_emptyArray() public {
        testArray.insertSorted(100);

        assertEq(testArray.length, 1);
        assertEq(testArray[0], 100);
    }

    function test_insertSorted_singleElement_before() public {
        testArray.push(100);
        testArray.insertSorted(50);

        assertEq(testArray.length, 2);
        assertEq(testArray[0], 50);
        assertEq(testArray[1], 100);
    }

    function test_insertSorted_singleElement_after() public {
        testArray.push(100);
        testArray.insertSorted(150);

        assertEq(testArray.length, 2);
        assertEq(testArray[0], 100);
        assertEq(testArray[1], 150);
    }

    function test_insertSorted_multipleElements_beginning() public {
        testArray.push(20);
        testArray.push(30);
        testArray.push(40);

        testArray.insertSorted(10);

        assertEq(testArray.length, 4);
        assertEq(testArray[0], 10);
        assertEq(testArray[1], 20);
        assertEq(testArray[2], 30);
        assertEq(testArray[3], 40);
    }

    function test_insertSorted_multipleElements_middle() public {
        testArray.push(10);
        testArray.push(30);
        testArray.push(40);

        testArray.insertSorted(25);

        assertEq(testArray.length, 4);
        assertEq(testArray[0], 10);
        assertEq(testArray[1], 25);
        assertEq(testArray[2], 30);
        assertEq(testArray[3], 40);
    }

    function test_insertSorted_multipleElements_end() public {
        testArray.push(10);
        testArray.push(20);
        testArray.push(30);

        testArray.insertSorted(40);

        assertEq(testArray.length, 4);
        assertEq(testArray[0], 10);
        assertEq(testArray[1], 20);
        assertEq(testArray[2], 30);
        assertEq(testArray[3], 40);
    }

    /*//////////////////////////////////////////////////////////////
                        DUPLICATE VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_insertSorted_duplicateValue_beginning() public {
        testArray.push(10);
        testArray.push(20);
        testArray.push(30);

        testArray.insertSorted(10);

        assertEq(testArray.length, 4);
        assertEq(testArray[0], 10);
        assertEq(testArray[1], 10);
        assertEq(testArray[2], 20);
        assertEq(testArray[3], 30);
    }

    function test_insertSorted_duplicateValue_middle() public {
        testArray.push(10);
        testArray.push(20);
        testArray.push(30);

        testArray.insertSorted(20);

        assertEq(testArray.length, 4);
        assertEq(testArray[0], 10);
        assertEq(testArray[1], 20);
        assertEq(testArray[2], 20);
        assertEq(testArray[3], 30);
    }

    function test_insertSorted_duplicateValue_end() public {
        testArray.push(10);
        testArray.push(20);
        testArray.push(30);

        testArray.insertSorted(30);

        assertEq(testArray.length, 4);
        assertEq(testArray[0], 10);
        assertEq(testArray[1], 20);
        assertEq(testArray[2], 30);
        assertEq(testArray[3], 30);
    }

    function test_insertSorted_multipleDuplicates() public {
        testArray.push(10);
        testArray.push(10);
        testArray.push(20);
        testArray.push(20);

        testArray.insertSorted(10);
        testArray.insertSorted(20);

        assertEq(testArray.length, 6);
        assertEq(testArray[0], 10);
        assertEq(testArray[1], 10);
        assertEq(testArray[2], 10);
        assertEq(testArray[3], 20);
        assertEq(testArray[4], 20);
        assertEq(testArray[5], 20);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_insertSorted_zeroValue() public {
        testArray.push(10);
        testArray.push(20);

        testArray.insertSorted(0);

        assertEq(testArray.length, 3);
        assertEq(testArray[0], 0);
        assertEq(testArray[1], 10);
        assertEq(testArray[2], 20);
    }

    function test_insertSorted_maxValue() public {
        testArray.push(100);
        testArray.push(200);

        testArray.insertSorted(type(uint256).max);

        assertEq(testArray.length, 3);
        assertEq(testArray[0], 100);
        assertEq(testArray[1], 200);
        assertEq(testArray[2], type(uint256).max);
    }

    function test_insertSorted_consecutiveValues() public {
        for (uint256 i = 1; i <= 5; i++) {
            testArray.insertSorted(i);
        }

        assertEq(testArray.length, 5);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(testArray[i], i + 1);
        }
    }

    function test_insertSorted_reverseOrder() public {
        // Insert values in reverse order
        for (uint256 i = 5; i >= 1; i--) {
            testArray.insertSorted(i);
        }

        assertEq(testArray.length, 5);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(testArray[i], i + 1);
        }
    }

    function test_insertSorted_randomOrder() public {
        // Insert: 3, 1, 4, 1, 5, 9, 2, 6
        testArray.insertSorted(3);
        testArray.insertSorted(1);
        testArray.insertSorted(4);
        testArray.insertSorted(1);
        testArray.insertSorted(5);
        testArray.insertSorted(9);
        testArray.insertSorted(2);
        testArray.insertSorted(6);

        assertEq(testArray.length, 8);

        // Should be sorted: 1, 1, 2, 3, 4, 5, 6, 9
        uint256[] memory expected = new uint256[](8);
        expected[0] = 1;
        expected[1] = 1;
        expected[2] = 2;
        expected[3] = 3;
        expected[4] = 4;
        expected[5] = 5;
        expected[6] = 6;
        expected[7] = 9;

        for (uint256 i = 0; i < testArray.length; i++) {
            assertEq(testArray[i], expected[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                     LARGE ARRAY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_insertSorted_largeArray_sequential() public {
        uint256 size = 100;

        for (uint256 i = 0; i < size; i++) {
            testArray.insertSorted(i);
        }

        assertEq(testArray.length, size);
        for (uint256 i = 0; i < size; i++) {
            assertEq(testArray[i], i);
        }
    }

    function test_insertSorted_largeArray_reverse() public {
        uint256 size = 100;

        for (uint256 i = size; i > 0; i--) {
            testArray.insertSorted(i);
        }

        assertEq(testArray.length, size);
        for (uint256 i = 0; i < size; i++) {
            assertEq(testArray[i], i + 1);
        }
    }

    function test_insertSorted_largeArray_random() public {
        // Use block.timestamp as seed for reproducibility
        uint256 seed = block.timestamp;
        uint256 size = 50;

        for (uint256 i = 0; i < size; i++) {
            uint256 value = uint256(keccak256(abi.encode(seed, i))) % 1000;
            testArray.insertSorted(value);
        }

        // Verify array is sorted
        for (uint256 i = 1; i < testArray.length; i++) {
            assertLe(testArray[i - 1], testArray[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_insertSorted_singleValue(uint256 value) public {
        testArray.insertSorted(value);

        assertEq(testArray.length, 1);
        assertEq(testArray[0], value);
    }

    function testFuzz_insertSorted_twoValues(uint256 value1, uint256 value2) public {
        testArray.insertSorted(value1);
        testArray.insertSorted(value2);

        assertEq(testArray.length, 2);

        if (value1 <= value2) {
            assertEq(testArray[0], value1);
            assertEq(testArray[1], value2);
        } else {
            assertEq(testArray[0], value2);
            assertEq(testArray[1], value1);
        }
    }

    function testFuzz_insertSorted_multipleValues(uint256[10] memory values) public {
        for (uint256 i = 0; i < values.length; i++) {
            testArray.insertSorted(values[i]);
        }

        assertEq(testArray.length, values.length);

        // Verify array is sorted
        for (uint256 i = 1; i < testArray.length; i++) {
            assertLe(testArray[i - 1], testArray[i]);
        }
    }

    function testFuzz_insertSorted_maintainsSortedProperty(uint256[] memory values) public {
        vm.assume(values.length > 0 && values.length <= 20);

        for (uint256 i = 0; i < values.length; i++) {
            testArray.insertSorted(values[i]);

            // After each insertion, verify array is still sorted
            for (uint256 j = 1; j < testArray.length; j++) {
                assertLe(testArray[j - 1], testArray[j]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GAS OPTIMIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_insertSorted_gasOptimization_appendOnly() public {
        // Best case: always appending (already sorted input)
        uint256 gasStart = gasleft();

        for (uint256 i = 0; i < 10; i++) {
            testArray.insertSorted(i * 10);
        }

        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas used for 10 append operations", gasUsed);

        // Verify correctness
        assertEq(testArray.length, 10);
        for (uint256 i = 0; i < 10; i++) {
            assertEq(testArray[i], i * 10);
        }
    }

    function test_insertSorted_gasOptimization_prependOnly() public {
        // Worst case: always prepending (reverse sorted input)
        uint256 gasStart = gasleft();

        for (uint256 i = 10; i > 0; i--) {
            testArray.insertSorted(i * 10);
        }

        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas used for 10 prepend operations", gasUsed);

        // Verify correctness
        assertEq(testArray.length, 10);
        for (uint256 i = 0; i < 10; i++) {
            assertEq(testArray[i], (i + 1) * 10);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function assertArrayEquals(uint256[] memory a, uint256[] memory b) internal pure {
        require(a.length == b.length, "Array length mismatch");
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] == b[i], "Array element mismatch");
        }
    }

    function isSorted(uint256[] memory arr) internal pure returns (bool) {
        for (uint256 i = 1; i < arr.length; i++) {
            if (arr[i - 1] > arr[i]) {
                return false;
            }
        }
        return true;
    }
}
