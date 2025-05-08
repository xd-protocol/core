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
import { LzLib } from "../libraries/LzLib.sol";
import { IStargate, StargateLib } from "../libraries/StargateLib.sol";

/**
 * @title StargateVault
 * @notice A cross-chain vault that handles asset deposits, withdrawals, and staking through
 *         integrations with LayerZero, Stargate, and external staking protocols.
 * @dev This contract supports both ERC20 and native currency operations. It provides functionality
 *      for quoting deposit/withdraw fees, staking/unstaking assets, and processing cross-chain messages.
 *      Outgoing cross-chain messages are composed and sent via _lzSend(), while incoming messages are
 *      handled in _lzReceive() to complete withdrawal operations.
 */
contract StargateVault is OApp, ReentrancyGuard, IStakingVault {
    using OptionsBuilder for bytes;
    using SafeTransferLib for ERC20;
    using StargateLib for IStargate;

    struct Asset {
        bool supported;
        address addr;
    }

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
    mapping(address asset => mapping(address owner => uint256)) public sharesOf;

    mapping(uint32 srcEid => mapping(address srcAsset => Asset)) public assets;
    FailedMessage[] public failedMessages;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateStargate(address indexed asset, uint32 dstEid, address indexed stargate);
    event UpdateStaker(address indexed asset, address indexed staker);
    event UpdateAsset(uint32 indexed srcEid, address indexed srcAsset, bool supported, address indexed asset);
    event MessageFail(uint256 indexed id, bytes message, bytes reason);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidMessageType();
    error UnsupportedAsset();
    error NoFeeRequired();
    error InsufficientValue();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidMinAmount();
    error InvalidLzReceiveOption();
    error InvalidEid();
    error Forbidden();
    error InvalidComposeMsg();
    error NotStargate();
    error InvalidMessage();

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

    function getReserve(address asset) public view returns (uint256 balance) {
        if (asset == StargateLib.NATIVE) {
            balance = address(this).balance;
        } else {
            balance = ERC20(asset).balanceOf(address(this));
        }
    }

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
     * @param to The recipient address on the destination.
     * @param amount The amount to withdraw.
     * @param minAmount The minimum acceptable amount for withdrawal.
     * @param incomingData Data for the incoming cross-chain message.
     * @param incomingFee Fee for processing the incoming message.
     * @param incomingOptions Options for the incoming message.
     * @param gasLimit The gas limit for the operation.
     * @return fee The fee required.
     */
    function quoteWithdraw(
        address asset,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes memory incomingOptions,
        uint128 gasLimit
    ) external view returns (uint256 fee) {
        return _quoteWithdraw(asset, to, amount, minAmount, incomingData, incomingFee, incomingOptions, gasLimit);
    }

    /**
     * @notice Provides a withdrawal fee quote for native currency.
     * @param to The recipient address on the destination.
     * @param amount The amount to withdraw.
     * @param minAmount The minimum acceptable amount for withdrawal.
     * @param incomingData Data for the incoming cross-chain message.
     * @param incomingFee Fee for processing the incoming message.
     * @param incomingOptions Options for the incoming message.
     * @param gasLimit The gas limit for the operation.
     * @return fee The fee required.
     */
    function quoteWithdrawNative(
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes memory incomingOptions,
        uint128 gasLimit
    ) external view returns (uint256 fee) {
        return _quoteWithdraw(
            StargateLib.NATIVE, to, amount, minAmount, incomingData, incomingFee, incomingOptions, gasLimit
        );
    }

    /**
     * @notice Internal helper to calculate withdrawal fees.
     * @param asset The asset to withdraw.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     * @param minAmount The minimum acceptable withdrawal amount.
     * @param incomingData Data for the incoming cross-chain message.
     * @param incomingFee Fee for the incoming message.
     * @param incomingOptions Options for the incoming message.
     * @param gasLimit The gas limit for the operation.
     * @return fee The native fee required.
     */
    function _quoteWithdraw(
        address asset,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes memory incomingOptions,
        uint128 gasLimit
    ) internal view returns (uint256 fee) {
        Stargate memory stargate = stargates[asset];
        MessagingFee memory _fee = _quote(
            stargate.dstEid,
            abi.encode(WITHDRAW, asset, to, amount, minAmount, incomingData, incomingFee, incomingOptions),
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, incomingFee),
            false
        );
        return _fee.nativeFee;
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

    /**
     * @notice Stakes a given amount of native currency.
     * @param amount The amount of native currency to stake.
     */
    function stakeNative(uint256 amount) external nonReentrant onlyOwner {
        _stake(StargateLib.NATIVE, amount);
    }

    /**
     * @notice Internal function to perform the staking operation.
     * @dev Retrieves the staker for the asset, sets token approvals if needed, and calls the stake function.
     * @param asset The asset to stake.
     * @param amount The amount to stake.
     */
    function _stake(address asset, uint256 amount) internal {
        address staker = stakers[asset];
        if (staker == address(0)) revert UnsupportedAsset();

        if (asset == StargateLib.NATIVE) {
            IStaker(staker).stake{ value: amount }(amount);
        } else {
            ERC20(asset).safeApprove(staker, 0);
            ERC20(asset).safeApprove(staker, amount);
            IStaker(staker).stake(amount);
        }

        emit Stake(asset, amount);
    }

    /**
     * @notice Unstakes a specified amount of an asset.
     * @param asset The asset to unstake.
     * @param amount The amount to unstake.
     */
    function unstake(address asset, uint256 amount) external nonReentrant onlyOwner {
        _unstake(asset, amount);
    }

    /**
     * @notice Unstakes a specified amount of native currency.
     * @param amount The amount of native currency to unstake.
     */
    function unstakeNative(uint256 amount) external nonReentrant onlyOwner {
        _unstake(StargateLib.NATIVE, amount);
    }

    /**
     * @notice Internal function to perform unstaking.
     * @dev Calls the unstake function on the staker contract associated with the asset.
     * @param asset The asset to unstake.
     * @param amount The amount to unstake.
     */
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
    function updateAsset(uint32 srcEid, address srcAsset, bool supported, address asset) external onlyOwner {
        assets[srcEid][srcAsset] = Asset(supported, asset);

        emit UpdateAsset(srcEid, srcAsset, supported, asset);
    }

    /**
     * @notice Deposits idle tokens into the vault (only owner callable).
     * @dev Processes the deposit and returns the amount of shares received.
     * @param asset The asset to deposit.
     * @param amount The amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param options Extra options.
     * @return shares The number of shares received.
     */
    function depositIdle(address asset, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        onlyOwner
        nonReentrant
        returns (uint256 shares)
    {
        Stargate memory stargate = stargates[asset];
        if (stargate.dstEid == eid) revert InvalidEid();

        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        return _deposit(asset, amount, minAmount, gasLimit, msg.value, refundTo);
    }

    /**
     * @notice Deposits idle native currency into the vault (only owner callable).
     * @dev Processes the deposit and returns the amount of shares received.
     * @param amount The native currency amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param options Extra options.
     * @return shares The number of shares received.
     */
    function depositIdleNative(uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        onlyOwner
        nonReentrant
        returns (uint256 shares)
    {
        Stargate memory stargate = stargates[StargateLib.NATIVE];
        if (stargate.dstEid == eid) revert InvalidEid();

        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        return _deposit(StargateLib.NATIVE, amount, minAmount, gasLimit, msg.value, refundTo);
    }

    /**
     * @notice Deposits tokens into the vault.
     * @dev Transfers tokens from the sender and updates their share balance.
     * @param asset The asset to deposit.
     * @param to The recipient.
     * @param amount The amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param options Extra options.
     * @return shares The number of shares received.
     */
    function deposit(address asset, address to, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        nonReentrant
        returns (uint256 shares)
    {
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        shares = _deposit(asset, amount, minAmount, gasLimit, msg.value, refundTo);
        sharesOf[asset][to] += shares;
    }

    /**
     * @notice Deposits native currency into the vault.
     * @dev Processes the deposit and updates the sender's balance.
     * @param to The recipient.
     * @param amount The native currency amount to deposit.
     * @param minAmount The minimum acceptable deposit.
     * @param options Extra options.
     * @return shares The number of shares received.
     */
    function depositNative(address to, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        nonReentrant
        returns (uint256 shares)
    {
        if (msg.value < amount) revert InsufficientValue();

        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        shares = _deposit(StargateLib.NATIVE, amount, minAmount, gasLimit, msg.value - amount, refundTo);
        sharesOf[StargateLib.NATIVE][to] += shares;
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
        if (amount == 0) revert InvalidAmount();
        if (minAmount > amount) revert InvalidMinAmount();

        Stargate memory stargate = stargates[asset];
        if (stargate.dstEid == 0) revert UnsupportedAsset();
        if (stargate.dstEid == eid) {
            AddressLib.transferNative(refundTo, msg.value);

            shares = amount;
        } else {
            address peer = AddressLib.fromBytes32(peers[stargate.dstEid]);
            if (peer == address(0)) revert NoPeer(stargate.dstEid);

            shares = IStargate(stargate.addr).sendToken(
                stargate.dstEid, asset, peer, amount, minAmount, "", gasLimit, true, fee, refundTo
            );
        }

        emit Deposit(asset, amount, shares);
    }

    /**
     * @notice Withdraws tokens from the vault.
     * @dev Processes the withdrawal request and routes it based on whether the asset is local or cross-chain.
     * @param asset The asset to withdraw.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     * @param minAmount The minimum acceptable withdrawal amount.
     * @param incomingData Data for the incoming cross-chain message.
     * @param incomingFee Fee for processing the incoming message.
     * @param incomingOptions Options for the incoming message.
     * @param options Extra options encoded as bytes.
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
    ) external payable nonReentrant {
        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        _withdraw(
            asset, to, amount, minAmount, incomingData, incomingFee, incomingOptions, gasLimit, msg.value, refundTo
        );
    }

    /**
     * @notice Withdraws native currency from the vault.
     * @param to The recipient address.
     * @param amount The native amount to withdraw.
     * @param minAmount The minimum acceptable withdrawal amount.
     * @param incomingData Data for the incoming cross-chain message.
     * @param incomingFee Fee for processing the incoming message.
     * @param incomingOptions Options for the incoming message.
     * @param options Extra options encoded as bytes.
     */
    function withdrawNative(
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes calldata incomingOptions,
        bytes calldata options
    ) external payable nonReentrant {
        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        _withdraw(
            StargateLib.NATIVE,
            to,
            amount,
            minAmount,
            incomingData,
            incomingFee,
            incomingOptions,
            gasLimit,
            msg.value,
            refundTo
        );
    }

    /**
     * @notice Internal function to process withdrawals.
     * @dev Checks sender balance, performs unstaking if needed, and routes the withdrawal locally or cross-chain.
     * @param asset The asset to withdraw.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     * @param minAmount The minimum acceptable withdrawal amount.
     * @param incomingData Data for the incoming cross-chain message.
     * @param incomingFee Fee for the incoming message.
     * @param incomingOptions Options for the incoming message.
     * @param gasLimit The gas limit for cross-chain operations.
     * @param fee The fee to forward with the withdrawal.
     * @param refundTo The address to refund any excess fee.
     */
    function _withdraw(
        address asset,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory incomingData,
        uint128 incomingFee,
        bytes memory incomingOptions,
        uint128 gasLimit,
        uint256 fee,
        address refundTo
    ) internal {
        if (sharesOf[asset][msg.sender] < amount) revert InsufficientBalance();
        if (amount == 0) revert InvalidAmount();

        sharesOf[asset][msg.sender] -= amount;

        if (getReserve(asset) >= amount) {
            _doWithdraw(asset, to, amount, incomingData);
            return;
        }

        Stargate memory stargate = stargates[asset];
        if (stargate.dstEid == 0) revert UnsupportedAsset();
        if (stargate.dstEid == eid) {
            if (fee != 0) revert NoFeeRequired();

            _unstakeIfNeeded(asset, amount);
            _doWithdraw(asset, to, amount, incomingData);
        } else {
            if (minAmount > amount) revert InvalidMinAmount();
            if (!LzLib.isValidOptions(incomingOptions)) revert InvalidLzReceiveOption();

            _lzSend(
                stargate.dstEid,
                abi.encode(WITHDRAW, asset, to, amount, minAmount, incomingData, incomingFee, incomingOptions),
                OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, incomingFee),
                MessagingFee(fee, 0),
                payable(refundTo)
            );
        }
    }

    /**
     * @notice Internal helper to unstake tokens if the current balance is insufficient.
     * @dev Checks the contract's current balance (or native balance) and calls _unstake() if needed.
     * @param asset The asset to check.
     * @param amount The required amount.
     */
    function _unstakeIfNeeded(address asset, uint256 amount) internal {
        uint256 balance = getReserve(asset);
        if (balance < amount) {
            _unstake(asset, amount - balance);
        }
    }

    function _doWithdraw(address asset, address to, uint256 amount, bytes memory data) internal {
        if (asset == StargateLib.NATIVE) {
            try IStakingVaultNativeCallbacks(to).onWithdrawNative{ value: amount }(data) { }
            catch {
                AddressLib.transferNative(to, amount);
            }
        } else {
            ERC20(asset).safeApprove(to, 0);
            ERC20(asset).safeApprove(to, amount);
            try IStakingVaultCallbacks(to).onWithdraw(asset, amount, data) { }
            catch {
                ERC20(asset).safeTransfer(to, amount);
            }
        }

        emit Withdraw(asset, amount);
    }

    /**
     * @notice Unstakes tokens and sends them cross-chain.
     * @dev Initiates an outgoing message to transfer tokens after unstaking.
     * @param dstEid The destination endpoint identifier.
     * @param asset The asset to send.
     * @param to The recipient address.
     * @param amount The amount to send.
     * @param minAmount The minimum acceptable amount on the destination.
     * @param options Extra options encoded as bytes.
     * @return dstAmount The amount received on the destination chain.
     */
    function unstakeAndSend(
        uint32 dstEid,
        address asset,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes calldata options
    ) external payable nonReentrant onlyOwner returns (uint256 dstAmount) {
        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        return _unstakeAndSend(dstEid, asset, amount, minAmount, to, gasLimit, msg.value, refundTo);
    }

    /**
     * @notice Unstakes native tokens and sends them cross-chain.
     * @param dstEid The destination endpoint identifier.
     * @param to The recipient address.
     * @param amount The amount to send.
     * @param minAmount The minimum acceptable amount on the destination.
     * @param options Extra options encoded as bytes.
     * @return dstAmount The amount received on the destination chain.
     */
    function unstakeAndSendNative(uint32 dstEid, address to, uint256 amount, uint256 minAmount, bytes calldata options)
        external
        payable
        nonReentrant
        onlyOwner
        returns (uint256 dstAmount)
    {
        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);
        return _unstakeAndSend(dstEid, StargateLib.NATIVE, amount, minAmount, to, gasLimit, msg.value, refundTo);
    }

    /**
     * @notice Internal function to unstake tokens and initiate an outgoing cross-chain send.
     * @param dstEid The destination endpoint identifier.
     * @param asset The asset to send.
     * @param amount The amount to send.
     * @param minAmount The minimum acceptable amount on the destination.
     * @param to The recipient address.
     * @param gasLimit The gas limit for cross-chain operations.
     * @param fee The fee to forward with the send.
     * @param refundTo The address to refund any excess fee.
     * @return dstAmount The amount received on the destination chain.
     */
    function _unstakeAndSend(
        uint32 dstEid,
        address asset,
        uint256 amount,
        uint256 minAmount,
        address to,
        uint128 gasLimit,
        uint256 fee,
        address refundTo
    ) internal returns (uint256 dstAmount) {
        if (dstEid == eid) revert InvalidEid();
        if (amount == 0) revert InvalidAmount();
        if (minAmount > amount) revert InvalidMinAmount();

        _unstakeIfNeeded(asset, amount);

        return _sendToken(dstEid, asset, to, amount, minAmount, "", gasLimit, fee, refundTo);
    }

    /**
     * @notice Internal function to send tokens cross-chain using Stargate.
     * @param dstEid The destination endpoint identifier.
     * @param asset The asset to send.
     * @param to The recipient address.
     * @param amount The amount to send.
     * @param minAmount The minimum acceptable amount on the destination.
     * @param data Additional data to pass with the send.
     * @param gasLimit The gas limit for cross-chain operations.
     * @param fee The fee to forward with the send.
     * @param refundTo The address to refund any excess fee.
     * @return dstAmount The amount received on the destination chain.
     */
    function _sendToken(
        uint32 dstEid,
        address asset,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory data,
        uint128 gasLimit,
        uint256 fee,
        address refundTo
    ) internal returns (uint256 dstAmount) {
        Stargate memory stargate = stargates[asset];
        if (stargate.dstEid == 0) revert UnsupportedAsset();
        address peer = AddressLib.fromBytes32(peers[stargate.dstEid]);
        if (peer == address(0)) revert NoPeer(stargate.dstEid);

        dstAmount = IStargate(stargate.addr).sendToken(
            dstEid, asset, peer, amount, minAmount, abi.encode(asset, to, data), gasLimit, true, fee, refundTo
        );
    }

    /*//////////////////////////////////////////////////////////////
                            RECEIVER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receives and processes a cross-chain message.
     * @dev Decodes the incoming message and, after unstaking if needed, routes tokens
     *      either locally (if on the same chain) or via a cross-chain send.
     * @param _origin The origin of the message.
     * @param _message The encoded message payload.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal virtual override {
        uint16 mt = abi.decode(_message, (uint16));
        if (mt != WITHDRAW) revert InvalidMessageType();

        (
            ,
            address asset,
            address to,
            uint256 amount,
            uint256 minAmount,
            bytes memory data,
            uint128 fee,
            bytes memory options
        ) = abi.decode(_message, (uint16, address, address, uint256, uint256, bytes, uint128, bytes));
        (uint128 gasLimit, address refundTo) = LzLib.decodeOptions(options);

        _unstakeIfNeeded(asset, amount);

        _sendToken(_origin.srcEid, asset, to, amount, minAmount, data, gasLimit, fee, refundTo);
    }

    /**
     * @notice Composes a LayerZero message from an OApp.
     * @dev Validates the sender, composes the message using OFTComposeMsgCodec, and then processes a withdrawal.
     *      If processing fails, records the failure in failedMessages.
     * @param from The address initiating the composition.
     * @param message The encoded message payload.
     */
    function lzCompose(
        address from,
        bytes32, /* guid */
        bytes calldata message,
        address, /* executor */
        bytes calldata /* extraData */
    ) external payable {
        if (msg.sender != address(endpoint)) revert Forbidden();

        bytes memory composeMsg = OFTComposeMsgCodec.composeMsg(message);
        if (composeMsg.length < 20) revert InvalidComposeMsg();

        address asset = abi.decode(composeMsg, (address));
        if (from != stargates[asset].addr) revert NotStargate();

        try this.processWithdraw(message) { }
        catch (bytes memory reason) {
            uint256 id = failedMessages.length;
            failedMessages.push(FailedMessage(false, keccak256(message)));
            emit MessageFail(id, message, reason);
        }
    }

    /**
     * @notice Retries processing a previously failed withdrawal message.
     * @dev Checks that the hash of the provided message matches the stored failure and then attempts processing.
     * @param id The identifier of the failed message.
     * @param message The original message payload.
     */
    function retryWithdraw(uint256 id, bytes calldata message) external {
        FailedMessage storage fail = failedMessages[id];
        if (fail.hash != keccak256(message)) revert InvalidMessage();

        fail.resolved = true;

        processWithdraw(message);
    }

    /**
     * @notice Processes a withdrawal message.
     * @dev Decodes the source endpoint, the composed message, and the amount. Then, depending on whether the asset
     *      is native or not, calls the appropriate onWithdraw callback.
     * @param message The encoded withdrawal message.
     */
    function processWithdraw(bytes calldata message) public {
        uint32 srcEid = OFTComposeMsgCodec.srcEid(message);
        uint256 amount = OFTComposeMsgCodec.amountLD(message);
        bytes memory composeMsg = OFTComposeMsgCodec.composeMsg(message);
        (address srcAsset, address to, bytes memory data) = abi.decode(composeMsg, (address, address, bytes));

        Asset memory asset = assets[srcEid][srcAsset];
        if (!asset.supported) revert UnsupportedAsset();

        _doWithdraw(asset.addr, to, amount, data);
    }
}
