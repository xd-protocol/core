// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BaseERC20xDHook } from "../mixins/BaseERC20xDHook.sol";
import { IBaseERC20xD } from "../interfaces/IBaseERC20xD.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReadCodecV1, EVMCallRequestV1 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { IERC20xDGateway } from "../interfaces/IERC20xDGateway.sol";
import { IERC20xDGatewayCallbacks } from "../interfaces/IERC20xDGatewayCallbacks.sol";

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
 *      - Implements cross-chain dividend aggregation using LayerZero read protocol
 *
 *      The contract maintains:
 *      - Total shares (sum of all EOA balances)
 *      - Cumulative dividends per share (scaled by PRECISION)
 *      - User checkpoints for claimed dividends
 *      - Unclaimed dividend tracking per user
 *      - Cross-chain dividend queries
 */
contract DividendDistributorHook is BaseERC20xDHook, Ownable, IERC20xDGatewayCallbacks {
    using AddressLib for address;
    using BytesLib for bytes;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Precision factor for dividend calculations (1e18)
    uint256 public constant PRECISION = 1e18;

    /// @notice Command label for reading global dividend info
    uint16 internal constant CMD_READ_DIVIDEND_INFO = 100;

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

    /// @notice Gateway contract for cross-chain reads
    address public gateway;

    /// @notice Peer dividend hook addresses on other chains
    mapping(uint32 eid => bytes32 peer) public peers;

    /// @notice Pending global dividend queries
    mapping(uint256 => PendingDividendQuery) public pendingQueries;
    uint256 public queryNonce;

    struct PendingDividendQuery {
        address user;
        bool pending;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DividendDeposited(uint256 amount, uint256 newCumulativePerShare);
    event DividendClaimed(address indexed user, uint256 amount);
    event SharesUpdated(address indexed user, uint256 oldShares, uint256 newShares, bool isEOA);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    event GlobalDividendInfo(address indexed user, uint256 totalPending, uint256 queryId);
    event PeerSet(uint32 eid, bytes32 peer);
    event GatewayUpdated(address gateway);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidDividendToken();
    error NoDividends();
    error NoShares();
    error TransferFailed();
    error Unauthorized();
    error InvalidAmount();
    error InvalidGateway();
    error NoPeer(uint32 eid);
    error QueryNotPending();
    error InvalidCmd();
    error InvalidRequests();

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
     * @notice Returns the current dividend token balance held by this contract
     * @return The balance of dividend tokens
     */
    function getDividendBalance() external view returns (uint256) {
        return dividendToken.balanceOf(address(this));
    }

    /**
     * @notice Quotes the fee for querying global dividend info
     * @param gasLimit Gas limit for the callback
     * @return fee The LayerZero fee required
     */
    function quoteGlobalDividendQuery(uint128 gasLimit) external view returns (uint256 fee) {
        bytes memory cmd = _getGlobalDividendCmd(msg.sender);
        return IERC20xDGateway(gateway).quoteRead(cmd, gasLimit);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the peer dividend hook address for a specific chain
     * @param eid The endpoint ID of the peer chain
     * @param peer The peer dividend hook address
     */
    function setPeer(uint32 eid, bytes32 peer) external onlyOwner {
        peers[eid] = peer;
        emit PeerSet(eid, peer);
    }

    /**
     * @notice Updates the gateway contract address
     * @param _gateway The new gateway address
     */
    function updateGateway(address _gateway) external onlyOwner {
        if (_gateway == address(0)) revert InvalidGateway();
        gateway = _gateway;
        emit GatewayUpdated(_gateway);
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

    /**
     * @notice Queries global dividend information across all chains
     * @param user The user to query dividends for
     * @param data LayerZero parameters
     * @return queryId The ID of the pending query
     */
    function queryGlobalDividends(address user, bytes memory data) external payable returns (uint256 queryId) {
        queryId = ++queryNonce;
        pendingQueries[queryId] = PendingDividendQuery(user, true);

        bytes memory cmd = _getGlobalDividendCmd(user);
        IERC20xDGateway(gateway).read{ value: msg.value }(cmd, data);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the peer address for a given endpoint ID
     * @param _eid The endpoint ID to query
     * @return The peer address as bytes32
     * @dev Reverts with NoPeer if no peer is set for the endpoint
     */
    function _getPeerOrRevert(uint32 _eid) internal view returns (bytes32) {
        bytes32 peer = peers[_eid];
        if (peer == bytes32(0)) revert NoPeer(_eid);
        return peer;
    }

    /**
     * @notice Constructs the command for querying global dividend info
     * @param user The user to query for
     * @return The encoded command
     */
    function _getGlobalDividendCmd(address user) internal view returns (bytes memory) {
        (uint32[] memory eids,) = IERC20xDGateway(gateway).chainConfigs();
        address[] memory targets = new address[](eids.length);

        for (uint256 i; i < eids.length; ++i) {
            bytes32 peer = _getPeerOrRevert(eids[i]);
            targets[i] = AddressCast.toAddress(peer);
        }

        return IERC20xDGateway(gateway).getCmd(
            CMD_READ_DIVIDEND_INFO, targets, abi.encodeWithSelector(this.pendingDividends.selector, user)
        );
    }

    /**
     * @notice Processes responses from LayerZero's read protocol
     * @param _cmd The encoded command
     * @param _responses Array of responses from each chain
     * @return The encoded aggregated result
     */
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory) {
        (uint16 cmdLabel, EVMCallRequestV1[] memory requests,) = ReadCodecV1.decode(_cmd);

        if (cmdLabel == CMD_READ_DIVIDEND_INFO) {
            if (requests.length == 0) revert InvalidRequests();

            // Decode user from the selector call
            address user = abi.decode(requests[0].callData.slice(4, 32), (address));

            uint256 totalPending;
            for (uint256 i; i < _responses.length; ++i) {
                uint256 pending = abi.decode(_responses[i], (uint256));
                totalPending += pending;
            }

            return abi.encode(cmdLabel, user, totalPending);
        } else {
            revert InvalidCmd();
        }
    }

    /**
     * @notice Callback for LayerZero read responses
     * @param _message The encoded message containing the read response
     */
    function onRead(bytes calldata _message) external {
        if (msg.sender != gateway) revert Forbidden();

        uint16 cmdLabel = abi.decode(_message, (uint16));
        if (cmdLabel == CMD_READ_DIVIDEND_INFO) {
            (, address user, uint256 totalPending) = abi.decode(_message, (uint16, address, uint256));

            // Find the query ID for this user
            uint256 queryId;
            for (uint256 i = 1; i <= queryNonce; ++i) {
                if (pendingQueries[i].pending && pendingQueries[i].user == user) {
                    queryId = i;
                    pendingQueries[i].pending = false;
                    break;
                }
            }

            emit GlobalDividendInfo(user, totalPending, queryId);
        } else {
            revert InvalidCmd();
        }
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
