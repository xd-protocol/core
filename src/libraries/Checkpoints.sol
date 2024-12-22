// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library Checkpoints {
    struct Checkpoint {
        uint256 fromBlock;
        int256 value;
    }

    function getValueAt(Checkpoint[] storage checkpoints, uint256 _block) internal view returns (int256) {
        if (checkpoints.length == 0) return 0;

        Checkpoint memory latest = checkpoints[checkpoints.length - 1];
        if (_block >= latest.fromBlock) {
            return latest.value;
        }
        if (_block < checkpoints[0].fromBlock) {
            return 0;
        }

        uint256 min;
        uint256 max = checkpoints.length - 1;
        while (max > min) {
            uint256 mid = (max + min + 1) / 2;
            if (checkpoints[mid].fromBlock <= _block) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return checkpoints[min].value;
    }

    function updateValueAtNow(Checkpoint[] storage checkpoints, int256 value) internal {
        Checkpoint storage latest = checkpoints[checkpoints.length - 1];
        if ((checkpoints.length == 0) || (latest.fromBlock < block.number)) {
            checkpoints.push(Checkpoint({ fromBlock: block.number, value: value }));
        } else {
            latest.value = value;
        }
    }
}
