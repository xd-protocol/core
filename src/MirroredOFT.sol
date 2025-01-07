// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { OAppRead } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppRead.sol";
import { Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {
    MessagingReceipt,
    MessagingFee,
    ILayerZeroEndpointV2
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { ISynchronizer } from "./interfaces/ISynchronizer.sol";
import { AddressLib } from "./libraries/AddressLib.sol";

contract MirroedOFT is OAppRead, ReentrancyGuard {
    using AddressLib for address;
    using OptionsBuilder for bytes;

    /**
     * @notice Represents a pending cross-chain transfer.
     * @param pending Indicates if the transfer is still pending.
     * @param from The address initiating the transfer.
     * @param amount The amount of tokens to transfer.
     * @param to The recipient address on the target chain.
     * @param callData Optional calldata for executing a function on the recipient contract.
     * @param value The native cryptocurrency value to send with the callData, if any.
     */
    struct PendingTransfer {
        bool pending;
        address from;
        uint256 amount;
        address to;
        bytes callData;
        uint256 value;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint32 public immutable READ_CHANNEL;
    address public immutable synchronizer;

    mapping(uint32 eid => uint64) internal _mirrorTransferDelays;

    bool internal _mirrorTransferring;
    PendingTransfer[] internal _pendingTransfers;
    mapping(address acount => uint256) internal _pendingNonce;

    uint16 public constant CMD_MIRROR_TRANSFER = 1;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event UpdateMirrorTransferDelay(uint32 indexed eid, uint64 delay);
    event MirrorTransfer(address indexed from, uint256 amount, address indexed to, uint256 indexed nonce);
    event InsufficientAvailability(uint256 indexed nonce, uint256 amount, int256 availabillity);
    event CallFailure(uint256 indexed nonce, address indexed to, bytes reason);
    event RefundFailure(address indexed to);
    event CancelPendingTransfer(uint256 indexed nonce);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRequests();
    error InvalidCmd();
    error InvalidLengths();
    error TransferNotPending(uint256 nonce);
    error InvalidAmount();
    error InvalidAddress();
    error InsufficientValue();
    error TransferPending();
    error ReentrantMirrorTransfer();
    error InsufficientBalance();
    error Overflow();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the MirroredOFT contract with the necessary configurations.
     * @param _synchronizer The address of the Synchronizer contract.
     * @param _endpoint The address of the LayerZero endpoint.
     * @param _owner The address that will be granted ownership privileges.
     */
    constructor(address _synchronizer, address _endpoint, address _owner) OAppRead(_endpoint, _owner) Ownable(_owner) {
        synchronizer = _synchronizer;
        READ_CHANNEL = ISynchronizer(_synchronizer).READ_CHANNEL();
        _pendingTransfers.push();

        _setPeer(READ_CHANNEL, AddressCast.toBytes32(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total supply of the token across all chains.
     * @return The total supply of the token as a `uint256`.
     */
    function totalSupply() public view returns (uint256) {
        return _toUint(ISynchronizer(synchronizer).getSettledTotalLiquidity(address(this)));
    }

    /**
     * @notice Returns the synced balance of a specific account across all chains.
     * @param account The address of the account to query.
     * @return The synced balance of the account as a `uint256`.
     */
    function balanceOf(address account) public view returns (uint256) {
        return _toUint(ISynchronizer(synchronizer).getSettledLiquidity(address(this), account));
    }

    /**
     * @dev Converts an `int256` value to `uint256`, returning 0 if the input is negative.
     * @param value The `int256` value to convert.
     * @return The converted `uint256` value.
     */
    function _toUint(int256 value) internal pure returns (uint256) {
        return value < 0 ? 0 : uint256(value);
    }

    /**
     * @notice Returns the local total supply on the current chain.
     * @return The total supply of the token as a `uint256`.
     */
    function localTotalSupply() public view returns (int256) {
        return ISynchronizer(synchronizer).getSettledTotalLiquidity(address(this));
    }

    /**
     * @notice Returns the local balance of a specific account on the current chain.
     * @param account The address of the account to query.
     * @return The local balance of the account on this chain as a `uint256`.
     */
    function localBalanceOf(address account) public view returns (int256) {
        return ISynchronizer(synchronizer).getLocalLiquidity(address(this), account);
    }

    /**
     * @notice Quotes the messaging fee for sending a read request with specific gas and calldata size.
     * @param from The address initiating the mirror transfer.
     * @param gasLimit The amount of gas to allocate for the executor.
     * @param calldataSize The size of the calldata in bytes.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteMirrorTransfer(address from, uint128 gasLimit, uint32 calldataSize)
        public
        view
        returns (MessagingFee memory fee)
    {
        return _quote(
            READ_CHANNEL,
            getCmd(from, _pendingTransfers.length),
            OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0),
            false
        );
    }

    /**
     * @notice Retrieves available balance of account on current chain.
     * @dev This will be called by lzRead from remote chains.
     * @param account The owner of available balance to read.
     * @param balance The balance that can be spent on current chain.
     */
    function availableLocalBalanceOf(address account, uint256 /* dummy */ ) public view returns (int256 balance) {
        uint256 nonce = _pendingNonce[account];
        PendingTransfer storage pending = _pendingTransfers[nonce];
        return localBalanceOf(account) - int256(pending.pending ? pending.amount : 0);
    }

    /**
     * @notice Processes the responses from LayerZero's read protocol, aggregating results based on the command label.
     * @param _cmd The encoded command specifying the request details.
     * @param _responses An array of responses corresponding to each read request.
     * @return The aggregated result.
     * @dev Specifically handles CMD_MIRROR_TRANSFER by summing up available balances across chains.
     */
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory) {
        (uint16 appCmdLabel, EVMCallRequestV1[] memory requests,) = ReadCodecV1.decode(_cmd);
        if (appCmdLabel == CMD_MIRROR_TRANSFER) {
            if (requests.length == 0) revert InvalidRequests();
            // decode callData for availableLocalBalanceOf(address account, uint256 dummy)
            (, uint256 nonce) = abi.decode(requests[0].callData, (address, uint256));

            int256 availability;
            for (uint256 i; i < _responses.length; ++i) {
                int256 balance = abi.decode(_responses[i], (int256));
                availability += balance;
            }
            return abi.encode(CMD_MIRROR_TRANSFER, nonce, availability);
        } else {
            revert InvalidCmd();
        }
    }

    /**
     * @notice Constructs the command payload for initiating a mirror transfer read request.
     * @param from The address initiating the mirror transfer.
     * @param nonce The unique identifier for the transfer.
     * @return cmd The encoded command data.
     * @dev Constructs read requests for each configured chain in the Synchronizer.
     */
    function getCmd(address from, uint256 nonce) public view returns (bytes memory) {
        ISynchronizer.ChainConfig[] memory _chainConfigs = ISynchronizer(synchronizer).chainConfigs();
        uint256 length = _chainConfigs.length;
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](length);

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 i; i < length; i++) {
            ISynchronizer.ChainConfig memory chainConfig = _chainConfigs[i];
            uint32 eid = chainConfig.targetEid;
            readRequests[i] = EVMCallRequestV1({
                appRequestLabel: uint16(i + 1),
                targetEid: eid,
                isBlockNum: false,
                blockNumOrTimestamp: timestamp + _mirrorTransferDelays[eid],
                confirmations: chainConfig.confirmations,
                to: chainConfig.to,
                callData: abi.encodeWithSelector(this.availableLocalBalanceOf.selector, from, nonce)
            });
        }

        return ReadCodecV1.encode(CMD_MIRROR_TRANSFER, readRequests, _computeSettings());
    }

    function _computeSettings() internal view returns (EVMCallComputeV1 memory) {
        return EVMCallComputeV1({
            computeSetting: 1, // lzReduce()
            targetEid: ILayerZeroEndpointV2(endpoint).eid(),
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 0,
            to: address(this)
        });
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the mirror transfer delays for specified endpoint IDs.
     * @dev Only callable by the contract owner.
     * @param eids An array of endpoint IDs whose delays are to be updated.
     * @param delays An array of delay values corresponding to each endpoint ID.
     * @dev Both arrays must be of the same length.
     */
    function updateMirrorTransferDelays(uint32[] memory eids, uint64[] memory delays) external onlyOwner {
        if (eids.length != delays.length) revert InvalidLengths();

        for (uint256 i; i < eids.length; ++i) {
            uint32 eid = eids[i];
            uint64 delay = delays[i];

            _mirrorTransferDelays[eid] = delay;

            emit UpdateMirrorTransferDelay(eid, delay);
        }
    }

    /**
     * @notice Initiates a cross-chain mirror transfer operation.
     * @dev Sends a read request with specified gas and calldata size.
     *      The user must provide sufficient fees via `msg.value`.
     *      It performs a global availability check using LayerZero's read protocol to ensure `amount <= availability`.
     * @param amount The amount of tokens to transfer.
     * @param to The recipient address on the target chain.
     * @param callData Optional calldata for executing a function on the recipient contract.
     * @param value Native cryptocurrency to be sent when calling the recipient with `callData`.
     * @param gasLimit The gas limit to allocate for the executor.
     * @param calldataSize The size of the calldata for the request, in bytes.
     * @return fee The messaging receipt from LayerZero, confirming the request details.
     *         Includes the `guid` and `block` parameters for tracking.
     * @dev Emits a `MirrorTransfer` event upon successful initiation.
     */
    function mirrorTransfer(
        uint256 amount,
        address to,
        bytes memory callData,
        uint256 value,
        uint128 gasLimit,
        uint32 calldataSize
    ) external payable returns (MessagingReceipt memory fee) {
        if (amount == 0) revert InvalidAmount();
        if (amount > balanceOf(msg.sender)) revert InsufficientBalance();
        if (to == address(0)) revert InvalidAddress();
        if (msg.value < value) revert InsufficientValue();

        uint256 nonce = _pendingNonce[msg.sender];
        if (nonce > 0) revert TransferPending();

        nonce = _pendingTransfers.length;
        _pendingTransfers.push(PendingTransfer(true, msg.sender, amount, to, callData, value));
        _pendingNonce[msg.sender] = nonce;

        bytes memory cmd = getCmd(msg.sender, nonce);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReadOption(gasLimit, calldataSize, 0);
        fee = _lzSend(READ_CHANNEL, cmd, options, MessagingFee(msg.value - value, 0), payable(msg.sender));

        emit MirrorTransfer(msg.sender, amount, to, nonce);
    }

    /**
     * @notice Cancels a pending mirror transfer.
     * @dev Only callable by the user who initiated the transfer.
     * @dev Emits a `CancelPendingTransfer` event upon successful cancellation.
     */
    function cancelPendingTransfer() external {
        uint256 nonce = _pendingNonce[msg.sender];
        PendingTransfer storage pending = _pendingTransfers[nonce];
        if (!pending.pending) revert TransferNotPending(nonce);

        pending.pending = false;
        _pendingNonce[msg.sender] = 0;

        emit CancelPendingTransfer(nonce);
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32, /* _guid */
        bytes calldata _message,
        address, /* _executor */
        bytes calldata /* _extraData */
    ) internal override nonReentrant {
        if (_origin.srcEid == READ_CHANNEL) {
            uint16 appCmdLabel = abi.decode(_message, (uint16));
            if (appCmdLabel == CMD_MIRROR_TRANSFER) {
                (, uint256 nonce, int256 globalAvailability) = abi.decode(_message, (uint16, uint256, int256));
                _onMirrorTransfer(nonce, globalAvailability);
            } else {
                revert InvalidCmd();
            }
        }
    }

    /**
     * @notice Finalizes a mirror transfer after receiving global availability data.
     * @param nonce The unique identifier for the transfer.
     * @param globalAvailability The total available liquidity across all chains.
     * @dev This function performs availability checks, executes any optional calldata, and transfers tokens.
     *      It ensures that transfers are not reentrant and handles refunds in case of failures.
     */
    function _onMirrorTransfer(uint256 nonce, int256 globalAvailability) internal {
        PendingTransfer storage pending = _pendingTransfers[nonce];
        address from = pending.from;
        if (!pending.pending) revert TransferNotPending(nonce);

        pending.pending = false;
        _pendingNonce[from] = 0;

        uint256 amount = pending.amount;
        int256 availability = localBalanceOf(from) + globalAvailability;
        if (availability < int256(amount)) {
            emit InsufficientAvailability(nonce, amount, availability);
            _refund(pending.to, pending.value);
            return;
        }

        if (_mirrorTransferring) revert ReentrantMirrorTransfer();
        _mirrorTransferring = true;

        (address to, bytes memory callData) = (pending.to, pending.callData);
        if (to.isContract() && callData.length > 0) {
            // composability
            (bool ok, bytes memory reason) = to.call{ value: pending.value }(callData);
            _mirrorTransferring = false;
            if (!ok) {
                emit CallFailure(nonce, to, reason);
                _refund(to, pending.value);
            }
        } else {
            _transfer(pending.from, pending.to, amount);
        }
    }

    function _refund(address to, uint256 value) internal {
        (bool ok) = payable(to).send(value);
        if (!ok) emit RefundFailure(to);
    }

    /**
     * @notice Transfers tokens from one address to another, handling both local and mirrored transfers.
     * @param from The address from which tokens are transferred.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @dev If `_mirrorTransferring` is true, skips local liquidity checks, relying on global availability.
     *      Otherwise, ensures the sender has sufficient local balance.
     *      Updates local liquidity balances accordingly.
     */
    function _transfer(address from, address to, uint256 amount) internal {
        if (amount > uint256(type(int256).max)) revert Overflow();

        int256 localLiquidity = ISynchronizer(synchronizer).getLocalLiquidity(address(this), from);
        if (_mirrorTransferring) {
            _mirrorTransferring = false;
        } else {
            if (localLiquidity < int256(amount)) revert InsufficientBalance();
        }

        if (from != address(0)) {
            ISynchronizer(synchronizer).updateLocalLiquidity(from, localLiquidity - int256(amount));
        }
        if (to != address(0)) {
            ISynchronizer(synchronizer).updateLocalLiquidity(
                to, ISynchronizer(synchronizer).getLocalLiquidity(address(this), to) + int256(amount)
            );
        }
    }
}
