// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

/**
 * @title CallOrderTrackerMock
 * @notice Mock contract to track the order of hook calls using a shared counter
 */
contract CallOrderTrackerMock {
    uint256 public globalCallCounter;

    function incrementAndGet() external returns (uint256) {
        globalCallCounter++;
        return globalCallCounter;
    }
}
