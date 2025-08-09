// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC7540 } from "../interfaces/IERC7540.sol";
import { BaseERC20xDHook } from "../mixins/BaseERC20xDHook.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

/**
 * @title ERC7540Hook
 * @notice A stateless hook that integrates with ERC7540 asynchronous vaults
 * @dev This hook delegates all deposit/redeem operations to the ERC7540 vault without maintaining any state.
 *      On mint (from=0): Deposits assets to vault on behalf of the recipient
 *      On burn (to=0): Redeems shares from vault with the burner as receiver
 */
contract ERC7540Hook is BaseERC20xDHook {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The ERC7540 vault that handles async operations
    IERC7540 public immutable vault;

    /// @notice The underlying asset token accepted by the vault
    address public immutable asset;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositRequested(address indexed user, uint256 assets, uint256 requestId);
    event RedeemRequested(address indexed user, uint256 shares, uint256 requestId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidVault();
    error InvalidAsset();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _token, address _vault) BaseERC20xDHook(_token) {
        if (_vault == address(0)) revert InvalidVault();

        vault = IERC7540(_vault);

        // Get the asset from the vault
        asset = IERC7540(_vault).asset();

        if (asset == address(0)) revert InvalidAsset();

        // Approve vault to spend max assets for deposits
        ERC20(asset).safeApprove(_vault, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                           MODIFIER
    //////////////////////////////////////////////////////////////*/

    modifier onlyToken() {
        if (msg.sender != token) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           HOOK IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles deposits on mint and redeems on burn
     * @dev This is called after the transfer is completed
     * @param from The source address (address(0) for mints)
     * @param to The destination address (address(0) for burns)
     * @param amount The amount of tokens transferred
     */
    function afterTransfer(address from, address to, uint256 amount, bytes memory /* data */ )
        external
        override
        onlyToken
    {
        // Handle mint: deposit assets to vault on behalf of recipient
        if (from == address(0) && to != address(0)) {
            _handleDeposit(to, amount);
        }
        // Handle burn: redeem shares from vault with burner as receiver
        else if (to == address(0) && from != address(0)) {
            _handleRedeem(from, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles deposit when tokens are minted
     * @dev Assumes the hook has received assets to deposit (e.g., through a separate transfer)
     * @param user The user who will own the deposit request
     * @param amount The amount of wrapped tokens minted (used as shares amount)
     */
    function _handleDeposit(address user, uint256 amount) internal {
        // Check if we have enough assets to deposit
        uint256 assets = ERC20(asset).balanceOf(address(this));

        if (assets >= amount) {
            // Request deposit with user as both controller and owner
            // The vault will handle the async processing
            uint256 requestId = vault.requestDeposit(amount, user, user);

            emit DepositRequested(user, amount, requestId);
        }
        // If we don't have assets, the mint happens without deposit
        // This allows for flexible integration patterns
    }

    /**
     * @notice Handles redeem when tokens are burned
     * @param user The user who burned tokens and will receive assets
     * @param shares The amount of shares (wrapped tokens) burned
     */
    function _handleRedeem(address user, uint256 shares) internal {
        // Request redeem with user as both controller and owner
        // The vault will send assets directly to the user when ready
        uint256 requestId = vault.requestRedeem(shares, user, user);

        emit RedeemRequested(user, shares, requestId);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a user has pending deposits
     * @param user The user to check
     * @param requestId The request ID to check
     * @return assets The amount of assets pending
     */
    function pendingDepositRequest(address user, uint256 requestId) external view returns (uint256 assets) {
        return vault.pendingDepositRequest(requestId, user);
    }

    /**
     * @notice Check if a user has claimable deposits
     * @param user The user to check
     * @param requestId The request ID to check
     * @return assets The amount of assets claimable
     */
    function claimableDepositRequest(address user, uint256 requestId) external view returns (uint256 assets) {
        return vault.claimableDepositRequest(requestId, user);
    }

    /**
     * @notice Check if a user has pending redeems
     * @param user The user to check
     * @param requestId The request ID to check
     * @return shares The amount of shares pending
     */
    function pendingRedeemRequest(address user, uint256 requestId) external view returns (uint256 shares) {
        return vault.pendingRedeemRequest(requestId, user);
    }

    /**
     * @notice Check if a user has claimable redeems
     * @param user The user to check
     * @param requestId The request ID to check
     * @return shares The amount of shares claimable
     */
    function claimableRedeemRequest(address user, uint256 requestId) external view returns (uint256 shares) {
        return vault.claimableRedeemRequest(requestId, user);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows depositing assets to this hook for subsequent vault deposits
     * @dev In production, this might be restricted or integrated with the minting process
     * @param amount The amount of assets to deposit
     */
    function depositAssets(uint256 amount) external {
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }
}
