// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library ArrayLib {
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
