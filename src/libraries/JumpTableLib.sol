// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

/**
 * @title JumpTableLib
 * @notice Library for efficient range queries on sorted arrays using binary lifting technique
 * @dev Implements a data structure that maintains a sorted array with a jump table for O(log N) searches.
 *      The jump table uses binary lifting mechanism, allowing "lifting" by powers of 2 to quickly
 *      find positions in the sorted array. This is a pure data structure library with no business logic.
 */
library JumpTableLib {
    /**
     * @notice Data structure maintaining a sorted array with jump table optimization using binary lifting
     * @param values Sorted array of uint64 values
     * @param jumpTable Binary lifting table where jumpTable[i][k] = index that is 2^k positions back from i
     */
    struct JumpTable {
        uint64[] values;
        mapping(uint256 => mapping(uint256 => uint256)) jumpTable;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Maximum jump levels, supports up to 2^32 elements
    uint256 private constant MAX_JUMP_LEVELS = 32;
    // Sentinel value indicating no valid index
    uint256 private constant INVALID_INDEX = type(uint256).max;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ValueNotIncreasing();
    error EmptyArray();
    error IndexOutOfBounds();

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Appends a new value to the sorted array and updates the jump table
     * @dev The new value must be strictly greater than the last element. Uses binary lifting
     *      to build the jump table for O(log N) future lookups.
     * @param self The JumpTable storage reference
     * @param value The value to append
     */
    function append(JumpTable storage self, uint64 value) internal {
        uint256 index = self.values.length;

        // Ensure values are strictly increasing
        if (index > 0) {
            if (value <= self.values[index - 1]) {
                revert ValueNotIncreasing();
            }
        }

        self.values.push(value);

        // Build jump table for this new element
        // jumpTable[index][0] points to the previous element (or INVALID_INDEX if none)
        self.jumpTable[index][0] = (index == 0) ? INVALID_INDEX : index - 1;

        // Fill higher jump levels using dynamic programming
        for (uint256 k = 1; k < MAX_JUMP_LEVELS; k++) {
            uint256 midIndex = self.jumpTable[index][k - 1];
            if (midIndex == INVALID_INDEX) {
                self.jumpTable[index][k] = INVALID_INDEX;
            } else {
                self.jumpTable[index][k] = self.jumpTable[midIndex][k - 1];
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Finds the index of the first element greater than the target
     * @dev Uses binary lifting mechanism for O(log N) search complexity by jumping
     *      through powers of 2 positions in the array
     * @param self The JumpTable storage reference
     * @param target The value to search for
     * @return The index of the first element > target, or length if all elements <= target
     */
    function findUpperBound(JumpTable storage self, uint64 target) internal view returns (uint256) {
        uint256 n = self.values.length;

        // Empty array case
        if (n == 0) {
            return 0;
        }

        // If target is before first element
        if (target < self.values[0]) {
            return 0;
        }

        // Start from the last element
        uint256 current = n - 1;

        // If target is >= last element, return length (no upper bound)
        if (self.values[current] <= target) {
            return n;
        }

        // Use jump table to find the position efficiently
        for (uint256 k = MAX_JUMP_LEVELS; k > 0;) {
            unchecked {
                k--;
            }
            uint256 prev = self.jumpTable[current][k];
            if (prev != INVALID_INDEX && self.values[prev] > target) {
                current = prev;
            }
        }

        return current;
    }

    /**
     * @notice Returns the value at the specified index
     * @param self The JumpTable storage reference
     * @param index The index to query
     * @return The value at the index
     */
    function valueAt(JumpTable storage self, uint256 index) internal view returns (uint64) {
        if (index >= self.values.length) {
            revert IndexOutOfBounds();
        }
        return self.values[index];
    }

    /**
     * @notice Returns the number of elements in the array
     * @param self The JumpTable storage reference
     * @return The number of elements
     */
    function length(JumpTable storage self) internal view returns (uint256) {
        return self.values.length;
    }

    /**
     * @notice Checks if the array is empty
     * @param self The JumpTable storage reference
     * @return True if empty, false otherwise
     */
    function isEmpty(JumpTable storage self) internal view returns (bool) {
        return self.values.length == 0;
    }

    /**
     * @notice Returns all values in the array
     * @dev Useful for testing and debugging, but can be gas-intensive for large arrays
     * @param self The JumpTable storage reference
     * @return The array of all values
     */
    function getValues(JumpTable storage self) internal view returns (uint64[] memory) {
        return self.values;
    }
}
