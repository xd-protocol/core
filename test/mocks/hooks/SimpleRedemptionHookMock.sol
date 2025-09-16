// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../../../src/interfaces/IERC20xDHook.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

/**
 * @title SimpleRedemptionHookMock
 * @notice Mock hook that tracks redemptions
 */
contract SimpleRedemptionHookMock is IERC20xDHook {
    using SafeTransferLib for ERC20;

    address public immutable wrappedToken;
    address public immutable underlying;

    event Redeemed(address indexed recipient, uint256 amount);

    constructor(address _wrappedToken, address _underlying) {
        wrappedToken = _wrappedToken;
        underlying = _underlying;
    }

    function afterTransfer(address from, address to, uint256 amount, bytes memory) external override {
        if (msg.sender != wrappedToken) return;
        if (to != address(0)) return; // Only process burns

        // Just emit event - underlying already transferred by contract
        emit Redeemed(from, amount);
    }

    // Empty implementations for other hooks
    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address, address) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }

    function onWrap(address, address, uint256 amount, bytes memory) external payable override returns (uint256) {
        return amount;
    }

    function onUnwrap(address from, address, uint256 shares, bytes memory) external override returns (uint256) {
        // Transfer underlying back to wrapped token contract
        ERC20(underlying).safeTransfer(wrappedToken, shares);
        return shares; // No yield
    }
}
