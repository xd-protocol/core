// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../../../src/interfaces/IERC20xDHook.sol";

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

    struct MapAccountsCall {
        bytes32 chainUID;
        address remoteAccount;
        address localAccount;
        uint256 timestamp;
    }

    struct SettleLiquidityCall {
        bytes32 chainUID;
        uint256 timestamp;
        address account;
        int256 liquidity;
    }

    struct SettleTotalLiquidityCall {
        bytes32 chainUID;
        uint256 timestamp;
        int256 totalLiquidity;
    }

    struct SettleDataCall {
        bytes32 chainUID;
        uint256 timestamp;
        bytes32 key;
        bytes value;
    }

    struct WrapCall {
        address from;
        address to;
        uint256 amount;
        uint256 returnedAmount;
        uint256 timestamp;
    }

    struct UnwrapCall {
        address from;
        address to;
        uint256 shares;
        uint256 returnedAmount;
        uint256 timestamp;
    }

    InitiateTransferCall[] public initiateTransferCalls;
    GlobalAvailabilityCall[] public globalAvailabilityCalls;
    TransferCall[] public beforeTransferCalls;
    TransferCall[] public afterTransferCalls;
    MapAccountsCall[] public mapAccountsCalls;
    SettleLiquidityCall[] public settleLiquidityCalls;
    SettleTotalLiquidityCall[] public settleTotalLiquidityCalls;
    SettleDataCall[] public settleDataCalls;
    WrapCall[] public wrapCalls;
    UnwrapCall[] public unwrapCalls;

    bool public shouldRevertOnInitiate;
    bool public shouldRevertOnGlobalAvailability;
    bool public shouldRevertBeforeTransfer;
    bool public shouldRevertAfterTransfer;
    bool public shouldRevertOnMapAccounts;
    bool public shouldRevertOnSettleLiquidity;
    bool public shouldRevertOnSettleTotalLiquidity;
    bool public shouldRevertOnSettleData;
    bool public shouldRevertOnWrap;
    bool public shouldRevertOnUnwrap;

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

    function beforeTransfer(address from, address to, uint256 amount, bytes memory /* data */ ) external override {
        if (shouldRevertBeforeTransfer) {
            revert(revertReason);
        }
        beforeTransferCalls.push(TransferCall({ from: from, to: to, amount: amount, timestamp: block.timestamp }));
    }

    function afterTransfer(address from, address to, uint256 amount, bytes memory /* data */ ) external override {
        if (shouldRevertAfterTransfer) {
            revert(revertReason);
        }
        afterTransferCalls.push(TransferCall({ from: from, to: to, amount: amount, timestamp: block.timestamp }));
    }

    function onMapAccounts(bytes32 chainUID, address remoteAccount, address localAccount) external override {
        if (shouldRevertOnMapAccounts) {
            revert(revertReason);
        }
        mapAccountsCalls.push(
            MapAccountsCall({
                chainUID: chainUID,
                remoteAccount: remoteAccount,
                localAccount: localAccount,
                timestamp: block.timestamp
            })
        );
    }

    function onSettleLiquidity(bytes32 chainUID, uint256 timestamp, address account, int256 liquidity)
        external
        override
    {
        if (shouldRevertOnSettleLiquidity) {
            revert(revertReason);
        }
        settleLiquidityCalls.push(
            SettleLiquidityCall({ chainUID: chainUID, timestamp: timestamp, account: account, liquidity: liquidity })
        );
    }

    function onSettleTotalLiquidity(bytes32 chainUID, uint256 timestamp, int256 totalLiquidity) external override {
        if (shouldRevertOnSettleTotalLiquidity) {
            revert(revertReason);
        }
        settleTotalLiquidityCalls.push(
            SettleTotalLiquidityCall({ chainUID: chainUID, timestamp: timestamp, totalLiquidity: totalLiquidity })
        );
    }

    function onSettleData(bytes32 chainUID, uint256 timestamp, bytes32 key, bytes memory value) external override {
        if (shouldRevertOnSettleData) {
            revert(revertReason);
        }
        settleDataCalls.push(SettleDataCall({ chainUID: chainUID, timestamp: timestamp, key: key, value: value }));
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

    function getMapAccountsCallCount() external view returns (uint256) {
        return mapAccountsCalls.length;
    }

    function getSettleLiquidityCallCount() external view returns (uint256) {
        return settleLiquidityCalls.length;
    }

    function getSettleTotalLiquidityCallCount() external view returns (uint256) {
        return settleTotalLiquidityCalls.length;
    }

    function getSettleDataCallCount() external view returns (uint256) {
        return settleDataCalls.length;
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

    function setShouldRevertOnMapAccounts(bool _shouldRevert) external {
        shouldRevertOnMapAccounts = _shouldRevert;
    }

    function setShouldRevertOnSettleLiquidity(bool _shouldRevert) external {
        shouldRevertOnSettleLiquidity = _shouldRevert;
    }

    function setShouldRevertOnSettleTotalLiquidity(bool _shouldRevert) external {
        shouldRevertOnSettleTotalLiquidity = _shouldRevert;
    }

    function setShouldRevertOnSettleData(bool _shouldRevert) external {
        shouldRevertOnSettleData = _shouldRevert;
    }

    function setRevertReason(string memory _reason) external {
        revertReason = _reason;
    }

    function onWrap(address from, address to, uint256 amount) external payable override returns (uint256) {
        if (shouldRevertOnWrap) {
            revert(revertReason);
        }
        uint256 returnedAmount = amount; // Default: return same amount
        wrapCalls.push(
            WrapCall({ from: from, to: to, amount: amount, returnedAmount: returnedAmount, timestamp: block.timestamp })
        );
        return returnedAmount;
    }

    function onUnwrap(address from, address to, uint256 shares) external override returns (uint256) {
        if (shouldRevertOnUnwrap) {
            revert(revertReason);
        }
        uint256 returnedAmount = shares; // Default: return same amount as shares
        unwrapCalls.push(
            UnwrapCall({ from: from, to: to, shares: shares, returnedAmount: returnedAmount, timestamp: block.timestamp })
        );
        return returnedAmount;
    }

    // Getters for wrap/unwrap call counts
    function getWrapCallCount() external view returns (uint256) {
        return wrapCalls.length;
    }

    function getUnwrapCallCount() external view returns (uint256) {
        return unwrapCalls.length;
    }

    // Setters for wrap/unwrap revert flags
    function setShouldRevertOnWrap(bool _shouldRevert) external {
        shouldRevertOnWrap = _shouldRevert;
    }

    function setShouldRevertOnUnwrap(bool _shouldRevert) external {
        shouldRevertOnUnwrap = _shouldRevert;
    }
}
