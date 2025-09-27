// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ArrayLib } from "./ArrayLib.sol";

/**
 * @title TimestampArrayLib
 * @notice Library for efficient timestamp storage and retrieval using dual array pattern
 * @dev Provides O(1) append operations and O(log n) search operations while maintaining
 *      the ability to query for the maximum value in O(1) time.
 *      Uses an unsorted data array for fast appends and a sorted index array for binary searches.
 */
library TimestampArrayLib {
    using ArrayLib for uint256[];

    /**
     * @notice Structure that maintains timestamps with efficient operations
     * @param values Unsorted array of timestamp values for O(1) append
     * @param indices Sorted array of indices pointing to values array
     * @param maxValue The maximum timestamp value for O(1) max queries
     */
    struct TimestampArray {
        uint256[] values; // Unsorted timestamps
        uint256[] indices; // Sorted indices into values array
        uint64 maxValue; // Track maximum for O(1) getLast
    }

    /**
     * @notice Adds a timestamp to the data structure
     * @param self The timestamp array data structure
     * @param timestamp The timestamp to add
     * @dev O(1) for append, O(n) for maintaining sorted indices (but only shifts indices, not data)
     */
    function add(TimestampArray storage self, uint64 timestamp) internal {
        // O(1) - Append to unsorted array
        self.values.push(timestamp);
        uint256 newIndex = self.values.length - 1;

        // Maintain sorted indices for O(log n) searches
        self.indices.insertSortedIndex(self.values, newIndex);

        // O(1) - Update max if needed
        if (timestamp > self.maxValue) {
            self.maxValue = timestamp;
        }
    }

    /**
     * @notice Returns the maximum timestamp
     * @param self The timestamp array data structure
     * @return The maximum timestamp value, or 0 if empty
     * @dev O(1) operation
     */
    function getLast(TimestampArray storage self) internal view returns (uint64) {
        return self.maxValue;
    }

    /**
     * @notice Finds the largest timestamp less than or equal to the target
     * @param self The timestamp array data structure
     * @param target The target timestamp to search for
     * @return The largest timestamp <= target, or 0 if none exists
     * @dev O(log n) operation using binary search on sorted indices
     */
    function findFloor(TimestampArray storage self, uint64 target) internal view returns (uint64) {
        (uint256 foundIndex, bool found) = self.indices.findFloorIndex(self.values, target);
        return found ? uint64(self.values[foundIndex]) : 0;
    }

    /**
     * @notice Returns the number of timestamps stored
     * @param self The timestamp array data structure
     * @return The count of timestamps
     */
    function length(TimestampArray storage self) internal view returns (uint256) {
        return self.values.length;
    }

    /**
     * @notice Checks if a specific timestamp exists
     * @param self The timestamp array data structure
     * @param timestamp The timestamp to check
     * @return True if the timestamp exists, false otherwise
     * @dev O(n) operation - linear search through values
     */
    function contains(TimestampArray storage self, uint64 timestamp) internal view returns (bool) {
        uint256 len = self.values.length;
        for (uint256 i = 0; i < len; i++) {
            if (self.values[i] == timestamp) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Returns the timestamp at a specific position in the unsorted array
     * @param self The timestamp array data structure
     * @param index The index to query
     * @return The timestamp at the given index
     * @dev O(1) operation. Reverts if index is out of bounds.
     */
    function at(TimestampArray storage self, uint256 index) internal view returns (uint64) {
        return uint64(self.values[index]);
    }

    /**
     * @notice Checks if the data structure is empty
     * @param self The timestamp array data structure
     * @return True if empty, false otherwise
     */
    function isEmpty(TimestampArray storage self) internal view returns (bool) {
        return self.values.length == 0;
    }
}
