// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library SnapshotsLib {
    struct Snapshots {
        Snapshot[] array;
        mapping(uint256 timestap => Snapshot) map;
    }

    struct Snapshot {
        bytes32 value;
        uint256 timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error StaleTimestamp();

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the value of the last snapshot.
     * @param snapshots The array of snapshots to search within.
     * @return The value of the closest snapshot, converted to `int256`.
     */
    function getLastAsInt(Snapshots storage snapshots) internal view returns (int256) {
        return getAsInt(snapshots, block.timestamp);
    }

    /**
     * @notice Retrieves the value of the closest snapshot with a timestamp less than or equal to `since`.
     * @param snapshots The array of snapshots to search within.
     * @param since The timestamp to find the closest snapshot for.
     * @return The value of the closest snapshot, converted to `int256`.
     */
    function getAsInt(Snapshots storage snapshots, uint256 since) internal view returns (int256) {
        return int256(uint256(get(snapshots, since)));
    }

    /**
     * @notice Retrieves the value of the last snapshot.
     * @param snapshots The array of snapshots to search within.
     * @return The value of the closest snapshot.
     */
    function getLast(Snapshots storage snapshots) internal view returns (bytes32) {
        return get(snapshots, block.timestamp);
    }

    /**
     * @notice Retrieves the value of the closest snapshot with a timestamp less than or equal to `since`.
     * @param snapshots The array of snapshots to search within.
     * @param since The timestamp to find the closest snapshot for.
     * @return The value of the closest snapshot.
     */
    function get(Snapshots storage snapshots, uint256 since) internal view returns (bytes32) {
        Snapshot memory entry = snapshots.map[since];
        if (entry.timestamp > 0) return entry.value;

        uint256 length = snapshots.array.length;
        if (length == 0) return 0;

        Snapshot memory last = snapshots.array[snapshots.array.length - 1];
        if (last.timestamp <= since) return last.value;
        if (since < snapshots.array[0].timestamp) return 0;

        uint256 min = 0;
        uint256 max = length - 1;
        while (max > min) {
            uint256 mid = (max + min + 1) / 2; // Midpoint
            if (snapshots.array[mid].timestamp <= since) {
                min = mid; // Narrow down to the upper half
            } else {
                max = mid - 1; // Narrow down to the lower half
            }
        }
        return snapshots.array[min].value; // Return the closest checkpoint value
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Appends a new snapshot with a given `int256` value and the current block timestamp.
     * @param snapshots The array of snapshots to append to.
     * @param value The `int256` value to store in the snapshot.
     */
    function appendAsInt(Snapshots storage snapshots, int256 value) internal {
        appendAsInt(snapshots, value, block.timestamp);
    }

    /**
     * @notice Appends a new snapshot with a given `int256` value and a specific timestamp.
     * @param snapshots The array of snapshots to append to.
     * @param value The `int256` value to store in the snapshot.
     * @param timestamp The timestamp to associate with the snapshot.
     */
    function appendAsInt(Snapshots storage snapshots, int256 value, uint256 timestamp) internal {
        append(snapshots, bytes32(uint256(value)), timestamp);
    }

    /**
     * @notice Appends a new snapshot with a given `bytes32` value and the current block timestamp.
     * @param snapshots The array of snapshots to append to.
     * @param value The `bytes32` value to store in the snapshot.
     */
    function append(Snapshots storage snapshots, bytes32 value) internal {
        append(snapshots, value, block.timestamp);
    }

    /**
     * @notice Appends a new snapshot with a given `bytes32` value and a specific timestamp.
     * @param snapshots The array of snapshots to append to.
     * @param value The `bytes32` value to store in the snapshot.
     * @param timestamp The timestamp to associate with the snapshot.
     */
    function append(Snapshots storage snapshots, bytes32 value, uint256 timestamp) internal {
        Snapshot[] storage array = snapshots.array;
        if (array.length > 0 && timestamp < array[array.length - 1].timestamp) revert StaleTimestamp();

        Snapshot memory entry = Snapshot(value, timestamp);
        snapshots.map[timestamp] = entry;
        snapshots.array.push(entry);
    }
}
