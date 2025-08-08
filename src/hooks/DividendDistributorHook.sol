// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xDHook } from "../mixins/BaseERC20xDHook.sol";
import { IBaseERC20xD } from "../interfaces/IBaseERC20xD.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { IGateway } from "../interfaces/IGateway.sol";
import { IGatewayApp } from "../interfaces/IGatewayApp.sol";

/**
 * @title DividendDistributorHook
 * @notice A hook that distributes dividends to ERC20xD token holders
 * @dev Uses a cumulative dividend per share model to track and distribute rewards
 *
 *      Key mechanics:
 *      - Only registered accounts can receive dividends
 *      - Tracks balance changes via onSettleLiquidity hook
 *      - Receives dividend deposits when tokens are transferred to this contract
 *      - Distributes dividends using ERC20xD cross-chain transfers
 *      - All token movements use global availability checks
 *      - Implements cross-chain dividend aggregation using LayerZero read protocol
 *
 *      The contract maintains:
 *      - Total shares (sum of all registered accounts' balances)
 *      - Cumulative dividends per share (scaled by PRECISION)
 *      - User checkpoints for claimed dividends
 *      - Unclaimed dividend tracking per user
 *      - Cross-chain dividend queries
 */
contract DividendDistributorHook is BaseERC20xDHook, Ownable, IGatewayApp {
    using AddressLib for address;
    using BytesLib for bytes;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

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

    /// @notice Total amount of shares (token supply held by registered accounts)
    uint256 public totalSupply;

    /// @notice User's balance at last update
    mapping(address => uint256) public balanceOf;

    /// @notice Cumulative dividends per share, scaled by PRECISION
    uint256 public cumulativeDividendsPerShare;

    /// @notice Tracks those who are registered for dividends.
    mapping(address => bool) public isRegistered;

    /// @notice User's last claimed dividend checkpoint
    mapping(address => uint256) public userDividendCheckpoints;

    /// @notice Unclaimed dividends for each user
    mapping(address => uint256) public unclaimedDividends;

    /// @notice Total dividends distributed
    uint256 public totalDividendsDistributed;

    /// @notice Total dividends claimed
    uint256 public totalDividendsClaimed;

    /// @notice Last known balance of dividend tokens
    uint256 private lastDividendBalance;

    /// @notice Gateway contract for cross-chain reads
    address public gateway;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterForDividends(address indexed user);
    event DividendDeposited(uint256 amount, uint256 newCumulativePerShare);
    event DividendClaimed(address indexed user, uint256 amount);
    event SharesUpdated(address indexed user, uint256 oldShares, uint256 newShares, bool registered);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    event PeerSet(uint32 eid, bytes32 peer);
    event GatewayUpdated(address gateway);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidDividendToken();
    error NoDividends();
    error InsufficientDividends();
    error TransferFailed();
    error AlreadyRegistered();
    error InvalidSignature();
    error InvalidAmount();
    error InvalidGateway();
    error InvalidRequests();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyToken() {
        if (msg.sender != token) revert Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new DividendDistributorHook
     * @param _token The ERC20xD token to attach to
     * @param _dividendToken The ERC20xD token to distribute as dividends
     * @param _gateway The gateway contract for cross-chain reads
     * @param _owner The owner of this contract
     */
    constructor(address _token, address _dividendToken, address _gateway, address _owner)
        BaseERC20xDHook(_token)
        Ownable(_owner)
    {
        if (_dividendToken == address(0)) revert InvalidDividendToken();
        if (_gateway == address(0)) revert InvalidGateway();

        dividendToken = IBaseERC20xD(_dividendToken);
        gateway = _gateway;
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the pending (claimable) dividends for a user
     * @param user The user to check
     * @return The amount of pending dividends
     */
    function pendingDividends(address user) public view returns (uint256) {
        uint256 shares = balanceOf[user];
        if (shares == 0) return unclaimedDividends[user];

        uint256 dividendsDelta = cumulativeDividendsPerShare - userDividendCheckpoints[user];
        uint256 pending = (shares * dividendsDelta) / PRECISION;

        return unclaimedDividends[user] + pending;
    }

    /**
     * @notice Quotes the fee required to claim dividends
     * @return fee The LayerZero fee required for claiming
     */
    function quoteRequestClaimDividends(address user, uint128 gasLimit) external view returns (uint256 fee) {
        return IGateway(gateway).quoteRead(
            address(this), abi.encodeWithSelector(this.pendingDividends.selector, user), 256, gasLimit
        );
    }

    function quoteTransferDividends(uint128 gasLimit) external view returns (uint256 fee) {
        return dividendToken.quoteTransfer(address(this), gasLimit);
    }

    /**
     * @notice Returns the current dividend token balance held by this contract
     * @return The balance of dividend tokens
     */
    function getDividendBalance() external view returns (uint256) {
        return dividendToken.balanceOf(address(this));
    }

    function reduce(IGatewayApp.Request[] calldata requests, bytes calldata callData, bytes[] calldata responses)
        external
        view
        returns (bytes memory)
    {
        if (requests.length == 0 || responses.length == 0) revert InvalidRequests();

        // parse user from callData `pendingDividends(address user)`
        address user = address(bytes20(callData[16:36]));
        uint256 totalPending = pendingDividends(user);
        for (uint256 i; i < responses.length; ++i) {
            uint256 pending = abi.decode(responses[i], (uint256));
            totalPending += pending;
        }

        return abi.encode(totalPending);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the gateway contract address
     * @param _gateway The new gateway address
     */
    function updateGateway(address _gateway) external onlyOwner {
        if (_gateway == address(0)) revert InvalidGateway();
        gateway = _gateway;
        emit GatewayUpdated(_gateway);
    }

    function updateReadTarget(bytes32 chainIdentifier, bytes32 target) external onlyOwner {
        IGateway(gateway).updateReadTarget(chainIdentifier, target);
    }

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

    function registerForDividends(bytes memory signature) external {
        if (isRegistered[msg.sender]) revert AlreadyRegistered();

        bytes32 message = keccak256(abi.encode(msg.sender, address(this))).toEthSignedMessageHash();
        address signer = message.recover(signature);

        if (signer != msg.sender) revert InvalidSignature();
        isRegistered[msg.sender] = true;

        emit RegisterForDividends(msg.sender);
    }

    function distributeDividends() external {
        _distributeDividends();
    }

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

    function requestClaimDividends(bytes memory transferData, uint256 transferFee, bytes memory data)
        external
        payable
        returns (bytes32 guid)
    {
        uint256 amount = _updateAndGetPendingDividends(msg.sender);

        if (amount == 0) revert NoDividends();

        bytes memory extra = abi.encode(msg.sender, amount, transferData, transferFee);
        guid = IGateway(gateway).read{ value: msg.value - transferFee }(
            abi.encodeWithSelector(this.pendingDividends.selector, msg.sender, transferFee), extra, 256, data
        );
    }

    function onRead(bytes calldata _message, bytes calldata _extra) external {
        if (msg.sender != gateway) revert Forbidden();

        (uint256 totalPending) = abi.decode(_message, (uint256));
        (address user, uint256 amount, bytes memory transferData, uint256 transferFee) =
            abi.decode(_extra, (address, uint256, bytes, uint256));
        if (amount > totalPending) revert InsufficientDividends();

        _transferDividends(user, amount, transferData, transferFee);
    }

    /**
     * @notice Handles incoming messages from the gateway
     * @dev Implementation of IGatewayApp.onReceive
     */
    function onReceive(bytes32, bytes calldata) external view {
        if (msg.sender != gateway) revert Forbidden();

        // DividendDistributorHook doesn't process incoming messages
        // It only uses read operations for cross-chain dividend queries
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
        if (totalSupply == 0) {
            // Update balance but don't distribute if no shares
            lastDividendBalance = currentBalance;
            return;
        }

        uint256 newDividends = currentBalance - lastDividendBalance;
        lastDividendBalance = currentBalance;

        // Update cumulative dividends per share
        cumulativeDividendsPerShare += (newDividends * PRECISION) / totalSupply;
        totalDividendsDistributed += newDividends;

        emit DividendDeposited(newDividends, cumulativeDividendsPerShare);
    }

    /**
     * @notice Updates user's pending dividends and returns the total
     * @param user The user to update
     * @return The total pending dividends
     */
    function _updateAndGetPendingDividends(address user) internal returns (uint256) {
        uint256 shares = balanceOf[user];
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
     * @notice Updates shares for a user (only registered accounts can have shares)
     * @param user The user to update
     * @param newBalance The new balance (shares)
     */
    function _updateShares(address user, uint256 newBalance) internal {
        bool registered = isRegistered[user];
        uint256 effectiveBalance = registered ? newBalance : 0;

        uint256 oldBalance = balanceOf[user];
        if (oldBalance == effectiveBalance) return;

        // Update pending dividends before changing shares
        if (oldBalance > 0) {
            _updateAndGetPendingDividends(user);
        }

        // Update total shares
        totalSupply = totalSupply + effectiveBalance - oldBalance;

        // Update user balance
        balanceOf[user] = effectiveBalance;

        // Update checkpoint for new shareholders
        if (oldBalance == 0 && effectiveBalance > 0) {
            userDividendCheckpoints[user] = cumulativeDividendsPerShare;
        }

        emit SharesUpdated(user, oldBalance, effectiveBalance, registered);
    }

    function _transferDividends(address user, uint256 amount, bytes memory data, uint256 fee) internal {
        // Reset unclaimed dividends
        unclaimedDividends[user] = 0;

        // Update checkpoint
        userDividendCheckpoints[user] = cumulativeDividendsPerShare;

        // Update total claimed
        totalDividendsClaimed += amount;

        // Update lastDividendBalance to account for the claim
        lastDividendBalance -= amount;

        // Transfer dividends using ERC20xD transfer with global availability checks
        dividendToken.transfer{ value: fee }(user, amount, data);

        emit DividendClaimed(user, amount);
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
