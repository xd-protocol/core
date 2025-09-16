// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../../../src/interfaces/IERC20xDHook.sol";
import { CallOrderTrackerMock } from "../CallOrderTrackerMock.sol";

/**
 * @title OrderTrackingHookMock
 * @notice Mock hook that tracks the order of hook calls
 */
contract OrderTrackingHookMock is IERC20xDHook {
    CallOrderTrackerMock public tracker;
    uint256 public beforeTransferCallOrder;
    uint256 public afterTransferCallOrder;
    uint256 public onInitiateTransferCallOrder;
    uint256 public onReadGlobalAvailabilityCallOrder;
    uint256 public onMapAccountsCallOrder;
    uint256 public onSettleLiquidityCallOrder;
    uint256 public onSettleTotalLiquidityCallOrder;
    uint256 public onSettleDataCallOrder;
    uint256 public onWrapCallOrder;
    uint256 public onUnwrapCallOrder;

    // Track last call details
    address public lastFrom;
    address public lastTo;
    uint256 public lastAmount;

    constructor(CallOrderTrackerMock _tracker) {
        tracker = _tracker;
    }

    function beforeTransfer(address from, address to, uint256 amount, bytes memory) external override {
        beforeTransferCallOrder = tracker.incrementAndGet();
        lastFrom = from;
        lastTo = to;
        lastAmount = amount;
    }

    function afterTransfer(address from, address to, uint256 amount, bytes memory) external override {
        afterTransferCallOrder = tracker.incrementAndGet();
        lastFrom = from;
        lastTo = to;
        lastAmount = amount;
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override {
        onInitiateTransferCallOrder = tracker.incrementAndGet();
    }

    function onReadGlobalAvailability(address, int256) external override {
        onReadGlobalAvailabilityCallOrder = tracker.incrementAndGet();
    }

    function onMapAccounts(bytes32, address, address) external override {
        onMapAccountsCallOrder = tracker.incrementAndGet();
    }

    function onSettleLiquidity(bytes32, uint256, address, int256) external override {
        onSettleLiquidityCallOrder = tracker.incrementAndGet();
    }

    function onSettleTotalLiquidity(bytes32, uint256, int256) external override {
        onSettleTotalLiquidityCallOrder = tracker.incrementAndGet();
    }

    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override {
        onSettleDataCallOrder = tracker.incrementAndGet();
    }

    function onWrap(address from, address to, uint256 amount, bytes memory hookData)
        external
        payable
        override
        returns (uint256)
    {
        onWrapCallOrder = tracker.incrementAndGet();
        lastFrom = from;
        lastTo = to;
        lastAmount = amount;
        return amount; // No modification
    }

    function onUnwrap(address from, address to, uint256 shares, bytes memory hookData)
        external
        override
        returns (uint256)
    {
        onUnwrapCallOrder = tracker.incrementAndGet();
        lastFrom = from;
        lastTo = to;
        lastAmount = shares;
        return shares; // No yield
    }
}
