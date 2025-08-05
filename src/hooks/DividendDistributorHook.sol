// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xDHook } from "../mixins/BaseERC20xDHook.sol";
import { IBaseERC20xD } from "../interfaces/IBaseERC20xD.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DividendDistributorHook
 * @notice A hook that distributes dividends to ERC20xD token holders (EOAs only)
 * @dev Uses a cumulative dividend per share model to track and distribute rewards
 *
 *      Key mechanics:
 *      - Only EOAs (not contracts) can receive dividends
 *      - Tracks balance changes via onSettleLiquidity hook
 *      - Receives dividend deposits when tokens are transferred to this contract
 *      - Distributes dividends using ERC20xD cross-chain transfers
 *      - All token movements use global availability checks
 *
 *      The contract maintains:
 *      - Total shares (sum of all EOA balances)
 *      - Cumulative dividends per share (scaled by PRECISION)
 *      - User checkpoints for claimed dividends
 *      - Unclaimed dividend tracking per user
 */
contract DividendDistributorHook is BaseERC20xDHook, Ownable {
    using AddressLib for address;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Precision factor for dividend calculations (1e18)
    uint256 public constant PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The ERC20xD token used for dividend distributions
    IBaseERC20xD public immutable dividendToken;

    /// @notice Total amount of shares (token supply held by EOAs)
    uint256 public totalShares;

    /// @notice Cumulative dividends per share, scaled by PRECISION
    uint256 public cumulativeDividendsPerShare;

    /// @notice User's last claimed dividend checkpoint
    mapping(address => uint256) public userDividendCheckpoints;

    /// @notice Unclaimed dividends for each user
    mapping(address => uint256) public unclaimedDividends;

    /// @notice User's balance at last update (only EOAs)
    mapping(address => uint256) public userBalances;

    /// @notice Total dividends distributed
    uint256 public totalDividendsDistributed;

    /// @notice Total dividends claimed
    uint256 public totalDividendsClaimed;

    /// @notice Last known balance of dividend tokens
    uint256 private lastDividendBalance;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DividendDeposited(uint256 amount, uint256 newCumulativePerShare);
    event DividendClaimed(address indexed user, uint256 amount);
    event SharesUpdated(address indexed user, uint256 oldShares, uint256 newShares, bool isEOA);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidDividendToken();
    error NoDividends();
    error NoShares();
    error TransferFailed();
    error Unauthorized();
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyToken() {
        if (msg.sender != token) revert Forbidden();
        _;
    }

    modifier onlyEOA() {
        if (msg.sender.isContract()) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new DividendDistributorHook
     * @param _token The ERC20xD token to attach to
     * @param _dividendToken The ERC20xD token to distribute as dividends
     * @param _owner The owner of this contract
     */
    constructor(address _token, address _dividendToken, address _owner) BaseERC20xDHook(_token) Ownable(_owner) {
        if (_dividendToken == address(0)) revert InvalidDividendToken();

        dividendToken = IBaseERC20xD(_dividendToken);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the pending (claimable) dividends for a user
     * @param user The user to check
     * @return The amount of pending dividends
     */
    function pendingDividends(address user) external view returns (uint256) {
        uint256 shares = userBalances[user];
        if (shares == 0) return unclaimedDividends[user];

        uint256 dividendsDelta = cumulativeDividendsPerShare - userDividendCheckpoints[user];
        uint256 pending = (shares * dividendsDelta) / PRECISION;

        return unclaimedDividends[user] + pending;
    }

    /**
     * @notice Quotes the fee required to claim dividends
     * @return fee The LayerZero fee required for claiming
     */
    function quoteClaim(uint128 gasLimit) external view returns (uint256 fee) {
        return dividendToken.quoteTransfer(address(this), gasLimit);
    }

    /**
     * @notice Returns user-specific dividend information
     * @param user The user to query
     * @return shares User's share balance (0 for contracts)
     * @return checkpoint User's last claimed checkpoint
     * @return unclaimed Unclaimed dividends
     * @return pending Total pending dividends (including unclaimed)
     * @return isEOA Whether the user is an EOA
     */
    function getUserDividendInfo(address user)
        external
        view
        returns (uint256 shares, uint256 checkpoint, uint256 unclaimed, uint256 pending, bool isEOA)
    {
        shares = userBalances[user];
        checkpoint = userDividendCheckpoints[user];
        unclaimed = unclaimedDividends[user];
        isEOA = !user.isContract();

        // Calculate pending
        if (shares > 0 && checkpoint < cumulativeDividendsPerShare) {
            uint256 dividendsDelta = cumulativeDividendsPerShare - checkpoint;
            pending = unclaimed + (shares * dividendsDelta) / PRECISION;
        } else {
            pending = unclaimed;
        }
    }

    /**
     * @notice Returns the current dividend token balance held by this contract
     * @return The balance of dividend tokens
     */
    function getDividendBalance() external view returns (uint256) {
        return dividendToken.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency withdraw of dividend tokens
     * @param to The recipient address
     * @param amount The amount to withdraw
     * @dev Only callable by owner in case of emergency
     */
    function emergencyWithdraw(address to, uint256 amount, bytes memory data) external payable onlyOwner {
        if (to == address(0)) revert InvalidToken();

        // Update last balance to prevent double distribution
        lastDividendBalance = dividendToken.balanceOf(address(this)) - amount;

        // Transfer using ERC20xD
        dividendToken.transfer{ value: msg.value }(to, amount, data);

        emit EmergencyWithdraw(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                      LOGIC (MUTABLE FUNCTIONS)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits dividend tokens to be distributed to shareholders
     * @dev This function is called during the compose phase of a cross-chain transfer.
     *      The dividend token contract calls this function and has set allowance
     *      for this hook to pull tokens from it.
     * @param amount The amount of dividend tokens to deposit
     */
    function depositDividends(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        // During compose, msg.sender is the dividend token contract
        // and it has set allowance for this contract to pull tokens
        bool success = IERC20(msg.sender).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        // Distribute the dividends
        _distributeDividends();
    }

    /**
     * @notice Claims accumulated dividends for the caller
     * @dev Requires msg.value to cover cross-chain transfer fees
     * @return amount The amount of dividends claimed
     */
    function claimDividends(bytes memory data) external payable onlyEOA returns (uint256 amount) {
        amount = _updateAndGetPendingDividends(msg.sender);

        if (amount == 0) revert NoDividends();

        // Reset unclaimed dividends
        unclaimedDividends[msg.sender] = 0;

        // Update checkpoint
        userDividendCheckpoints[msg.sender] = cumulativeDividendsPerShare;

        // Update total claimed
        totalDividendsClaimed += amount;

        // Update lastDividendBalance to account for the claim
        lastDividendBalance -= amount;

        // Transfer dividends using ERC20xD transfer with global availability checks
        dividendToken.transfer{ value: msg.value }(msg.sender, amount, data);

        emit DividendClaimed(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates dividend distribution when new tokens are received
     * @dev Called internally when dividend tokens are transferred to this contract
     */
    function _distributeDividends() internal {
        uint256 currentBalance = dividendToken.balanceOf(address(this));

        if (currentBalance <= lastDividendBalance) return;
        if (totalShares == 0) {
            // Update balance but don't distribute if no shares
            lastDividendBalance = currentBalance;
            return;
        }

        uint256 newDividends = currentBalance - lastDividendBalance;
        lastDividendBalance = currentBalance;

        // Update cumulative dividends per share
        cumulativeDividendsPerShare += (newDividends * PRECISION) / totalShares;
        totalDividendsDistributed += newDividends;

        emit DividendDeposited(newDividends, cumulativeDividendsPerShare);
    }

    /**
     * @notice Updates user's pending dividends and returns the total
     * @param user The user to update
     * @return The total pending dividends
     */
    function _updateAndGetPendingDividends(address user) internal returns (uint256) {
        uint256 shares = userBalances[user];
        if (shares == 0) return unclaimedDividends[user];

        uint256 checkpoint = userDividendCheckpoints[user];
        if (checkpoint < cumulativeDividendsPerShare) {
            uint256 dividendsDelta = cumulativeDividendsPerShare - checkpoint;
            uint256 pending = (shares * dividendsDelta) / PRECISION;
            unclaimedDividends[user] += pending;
        }

        return unclaimedDividends[user];
    }

    /**
     * @notice Updates shares for a user (only EOAs can have shares)
     * @param user The user to update
     * @param newBalance The new balance (shares)
     */
    function _updateShares(address user, uint256 newBalance) internal {
        // Only EOAs can have shares
        bool isEOA = !user.isContract();
        uint256 effectiveBalance = isEOA ? newBalance : 0;

        uint256 oldBalance = userBalances[user];
        if (oldBalance == effectiveBalance) return;

        // Update pending dividends before changing shares
        if (oldBalance > 0) {
            _updateAndGetPendingDividends(user);
        }

        // Update total shares
        totalShares = totalShares + effectiveBalance - oldBalance;

        // Update user balance
        userBalances[user] = effectiveBalance;

        // Update checkpoint for new shareholders
        if (oldBalance == 0 && effectiveBalance > 0) {
            userDividendCheckpoints[user] = cumulativeDividendsPerShare;
        }

        emit SharesUpdated(user, oldBalance, effectiveBalance, isEOA);
    }

    /*//////////////////////////////////////////////////////////////
                           HOOK IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles updates after transfers
     * @dev Called after every transfer on the main token
     * @param from The sender (address(0) for mints)
     * @param to The recipient (address(0) for burns)
     */
    function afterTransfer(address from, address to, uint256, bytes memory) external override onlyToken {
        // Update shares for both sender and recipient based on their new local balances
        if (from != address(0)) {
            // For sender, get their new local balance
            int256 localBalance = IBaseERC20xD(token).localBalanceOf(from);
            uint256 newBalance = localBalance > 0 ? uint256(localBalance) : 0;
            _updateShares(from, newBalance);
        }

        if (to != address(0) && to != from) {
            // For recipient, get their new local balance
            int256 localBalance = IBaseERC20xD(token).localBalanceOf(to);
            uint256 newBalance = localBalance > 0 ? uint256(localBalance) : 0;
            _updateShares(to, newBalance);
        }
    }
}
