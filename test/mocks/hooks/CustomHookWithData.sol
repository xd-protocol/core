// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../../../src/interfaces/IERC20xDHook.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

/**
 * @title CustomHookWithData
 * @notice Mock hook that processes custom data for wrap and unwrap operations
 * @dev Used for testing hookData parameter functionality
 */
contract CustomHookWithData is IERC20xDHook {
    using SafeTransferLib for ERC20;

    struct WrapConfig {
        uint256 multiplier; // e.g., 1000 = 100%, 1100 = 110%
        address recipient; // optional override recipient
        bytes metadata; // arbitrary metadata
    }

    struct UnwrapConfig {
        uint256 feePercent; // e.g., 100 = 1%
        address feeRecipient;
        bool applyBonus;
    }

    // Storage for testing
    mapping(address => WrapConfig) public lastWrapConfigs;
    mapping(address => UnwrapConfig) public lastUnwrapConfigs;
    mapping(address => bytes) public lastWrapMetadata;
    mapping(address => bytes) public lastWrapRawData;
    mapping(address => bytes) public lastUnwrapRawData;

    address public immutable underlying;
    address public immutable wrappedToken;

    event WrapProcessed(address from, address to, uint256 amount, WrapConfig config);
    event UnwrapProcessed(address from, address to, uint256 shares, UnwrapConfig config);

    constructor(address _wrappedToken, address _underlying) {
        wrappedToken = _wrappedToken;
        underlying = _underlying;
    }

    function onWrap(address from, address to, uint256 amount, bytes memory hookData)
        external
        payable
        override
        returns (uint256)
    {
        // Store raw data for verification
        lastWrapRawData[from] = hookData;

        if (hookData.length > 0) {
            WrapConfig memory config = abi.decode(hookData, (WrapConfig));
            lastWrapConfigs[from] = config;
            lastWrapMetadata[from] = config.metadata;

            emit WrapProcessed(from, to, amount, config);

            // Apply multiplier
            uint256 adjustedAmount = (amount * config.multiplier) / 1000;

            // If this is WrappedERC20xD, pull tokens
            if (msg.sender == wrappedToken && underlying != address(0)) {
                ERC20(underlying).safeTransferFrom(wrappedToken, address(this), amount);
            }

            return adjustedAmount;
        }

        // Default behavior
        if (msg.sender == wrappedToken && underlying != address(0)) {
            ERC20(underlying).safeTransferFrom(wrappedToken, address(this), amount);
        }
        return amount;
    }

    function onUnwrap(address from, address to, uint256 shares, bytes memory hookData)
        external
        override
        returns (uint256)
    {
        // Store raw data for verification
        lastUnwrapRawData[from] = hookData;

        if (hookData.length > 0) {
            UnwrapConfig memory config = abi.decode(hookData, (UnwrapConfig));
            lastUnwrapConfigs[from] = config;

            emit UnwrapProcessed(from, to, shares, config);

            uint256 underlyingAmount = shares;

            // Apply bonus if configured
            if (config.applyBonus) {
                underlyingAmount = (shares * 1100) / 1000; // 10% bonus
            }

            // Calculate fee
            if (config.feePercent > 0) {
                uint256 fee = (underlyingAmount * config.feePercent) / 10_000;
                underlyingAmount -= fee;

                // Transfer fee to recipient (if we have the underlying)
                if (config.feeRecipient != address(0) && underlying != address(0)) {
                    ERC20(underlying).safeTransfer(config.feeRecipient, fee);
                }
            }

            // Transfer underlying back to wrapped token contract
            if (underlying != address(0)) {
                ERC20(underlying).safeTransfer(wrappedToken, underlyingAmount);
            } else {
                // Native token - send ETH
                payable(wrappedToken).transfer(underlyingAmount);
            }

            return underlyingAmount;
        }

        // Default behavior
        if (underlying != address(0)) {
            ERC20(underlying).safeTransfer(wrappedToken, shares);
        } else {
            // Native token - send ETH
            payable(wrappedToken).transfer(shares);
        }
        return shares;
    }

    // Other required interface functions
    function afterTransfer(address, address, uint256, bytes memory) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function onMapAccounts(bytes32, address[] memory, address[] memory) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }

    // Helper functions for testing
    function getLastWrapMultiplier(address user) external view returns (uint256) {
        return lastWrapConfigs[user].multiplier;
    }

    function getLastWrapRecipient(address user) external view returns (address) {
        return lastWrapConfigs[user].recipient;
    }

    function getLastUnwrapFeePercent(address user) external view returns (uint256) {
        return lastUnwrapConfigs[user].feePercent;
    }

    function getLastUnwrapFeeRecipient(address user) external view returns (address) {
        return lastUnwrapConfigs[user].feeRecipient;
    }

    function getLastUnwrapBonus(address user) external view returns (bool) {
        return lastUnwrapConfigs[user].applyBonus;
    }
}
