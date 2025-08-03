// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";

contract HookMock is IERC20xDHook {
    struct InitiateTransferCall {
        address from;
        address to;
        uint256 amount;
        bytes callData;
        uint256 value;
        bytes data;
        uint256 timestamp;
    }

    struct GlobalAvailabilityCall {
        address account;
        int256 globalAvailability;
        uint256 timestamp;
    }

    struct TransferCall {
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
    }

    InitiateTransferCall[] public initiateTransferCalls;
    GlobalAvailabilityCall[] public globalAvailabilityCalls;
    TransferCall[] public beforeTransferCalls;
    TransferCall[] public afterTransferCalls;

    bool public shouldRevertOnInitiate;
    bool public shouldRevertOnGlobalAvailability;
    bool public shouldRevertBeforeTransfer;
    bool public shouldRevertAfterTransfer;

    string public revertReason = "HookMock: Intentional revert";

    function onInitiateTransfer(
        address from,
        address to,
        uint256 amount,
        bytes memory callData,
        uint256 value,
        bytes memory data
    ) external override {
        if (shouldRevertOnInitiate) {
            revert(revertReason);
        }
        initiateTransferCalls.push(
            InitiateTransferCall({
                from: from,
                to: to,
                amount: amount,
                callData: callData,
                value: value,
                data: data,
                timestamp: block.timestamp
            })
        );
    }

    function onReadGlobalAvailability(address account, int256 globalAvailability) external override {
        if (shouldRevertOnGlobalAvailability) {
            revert(revertReason);
        }
        globalAvailabilityCalls.push(
            GlobalAvailabilityCall({
                account: account,
                globalAvailability: globalAvailability,
                timestamp: block.timestamp
            })
        );
    }

    function beforeTransfer(address from, address to, uint256 amount) external override {
        if (shouldRevertBeforeTransfer) {
            revert(revertReason);
        }
        beforeTransferCalls.push(TransferCall({ from: from, to: to, amount: amount, timestamp: block.timestamp }));
    }

    function afterTransfer(address from, address to, uint256 amount) external override {
        if (shouldRevertAfterTransfer) {
            revert(revertReason);
        }
        afterTransferCalls.push(TransferCall({ from: from, to: to, amount: amount, timestamp: block.timestamp }));
    }

    // Getters for call counts
    function getInitiateTransferCallCount() external view returns (uint256) {
        return initiateTransferCalls.length;
    }

    function getGlobalAvailabilityCallCount() external view returns (uint256) {
        return globalAvailabilityCalls.length;
    }

    function getBeforeTransferCallCount() external view returns (uint256) {
        return beforeTransferCalls.length;
    }

    function getAfterTransferCallCount() external view returns (uint256) {
        return afterTransferCalls.length;
    }

    // Setters for revert flags
    function setShouldRevertOnInitiate(bool _shouldRevert) external {
        shouldRevertOnInitiate = _shouldRevert;
    }

    function setShouldRevertOnGlobalAvailability(bool _shouldRevert) external {
        shouldRevertOnGlobalAvailability = _shouldRevert;
    }

    function setShouldRevertBeforeTransfer(bool _shouldRevert) external {
        shouldRevertBeforeTransfer = _shouldRevert;
    }

    function setShouldRevertAfterTransfer(bool _shouldRevert) external {
        shouldRevertAfterTransfer = _shouldRevert;
    }

    function setRevertReason(string memory _reason) external {
        revertReason = _reason;
    }
}
