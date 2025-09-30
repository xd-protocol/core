// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../../../src/interfaces/IERC20xDHook.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

/**
 * @title YieldVaultHookMock
 * @notice Mock hook that simulates a yield-bearing vault
 * @dev Supports both ERC20 and native token vaults with configurable yield rates
 */
contract YieldVaultHookMock is IERC20xDHook {
    using SafeTransferLib for ERC20;

    address public immutable wrappedToken;
    address public immutable underlying;
    bool public immutable isNative;

    // Yield configuration
    uint256 public yieldPercentage = 1000; // 10% = 1000 basis points
    uint256 public constant BASIS_POINTS = 10_000;

    // Tracking deposits
    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;

    // Mock vault balance (simulates underlying + yield)
    uint256 public vaultBalance;

    event VaultDeposit(address indexed from, uint256 amount);
    event VaultWithdrawal(address indexed to, uint256 shares, uint256 assets);

    constructor(address _wrappedToken, address _underlying) {
        wrappedToken = _wrappedToken;
        underlying = _underlying;
        isNative = _underlying == address(0);
    }

    /**
     * @notice Set the yield percentage for testing
     * @param _yieldPercentage Yield in basis points (1000 = 10%)
     */
    function setYieldPercentage(uint256 _yieldPercentage) external {
        yieldPercentage = _yieldPercentage;
    }

    /**
     * @notice Simulate yield accrual by increasing vault balance
     */
    function accrueYield() external {
        if (totalDeposits > 0) {
            uint256 yield = (totalDeposits * yieldPercentage) / BASIS_POINTS;
            vaultBalance += yield;
        }
    }

    /**
     * @notice Manually set vault balance for testing
     */
    function setVaultBalance(uint256 _balance) external {
        vaultBalance = _balance;
    }

    // Hook implementations
    function onWrap(address from, address to, uint256 amount, bytes memory hookData)
        external
        payable
        override
        returns (uint256)
    {
        require(msg.sender == wrappedToken, "Only wrapped token can call");

        if (isNative) {
            // For native tokens, we receive them as msg.value
            require(msg.value == amount, "Incorrect native amount");
            vaultBalance += amount;
        } else {
            // For ERC20, pull tokens from wrapped contract using allowance
            ERC20(underlying).safeTransferFrom(wrappedToken, address(this), amount);
            vaultBalance += amount;
        }

        deposits[from] += amount;
        totalDeposits += amount;

        emit VaultDeposit(from, amount);
        return amount; // Return same amount for minting
    }

    function onUnwrap(address from, address to, uint256 shares, bytes memory hookData)
        external
        override
        returns (uint256)
    {
        require(msg.sender == wrappedToken, "Only wrapped token can call");
        require(deposits[from] >= shares, "Insufficient deposits");

        // Calculate assets to return (shares + proportional yield)
        uint256 assets = shares;
        if (totalDeposits > 0 && vaultBalance > totalDeposits) {
            // Add proportional yield
            uint256 totalYield = vaultBalance - totalDeposits;
            uint256 userYield = (totalYield * shares) / totalDeposits;
            assets = shares + userYield;
        }

        // Ensure we don't exceed vault balance
        if (assets > vaultBalance) {
            assets = vaultBalance;
        }

        // Update tracking
        deposits[from] -= shares;
        totalDeposits -= shares;
        vaultBalance -= assets;

        // Transfer assets back to wrapped token contract
        if (isNative) {
            // Transfer native tokens
            (bool success,) = wrappedToken.call{ value: assets }("");
            require(success, "Native transfer failed");
        } else {
            // Transfer ERC20 tokens
            ERC20(underlying).safeTransfer(wrappedToken, assets);
        }

        emit VaultWithdrawal(to, shares, assets);
        return assets; // Return actual amount including yield
    }

    // Empty implementations for other hooks
    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function afterTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address[] memory, address[] memory) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }

    // Receive native tokens
    receive() external payable {
        if (isNative) {
            // Accept native tokens for the vault
        }
    }
}
