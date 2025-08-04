// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../interfaces/IERC20xDHook.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { AddressLib } from "../libraries/AddressLib.sol";

/**
 * @title VaultRedemptionHook
 * @notice A hook that handles redemption of underlying tokens during unwrap operations
 * @dev This hook demonstrates how to implement vault-like functionality using the hook pattern.
 *      It listens to afterTransfer events and releases underlying tokens when burning wrapped tokens.
 */
contract VaultRedemptionHook is IERC20xDHook {
    using SafeTransferLib for ERC20;
    using AddressLib for address;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The wrapped token contract this hook is attached to
    address public immutable wrappedToken;

    /// @notice The underlying token that gets redeemed
    address public immutable underlying;

    /// @notice Mapping of pending cross-chain redemptions
    mapping(bytes32 => PendingRedemption) public pendingRedemptions;

    struct PendingRedemption {
        address recipient;
        uint256 amount;
        uint32 eid;
        bool fulfilled;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RedemptionInitiated(address indexed recipient, uint256 amount, bool isLocal);
    event RedemptionFulfilled(address indexed recipient, uint256 amount);
    event CrossChainRedemptionInitiated(address indexed recipient, uint256 amount, uint32 eid);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyWrappedToken();
    error InsufficientBalance();
    error InvalidRecipient();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _wrappedToken, address _underlying) {
        wrappedToken = _wrappedToken;
        underlying = _underlying;
    }

    /*//////////////////////////////////////////////////////////////
                           MODIFIER
    //////////////////////////////////////////////////////////////*/

    modifier onlyWrappedToken() {
        if (msg.sender != wrappedToken) revert OnlyWrappedToken();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           HOOK IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    function onInitiateTransfer(
        address from,
        address to,
        uint256 amount,
        bytes memory callData,
        uint256 value,
        bytes memory data
    ) external override onlyWrappedToken {
        // Not used for redemption logic
    }

    function onReadGlobalAvailability(address account, int256 globalAvailability) external override onlyWrappedToken {
        // Not used for redemption logic
    }

    function beforeTransfer(address from, address to, uint256 amount, bytes memory data)
        external
        override
        onlyWrappedToken
    {
        // Could be used to prepare for redemption, but not needed in this example
    }

    /**
     * @notice Handles redemption after tokens are burned
     * @dev This is called after the wrapped tokens are burned (transferred to address(0))
     * @param from The address burning the tokens
     * @param to Should be address(0) for burns
     * @param amount The amount of tokens burned
     * @param data Contains LayerZero parameters and potentially the recipient address
     */
    function afterTransfer(address from, address to, uint256 amount, bytes memory data)
        external
        override
        onlyWrappedToken
    {
        // Only process burns (unwrap operations)
        if (to != address(0)) return;

        // Extract recipient from callData that was passed during unwrap
        // The unwrap function encodes the recipient address in callData
        address recipient = from; // Default to sender if no recipient specified

        // In a real implementation, you would decode the recipient from pending transfer data
        // For this example, we'll check if the underlying is available locally

        if (_isUnderlyingLocal()) {
            _redeemLocal(recipient, amount);
        } else {
            _initiateCrossChainRedemption(recipient, amount, data);
        }
    }

    function onMapAccounts(uint32 eid, address remoteAccount, address localAccount) external override {
        // Not used for redemption logic
    }

    function onSettleLiquidity(uint32 eid, uint256 timestamp, address account, int256 liquidity) external override {
        // Not used for redemption logic
    }

    function onSettleTotalLiquidity(uint32 eid, uint256 timestamp, int256 totalLiquidity) external override {
        // Not used for redemption logic
    }

    function onSettleData(uint32 eid, uint256 timestamp, bytes32 key, bytes memory value) external override {
        // Not used for redemption logic
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if underlying tokens are available locally
     * @return True if underlying tokens can be redeemed on this chain
     */
    function _isUnderlyingLocal() internal view returns (bool) {
        // For native tokens
        if (underlying == address(0)) {
            return address(this).balance >= 0;
        }
        // For ERC20 tokens
        return ERC20(underlying).balanceOf(address(this)) > 0;
    }

    /**
     * @notice Redeems underlying tokens locally
     * @param recipient The address to receive the underlying tokens
     * @param amount The amount to redeem
     */
    function _redeemLocal(address recipient, uint256 amount) internal {
        if (recipient == address(0)) revert InvalidRecipient();

        if (underlying == address(0)) {
            // Redeem native tokens
            if (address(this).balance < amount) revert InsufficientBalance();
            recipient.transferNative(amount);
        } else {
            // Redeem ERC20 tokens
            if (ERC20(underlying).balanceOf(address(this)) < amount) revert InsufficientBalance();
            ERC20(underlying).safeTransfer(recipient, amount);
        }

        emit RedemptionFulfilled(recipient, amount);
    }

    /**
     * @notice Initiates cross-chain redemption when underlying is on another chain
     * @param recipient The address to receive the underlying tokens
     * @param amount The amount to redeem
     */
    function _initiateCrossChainRedemption(address recipient, uint256 amount, bytes memory /* data */ ) internal {
        // In a real implementation, this would:
        // 1. Decode LayerZero parameters from data
        // 2. Send a cross-chain message to the chain holding the underlying
        // 3. Track the pending redemption

        // For this example, we'll just emit an event
        emit CrossChainRedemptionInitiated(recipient, amount, 0);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows depositing underlying tokens for redemption
     * @dev In production, this would be restricted and integrated with vault logic
     */
    function depositUnderlying() external payable {
        // Accept native tokens
    }

    /**
     * @notice Allows depositing ERC20 underlying tokens
     * @param amount The amount to deposit
     */
    function depositUnderlyingERC20(uint256 amount) external {
        if (underlying != address(0)) {
            ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        }
    }
}
