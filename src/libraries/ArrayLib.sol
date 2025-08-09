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
    /**
     * @notice Inserts a timestamp into a sorted array while maintaining sort order
     * @param arr The storage array to insert into (must be sorted in ascending order)
     * @param timestamp The timestamp to insert
     * @dev Uses binary insertion sort for efficiency. Handles edge cases:
     *      - Empty array: simply pushes the timestamp
     *      - Timestamp >= last element: pushes to end
     *      - Otherwise: shifts elements and inserts at correct position
     */
    function insertSorted(uint256[] storage arr, uint256 timestamp) internal {
        uint256 len = arr.length;

        if (len == 0) {
            arr.push(timestamp);
            return;
        }

        if (arr[len - 1] <= timestamp) {
            arr.push(timestamp);
            return;
        }

        arr.push(arr[len - 1]);

        uint256 i = len;
        while (i > 0 && arr[i - 1] > timestamp) {
            arr[i] = arr[i - 1];
            unchecked {
                i--;
            }
        }

        arr[i] = timestamp;
    }
}
