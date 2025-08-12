// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

/**
 * @title ArrayLib
 * @notice Library providing utility functions for array manipulation and sorting
 * @dev Contains optimized functions for maintaining sorted arrays, particularly useful for
 *      timestamp-based operations in snapshots and time-series data management.
 *      Uses binary insertion sort for efficient insertion while maintaining sort order.
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
}
