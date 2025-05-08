// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStakingVaultCallbacks {
    /**
     * @notice Called when a token withdrawal is performed.
     * @param asset The address of the asset withdrawn.
     * @param amount The amount withdrawn.
     * @param data Arbitrary data.
     */
    function onWithdraw(address asset, uint256 amount, bytes calldata data) external;
}

interface IStakingVaultNativeCallbacks {
    /**
     * @notice Called when a native currency withdrawal is performed.
     * @param data Arbitrary data.
     */
    function onWithdrawNative(bytes calldata data) external payable;
}

interface IStakingVault {
    event Stake(address indexed asset, uint256 amount);
    event Unstake(address indexed asset, uint256 amount);
    event Deposit(address indexed asset, uint256 amount, uint256 shares);
    event Withdraw(address indexed asset, uint256 amount);

    /**
     * @notice Deposits an asset.
     * @param asset The asset to deposit.
     * @param to The recipient.
     * @param amount The amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param options Extra options.
     * @return dstAmount The resulting share amount.
     */
    function deposit(address asset, address to, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        returns (uint256 dstAmount);

    /**
     * @notice Deposits native currency.
     * @param to The recipient.
     * @param amount The native amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param options Extra options.
     * @return dstAmount The resulting share amount.
     */
    function depositNative(address to, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        returns (uint256 dstAmount);

    /**
     * @notice Withdraws tokens from the vault.
     * @dev Checks balance and processes local or cross-chain withdrawals.
     * @param to The recipient.
     * @param asset The asset to withdraw.
     * @param amount The amount to withdraw.
     * @param options Extra options.
     */
    function withdraw(
        address asset,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes calldata incomingOptions,
        bytes calldata options
    ) external payable;

    /**
     * @notice Withdraws native currency from the vault.
     * @dev Checks balance and processes local or cross-chain withdrawals.
     * @param to The recipient.
     * @param amount The native amount to withdraw.
     * @param options Extra options.
     */
    function withdrawNative(
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes calldata incomingOptions,
        bytes calldata options
    ) external payable;
}
