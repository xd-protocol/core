// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../../../src/interfaces/IERC20xDHook.sol";

/**
 * @title FailingRedemptionHookMock
 * @notice Mock hook that fails during redemption operations
 */
contract FailingRedemptionHookMock is IERC20xDHook {
    error RedemptionFailed();

    function afterTransfer(address, address to, uint256, bytes memory) external pure override {
        if (to == address(0)) revert RedemptionFailed();
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address, address) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }

    function onWrap(address, address, uint256, bytes memory) external payable override returns (uint256) {
        revert("Wrap disabled");
    }

    function onUnwrap(address, address, uint256, bytes memory) external pure override returns (uint256) {
        revert("Redemption disabled");
    }
}
