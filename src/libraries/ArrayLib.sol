// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

/**
 * @title ArrayLib
 * @notice Library providing utility functions for array manipulation and sorting
 * @dev Contains optimized functions for maintaining sorted arrays, particularly useful for
 *      timestamp-based operations in snapshots and time-series data management.
 *      Supports dual array pattern: unsorted data array with sorted index array for O(1) writes and O(log n) reads.
 */
library ArrayLib {
    function last(uint256[] storage array) internal view returns (uint256) {
        uint256 length = array.length;
        if (length == 0) return 0;
        return array[length - 1];
    }

    /**
     * @notice Finds the largest element less than or equal to a given timestamp
     * @param arr The sorted array to search in (must be sorted in ascending order)
     * @param timestamp The timestamp to find
     * @return value The largest element <= timestamp, or 0 if none exists
     * @dev Uses binary search algorithm identical to SnapshotsLib.get() for consistency.
     *      Returns 0 when no valid element is found (array empty or all elements > timestamp).
     */
    function findFloor(uint256[] storage arr, uint256 timestamp) internal view returns (uint256 value) {
        uint256 length = arr.length;
        if (length == 0) return 0;

        uint256 lastTimestamp = arr[length - 1];
        if (lastTimestamp <= timestamp) return lastTimestamp;
        if (timestamp < arr[0]) return 0;

        uint256 min = 0;
        uint256 max = length - 1;
        while (max > min) {
            uint256 mid = (max + min + 1) / 2;
            if (arr[mid] <= timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return arr[min];
    }

    /**
     * @notice Inserts an index into a sorted index array based on the value at that index in the values array
     * @param indices The sorted array of indices to insert into
     * @param values The array of values that indices point to
     * @param newIndex The index to insert (pointing to values[newIndex])
     * @dev Maintains sorted order of indices based on comparing values[indices[i]].
     *      This enables O(1) append to values array while maintaining O(log n) search capability.
     */
    function insertSortedIndex(uint256[] storage indices, uint256[] storage values, uint256 newIndex) internal {
        uint256 newValue = values[newIndex];
        uint256 length = indices.length;

        // Empty array or larger than all elements - just push
        if (length == 0) {
            indices.push(newIndex);
            return;
        }

        // Check if it should go at the end (common case for chronological data)
        if (newValue >= values[indices[length - 1]]) {
            indices.push(newIndex);
            return;
        }

        // Binary search to find insertion point
        uint256 left = 0;
        uint256 right = length;
        while (left < right) {
            uint256 mid = (left + right) / 2;
            if (values[indices[mid]] < newValue) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        // Insert at the found position
        indices.push(0); // Extend array
        // Shift indices to the right
        for (uint256 i = length; i > left; i--) {
            indices[i] = indices[i - 1];
        }
        indices[left] = newIndex;
    }

    /**
     * @notice Finds the index of the largest value less than or equal to target using sorted indices
     * @param indices The sorted array of indices
     * @param values The array of values that indices point to
     * @param target The target value to search for
     * @return foundIndex The index in the values array of the largest value <= target
     * @return found Whether a valid value was found
     * @dev Uses binary search on the indices array, comparing values[indices[i]] with target.
     *      Returns (0, false) if no valid element is found.
     */
    function findFloorIndex(uint256[] storage indices, uint256[] storage values, uint256 target)
        internal
        view
        returns (uint256 foundIndex, bool found)
    {
        uint256 length = indices.length;
        if (length == 0) return (0, false);

        // Check last element first (optimization for recent queries)
        uint256 lastIndex = indices[length - 1];
        if (values[lastIndex] <= target) {
            return (lastIndex, true);
        }

        // Check first element
        uint256 firstIndex = indices[0];
        if (target < values[firstIndex]) {
            return (0, false);
        }

        // Binary search
        uint256 left = 0;
        uint256 right = length - 1;
        while (left < right) {
            uint256 mid = (left + right + 1) / 2;
            if (values[indices[mid]] <= target) {
                left = mid;
            } else {
                right = mid - 1;
            }
        }

        return (indices[left], true);
    }
}
