// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Owned } from "solmate/auth/Owned.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { IStakingVault, IStakingVaultCallbacks, IStakingVaultNativeCallbacks } from "../interfaces/IStakingVault.sol";
import { IStaker } from "../interfaces/IStaker.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { IStargate, StargateLib } from "../libraries/StargateLib.sol";

contract StargateVault is OApp, ReentrancyGuard, IStakingVault {
    using OptionsBuilder for bytes;
    using SafeTransferLib for ERC20;
    using StargateLib for IStargate;

    struct Stargate {
        uint32 dstEid;
        address addr;
    }

    struct FailedMessage {
        bool resolved;
        bytes32 hash;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint16 public constant WITHDRAW = 1;

    uint32 public immutable eid;
    mapping(address asset => Stargate) public stargates;
    mapping(address asset => address) public stakers;
    mapping(address asset => mapping(address owner => uint256)) public balances;

    mapping(uint32 srcEid => mapping(address srcAsset => address)) public assets;
    FailedMessage[] public failedMessages;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateStargate(address indexed asset, uint32 dstEid, address indexed stargate);
    event UpdateStaker(address indexed asset, address indexed staker);
    event UpdateAsset(uint32 indexed srcEid, address indexed srcAsset, address indexed asset);
    event MessageFail(uint256 indexed id, bytes message, bytes reason);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidMessageType();
    error InvalidAddress();
    error UnsupportedAsset();
    error InsufficientValue();
    error InsufficientBalance();
    error InvalidEid();
    error Forbidden();
    error InvalidMessage();
    error NotStargate();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the StargateVault contract.
     * @param _endpoint The LayerZero endpoint address.
     * @param _owner The owner of the contract.
     */
    constructor(address _endpoint, address _owner) OApp(_endpoint, _owner) Ownable(_owner) {
        eid = ILayerZeroEndpointV2(_endpoint).eid();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Provides a deposit quote for a given asset.
     * @param asset The asset to deposit.
     * @param amount The amount to deposit.
     * @param gasLimit The gas limit for the operation.
     * @return minAmount The minimum deposit accepted.
     * @return fee The fee required.
     */
    function quoteDeposit(address asset, uint256 amount, uint128 gasLimit)
        external
        view
        returns (uint256 minAmount, uint256 fee)
    {
        return _quoteDeposit(asset, amount, gasLimit);
    }

    /**
     * @notice Provides a deposit quote for native currency.
     * @param amount The native amount to deposit.
     * @param gasLimit The gas limit for the operation.
     * @return minAmount The minimum deposit accepted.
     * @return fee The fee required.
     */
    function quoteDepositNative(uint256 amount, uint128 gasLimit)
        external
        view
        returns (uint256 minAmount, uint256 fee)
    {
        return _quoteDeposit(StargateLib.NATIVE, amount, gasLimit);
    }

    /**
     * @notice Internal helper for calculating deposit quotes.
     * @param asset The asset to deposit.
     * @param amount The deposit amount.
     * @param gasLimit The gas limit for cross-chain operations.
     * @return minAmount The minimum deposit accepted.
     * @return fee The fee required.
     */
    function _quoteDeposit(address asset, uint256 amount, uint128 gasLimit)
        internal
        view
        returns (uint256 minAmount, uint256 fee)
    {
        Stargate memory stargate = stargates[asset];
        if (stargate.dstEid == 0) revert UnsupportedAsset();
        if (stargate.dstEid == eid) {
            return (amount, 0);
        }

        address peer = AddressLib.fromBytes32(peers[stargate.dstEid]);
        if (peer == address(0)) revert NoPeer(stargate.dstEid);

        return IStargate(stargate.addr).quoteSendToken(stargate.dstEid, asset, peer, amount, "", gasLimit, false);
    }

    /**
     * @notice Provides a withdrawal fee quote for a token asset.
     * @param asset The asset to withdraw.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     * @param gasLimit The gas limit for the operation.
     * @return fee The fee required.
     */
    function quoteWithdraw(address asset, address to, uint256 amount, uint128 gasLimit)
        external
        view
        returns (uint256 fee)
    {
        return _quoteWithdraw(asset, to, amount, gasLimit);
    }

    /**
     * @notice Provides a withdrawal fee quote for native currency.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     * @param gasLimit The gas limit for the operation.
     * @return fee The fee required.
     */
    function quoteWithdrawNative(address to, uint256 amount, uint128 gasLimit) external view returns (uint256 fee) {
        return _quoteWithdraw(StargateLib.NATIVE, to, amount, gasLimit);
    }

    /**
     * @notice Internal helper to calculate withdrawal fees.
     * @param asset The asset to withdraw.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     * @param gasLimit The gas limit for cross-chain operations.
     * @return fee The native fee required.
     */
    function _quoteWithdraw(address asset, address to, uint256 amount, uint128 gasLimit)
        internal
        view
        returns (uint256)
    {
        Stargate memory stargate = stargates[asset];
        MessagingFee memory fee = _quote(
            stargate.dstEid,
            abi.encode(WITHDRAW, asset, to, amount),
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0),
            false
        );
        return fee.nativeFee;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the staker contract address for a given asset.
     * @param asset The asset for which the staker is being set.
     * @param staker The new staker contract address.
     */
    function updateStaker(address asset, address staker) external {
        stakers[asset] = staker;

        emit UpdateStaker(asset, staker);
    }

    /**
     * @notice Stakes a given amount of an asset.
     * @dev For native currency, value is forwarded. For tokens, approval is handled temporarily.
     * @param asset The asset to stake.
     * @param amount The amount to stake.
     */
    function stake(address asset, uint256 amount) external nonReentrant onlyOwner {
        _stake(asset, amount);
    }

    function stakeNative(uint256 amount) external nonReentrant onlyOwner {
        _stake(StargateLib.NATIVE, amount);
    }

    function _stake(address asset, uint256 amount) internal {
        address staker = stakers[asset];
        if (staker == address(0)) revert UnsupportedAsset();

        if (asset == StargateLib.NATIVE) {
            IStaker(staker).stake{ value: amount }(amount);
        } else {
            ERC20(asset).approve(staker, amount);
            IStaker(staker).stake(amount);
            ERC20(asset).approve(staker, 0);
        }

        emit Stake(asset, amount);
    }

    function unstake(address asset, uint256 amount) external nonReentrant onlyOwner {
        _unstake(asset, amount);
    }

    function unstakeNative(uint256 amount) external nonReentrant onlyOwner {
        _unstake(StargateLib.NATIVE, amount);
    }

    function _unstake(address asset, uint256 amount) internal {
        address staker = stakers[asset];
        if (staker == address(0)) revert UnsupportedAsset();

        IStaker(staker).unstake(amount);

        emit Unstake(asset, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            SENDER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the staking stargate for a given asset.
     * @dev Only callable by the owner.
     * @param asset The asset whose stargate is being updated.
     * @param dstEid The destination endpoint identifier.
     * @param stargate The address of the Stargate contract for the asset.
     */
    function updateStargate(address asset, uint32 dstEid, address stargate) external onlyOwner {
        stargates[asset] = Stargate(dstEid, stargate);

        emit UpdateStargate(asset, dstEid, stargate);
    }

    /**
     * @notice Maps a source asset from a given endpoint to an asset in this vault.
     * @dev Only callable by the owner. Reverts if the source asset is zero.
     * @param srcEid The source endpoint identifier.
     * @param srcAsset The asset address on the source chain.
     * @param asset The corresponding asset address in this vault.
     */
    function updateAsset(uint32 srcEid, address srcAsset, address asset) external onlyOwner {
        if (srcAsset == address(0)) revert InvalidAddress();

        assets[srcEid][srcAsset] = asset;

        emit UpdateAsset(srcEid, srcAsset, asset);
    }

    /**
     * @notice Deposits idle tokens into the vault (only owner callable).
     * @dev Processes the deposit and returns the amount of shares received.
     * @param asset The asset to deposit.
     * @param amount The amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for cross-chain operations.
     * @return shares The number of shares received.
     */
    function depositIdle(address asset, uint256 amount, uint256 minAmount, uint128 gasLimit)
        external
        payable
        onlyOwner
        nonReentrant
        returns (uint256 shares)
    {
        return _deposit(asset, amount, minAmount, gasLimit, msg.value, msg.sender);
    }

    /**
     * @notice Deposits idle native currency into the vault (only owner callable).
     * @dev Processes the deposit and returns the amount of shares received.
     * @param amount The native currency amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for cross-chain operations.
     * @return shares The number of shares received.
     */
    function depositIdleNative(uint256 amount, uint256 minAmount, uint128 gasLimit)
        external
        payable
        onlyOwner
        nonReentrant
        returns (uint256 shares)
    {
        return _deposit(StargateLib.NATIVE, amount, minAmount, gasLimit, msg.value, msg.sender);
    }

    /**
     * @notice Deposits tokens into the vault.
     * @dev Transfers tokens from the sender and updates their share balance.
     * @param asset The asset to deposit.
     * @param amount The amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for cross-chain operations.
     * @param refundTo The address to refund any excess fee.
     * @return shares The number of shares received.
     */
    function deposit(address asset, uint256 amount, uint256 minAmount, uint128 gasLimit, address refundTo)
        external
        payable
        nonReentrant
        returns (uint256 shares)
    {
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        shares = _deposit(asset, amount, minAmount, gasLimit, msg.value, refundTo);
        balances[asset][msg.sender] += shares;
    }

    /**
     * @notice Deposits native currency into the vault.
     * @dev Processes the deposit and updates the sender's balance.
     * @param amount The native currency amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for cross-chain operations.
     * @param refundTo The address to refund any excess fee.
     * @return shares The number of shares received.
     */
    function depositNative(uint256 amount, uint256 minAmount, uint128 gasLimit, address refundTo)
        external
        payable
        nonReentrant
        returns (uint256 shares)
    {
        if (msg.value < amount) revert InsufficientValue();

        shares = _deposit(StargateLib.NATIVE, amount, minAmount, gasLimit, msg.value - amount, refundTo);
        balances[StargateLib.NATIVE][msg.sender] += shares;
    }

    /**
     * @notice Internal function to process deposits.
     * @dev Handles both local and cross-chain deposit logic.
     * @param asset The asset to deposit.
     * @param amount The amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param gasLimit The gas limit for cross-chain operations.
     * @param fee The fee sent with the deposit.
     * @param refundTo The address to refund any excess fee.
     * @return shares The number of shares issued.
     */
    function _deposit(address asset, uint256 amount, uint256 minAmount, uint128 gasLimit, uint256 fee, address refundTo)
        internal
        returns (uint256 shares)
    {
        Stargate memory stargate = stargates[asset];
        if (stargate.dstEid == 0) revert UnsupportedAsset();
        if (stargate.dstEid == eid) {
            AddressLib.transferNative(refundTo, msg.value);

            shares = amount;
        } else {
            address peer = AddressLib.fromBytes32(peers[stargate.dstEid]);
            if (peer == address(0)) revert NoPeer(stargate.dstEid);

            shares = IStargate(stargate.addr).sendToken(
                stargate.dstEid, asset, peer, amount, minAmount, "", gasLimit, false, fee, refundTo
            );
        }

        emit Deposit(asset, amount, shares);
    }

    /**
     * @notice Withdraws tokens from the vault.
     * @dev Checks balance and processes local or cross-chain withdrawals.
     * @param asset The asset to withdraw.
     * @param amount The amount to withdraw.
     * @param data Arbitrary data to be passed as an argument for onWithdraw().
     * @param gasLimit The gas limit for cross-chain operations.
     * @param refundTo The address to refund any excess fee.
     */
    function withdraw(address asset, uint256 amount, bytes calldata data, uint128 gasLimit, address refundTo)
        external
        payable
        nonReentrant
    {
        _withdraw(asset, amount, data, gasLimit, refundTo);
    }

    /**
     * @notice Withdraws native currency from the vault.
     * @dev Checks balance and processes local or cross-chain withdrawals.
     * @param amount The native amount to withdraw.
     * @param data Arbitrary data to be passed as an argument for onWithdraw().
     * @param gasLimit The gas limit for cross-chain operations.
     * @param refundTo The address to refund any excess fee.
     */
    function withdrawNative(uint256 amount, bytes calldata data, uint128 gasLimit, address refundTo)
        external
        payable
        nonReentrant
    {
        _withdraw(StargateLib.NATIVE, amount, data, gasLimit, refundTo);
    }

    /**
     * @notice Internal function to process withdrawals.
     * @dev Validates the user's balance and handles local vs. cross-chain logic.
     * @param asset The asset to withdraw.
     * @param amount The amount to withdraw.
     * @param data Arbitrary data to be passed as an argument for onWithdraw().
     * @param gasLimit The gas limit for cross-chain operations.
     * @param refundTo The address to refund any excess fee.
     */
    function _withdraw(address asset, uint256 amount, bytes memory data, uint128 gasLimit, address refundTo) internal {
        if (balances[asset][msg.sender] < amount) revert InsufficientBalance();

        balances[asset][msg.sender] -= amount;

        Stargate memory stargate = stargates[asset];
        if (stargate.dstEid == 0) revert UnsupportedAsset();

        (, address to) = abi.decode(data, (address, address));
        if (stargate.dstEid == eid) {
            _unstakeIfNeeded(asset, amount);
            AddressLib.transferNative(refundTo, msg.value);
            if (asset == StargateLib.NATIVE) {
                IStakingVaultNativeCallbacks(msg.sender).onWithdrawNative{ value: amount }(data);
            } else {
                ERC20(asset).approve(to, amount);
                IStakingVaultCallbacks(msg.sender).onWithdraw(asset, amount, data);
                ERC20(asset).approve(to, 0);
            }
        } else {
            _lzSend(
                stargate.dstEid,
                abi.encode(WITHDRAW, asset, amount, data),
                OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0),
                MessagingFee(msg.value, 0),
                payable(msg.sender)
            );
        }

        emit Withdraw(asset, amount);
    }

    function unstakeAndSend(address asset, uint256 amount, uint256 minAmount, uint32 dstEid, uint128 gasLimit)
        external
        payable
        nonReentrant
        onlyOwner
        returns (uint256 dstAmount)
    {
        return _unstakeAndSend(asset, amount, minAmount, dstEid, gasLimit, msg.value, msg.sender);
    }

    function unstakeNativeAndSend(uint256 amount, uint256 minAmount, uint32 dstEid, uint128 gasLimit)
        external
        payable
        nonReentrant
        onlyOwner
        returns (uint256 dstAmount)
    {
        return _unstakeAndSend(StargateLib.NATIVE, amount, minAmount, dstEid, gasLimit, msg.value, msg.sender);
    }

    function _unstakeAndSend(
        address asset,
        uint256 amount,
        uint256 minAmount,
        uint32 dstEid,
        uint128 gasLimit,
        uint256 fee,
        address refundTo
    ) internal returns (uint256 dstAmount) {
        if (dstEid == eid) revert InvalidEid();

        Stargate memory stargate = stargates[asset];
        if (stargate.dstEid == 0) revert UnsupportedAsset();

        address peer = AddressLib.fromBytes32(peers[stargate.dstEid]);
        if (peer == address(0)) revert NoPeer(stargate.dstEid);

        _unstake(asset, amount);

        dstAmount = IStargate(stargate.addr).sendToken(
            dstEid, asset, peer, amount, minAmount, "", gasLimit, false, fee, refundTo
        );
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receives and processes a cross-chain message.
     * @dev This function should decode the message, perform unstaking, and transfer tokens via Stargate.
     * @param _message The encoded message payload.
     */
    function _lzReceive(
        Origin calldata, /* _origin */
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual override {
        uint16 mt = abi.decode(_message, (uint16));
        if (mt != WITHDRAW) revert InvalidMessageType();

        (, address asset, uint256 amount, bytes memory data) = abi.decode(_message, (uint16, address, uint256, bytes));
        _unstakeIfNeeded(asset, amount);
        // TODO: sendToken
    }

    function _unstakeIfNeeded(address asset, uint256 amount) internal {
        uint256 balance;
        if (asset == StargateLib.NATIVE) {
            balance = address(this).balance;
        } else {
            balance = ERC20(asset).balanceOf(address(this));
        }
        if (balance < amount) {
            _unstake(asset, amount - balance);
        }
    }

    /**
     * @notice Composes and sends a cross-chain withdrawal message.
     * @dev This function should encode the withdrawal request and dispatch it to the destination chain.
     * @param from The address initiating the withdrawal.
     * @param guid A unique identifier for this withdrawal.
     * @param message The encoded withdrawal details.
     * @param executor The address that will execute the withdrawal on the target chain.
     * @param extraData Additional data needed for composing the message.
     */
    function lzCompose(address from, bytes32 guid, bytes calldata message, address executor, bytes calldata extraData)
        external
        payable
    {
        if (msg.sender != address(endpoint)) revert Forbidden();
        if (message.length < 20) revert InvalidMessage();
        address asset = abi.decode(message, (address));
        if (from != stargates[asset].addr) revert NotStargate();

        try this.processWithdraw(message) { }
        catch (bytes memory reason) {
            uint256 id = failedMessages.length;
            failedMessages.push(FailedMessage(false, keccak256(message)));
            emit MessageFail(id, message, reason);
        }
    }

    function retryWithdraw(uint256 id, bytes calldata message) external {
        FailedMessage storage fail = failedMessages[id];
        if (fail.hash != keccak256(message)) revert InvalidMessage();

        fail.resolved = true;

        processWithdraw(message);
    }

    function processWithdraw(bytes calldata message) public {
        (address asset, uint256 amount, bytes memory data) = abi.decode(message, (address, uint256, bytes));

        if (asset == StargateLib.NATIVE) {
            IStakingVaultNativeCallbacks(msg.sender).onWithdrawNative{ value: amount }(data);
        } else {
            (, address to) = abi.decode(data, (address, address));
            ERC20(asset).approve(to, amount);
            IStakingVaultCallbacks(msg.sender).onWithdraw(asset, amount, data);
            ERC20(asset).approve(to, 0);
        }
    }
}
