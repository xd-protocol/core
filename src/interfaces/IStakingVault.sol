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
     * @notice Provides a quote for depositing an asset.
     * @param asset The asset to deposit.
     * @param amount The amount to deposit.
     * @param gasLimit The gas limit for the operation.
     * @return minAmount The minimum amount accepted.
     * @return fee The fee required.
     */
    function quoteDeposit(address asset, uint256 amount, uint128 gasLimit)
        external
        view
        returns (uint256 minAmount, uint256 fee);

    /**
     * @notice Provides a quote for depositing native currency.
     * @param amount The native amount to deposit.
     * @param gasLimit The gas limit for the operation.
     * @return minAmount The minimum amount accepted.
     * @return fee The fee required.
     */
    function quoteDepositNative(uint256 amount, uint128 gasLimit)
        external
        view
        returns (uint256 minAmount, uint256 fee);

    /**
     * @notice Deposits an idle asset.
     * @param asset The asset address.
     * @param amount The amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for the operation.
     * @return dstAmount The resulting share amount.
     */
    function depositIdle(address asset, uint256 amount, uint256 minAmount, uint128 gasLimit)
        external
        payable
        returns (uint256 dstAmount);

    /**
     * @notice Deposits idle native currency.
     * @param amount The native amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for the operation.
     * @return dstAmount The resulting share amount.
     */
    function depositIdleNative(uint256 amount, uint256 minAmount, uint128 gasLimit)
        external
        payable
        returns (uint256 dstAmount);

    /**
     * @notice Deposits an asset.
     * @param asset The asset to deposit.
     * @param amount The amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for the operation.
     * @param refundTo The address to refund any excess fee.
     * @return dstAmount The resulting share amount.
     */
    function deposit(address asset, uint256 amount, uint256 minAmount, uint128 gasLimit, address refundTo)
        external
        payable
        returns (uint256 dstAmount);

    /**
     * @notice Deposits native currency.
     * @param amount The native amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for the operation.
     * @param refundTo The address to refund any excess fee.
     * @return dstAmount The resulting share amount.
     */
    function depositNative(uint256 amount, uint256 minAmount, uint128 gasLimit, address refundTo)
        external
        payable
        returns (uint256 dstAmount);

    /**
     * @notice Provides a quote for withdrawing an asset.
     * @param asset The asset to withdraw.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     * @param gasLimit The gas limit for the operation.
     * @return fee The fee required.
     */
    function quoteWithdraw(address asset, address to, uint256 amount, uint128 gasLimit)
        external
        view
        returns (uint256 fee);

    /**
     * @notice Provides a quote for withdrawing native currency.
     * @param to The recipient address.
     * @param amount The native amount to withdraw.
     * @param gasLimit The gas limit for the operation.
     * @return fee The fee required.
     */
    function quoteWithdrawNative(address to, uint256 amount, uint128 gasLimit) external view returns (uint256 fee);

    /**
     * @notice Withdraws a specified asset.
     * @param asset The asset to withdraw.
     * @param amount The amount to withdraw.
     * @param data Arbitrary data.
     * @param gasLimit The gas limit for the operation.
     * @param refundTo The address to refund any excess fee.
     */
    function withdraw(address asset, uint256 amount, bytes calldata data, uint128 gasLimit, address refundTo)
        external
        payable;

    /**
     * @notice Withdraws native currency.
     * @param amount The native amount to withdraw.
     * @param data Arbitrary data.
     * @param gasLimit The gas limit for the operation.
     * @param refundTo The address to refund any excess fee.
     */
    function withdrawNative(uint256 amount, bytes calldata data, uint128 gasLimit, address refundTo) external payable;
}
