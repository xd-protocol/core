// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ReadCodecV1, EVMCallRequestV1 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import {
    MessagingReceipt,
    ILayerZeroEndpointV2
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { BaseERC20 } from "./BaseERC20.sol";
import { IBaseERC20xD } from "../interfaces/IBaseERC20xD.sol";
import { ILiquidityMatrix } from "../interfaces/ILiquidityMatrix.sol";
import { IERC20xDGateway } from "../interfaces/IERC20xDGateway.sol";
import { AddressLib } from "../libraries/AddressLib.sol";

/**
 * @title BaseERC20xD
 * @notice An abstract cross-chain ERC20 token implementation that manages global liquidity
 *         and facilitates cross-chain transfer operations.
 * @dev This contract extends BaseERC20 and integrates with LayerZero’s OAppRead protocol and a
 *      LiquidityMatrix contract to track both local and settled liquidity across chains.
 *
 *      Key functionalities include:
 *      - Maintaining pending transfers and nonces to coordinate cross-chain token transfers.
 *      - Initiating cross-chain transfer requests via LayerZero by composing a read command
 *        (global availability check) that aggregates liquidity across multiple chains.
 *      - Processing incoming responses through _lzReceive() to execute transfers once the global
 *        liquidity check confirms sufficient availability.
 *      - Supporting cancellation of pending transfers and updating local liquidity via the
 *        LiquidityMatrix.
 *
 *      Outgoing messages (transfers initiated by this contract) are composed and sent to remote chains
 *      for validation, while incoming messages (responses from remote chains) trigger the execution
 *      of the transfer logic.
 *
 *      Note: This contract is abstract and requires derived implementations to provide specific logic
 *      for functions such as _compose() and _transferFrom() as well as other operational details.
 */
abstract contract BaseERC20xD is BaseERC20, Ownable, ReentrancyGuard, IBaseERC20xD {
    using AddressLib for address;
    using BytesLib for bytes;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint16 internal constant CMD_TRANSFER = 1;

    address public liquidityMatrix;
    address public gateway;

    mapping(uint32 eid => bytes32 peer) public peers;

    bool internal _composing;
    PendingTransfer[] internal _pendingTransfers;
    mapping(address acount => uint256) internal _pendingNonce;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PeerSet(uint32 eid, bytes32 peer);
    event UpdateLiquidityMatrix(address indexed liquidityMatrix);
    event UpdateGateway(address indexed gateway);
    event Transfer(address indexed from, address indexed to, uint256 amount, uint256 indexed nonce);
    event CancelPendingTransfer(uint256 indexed nonce);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRequests();
    error InvalidCmd();
    error NoPeer(uint32 eid);
    error Unsupported();
    error Forbidden();
    error TransferNotPending(uint256 nonce);
    error InvalidAmount();
    error InvalidAddress();
    error InsufficientBalance();
    error InsufficientValue();
    error TransferPending();
    error Overflow();
    error RefundFailure(uint256 nonce);
    error InsufficientAvailability(uint256 nonce, uint256 amount, int256 availabillity);
    error CallFailure(address to, bytes reason);
    error NotComposing();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20xD contract with the necessary configurations.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the ERC20xDGateway contract.
     * @param _owner The address that will be granted ownership privileges.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner
    ) BaseERC20(_name, _symbol, _decimals) Ownable(_owner) {
        liquidityMatrix = _liquidityMatrix;
        gateway = _gateway;
        _pendingTransfers.push();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function endpoint() external view returns (ILayerZeroEndpointV2) {
        return ILiquidityMatrix(liquidityMatrix).endpoint();
    }

    function pendingNonce(address account) external view returns (uint256) {
        return _pendingNonce[account];
    }

    function pendingTransfer(address account) external view returns (PendingTransfer memory) {
        uint256 nonce = _pendingNonce[account];
        return _pendingTransfers[nonce];
    }

    /**
     * @notice Returns the total supply of the token across all chains.
     * @return The total supply of the token as a `uint256`.
     */
    function totalSupply() public view override(BaseERC20, IERC20) returns (uint256) {
        return _toUint(ILiquidityMatrix(liquidityMatrix).getSettledTotalLiquidity(address(this)));
    }

    /**
     * @notice Returns the synced balance of a specific account across all chains.
     * @param account The address of the account to query.
     * @return The synced balance of the account as a `uint256`.
     */
    function balanceOf(address account) public view override(BaseERC20, IERC20) returns (uint256) {
        return _toUint(ILiquidityMatrix(liquidityMatrix).getSettledLiquidity(address(this), account));
    }

    /**
     * @dev Converts an `int256` value to `uint256`, returning 0 if the input is negative.
     * @param value The `int256` value to convert.
     * @return The converted `uint256` value.
     */
    function _toUint(int256 value) internal pure virtual returns (uint256) {
        return value < 0 ? 0 : uint256(value);
    }

    /**
     * @notice Returns the local total supply on the current chain.
     * @return The total supply of the token as a `uint256`.
     */
    function localTotalSupply() public view returns (int256) {
        return ILiquidityMatrix(liquidityMatrix).getLocalTotalLiquidity(address(this));
    }

    /**
     * @notice Returns the local balance of a specific account on the current chain.
     * @param account The address of the account to query.
     * @return The local balance of the account on this chain as a `uint256`.
     */
    function localBalanceOf(address account) public view returns (int256) {
        return ILiquidityMatrix(liquidityMatrix).getLocalLiquidity(address(this), account);
    }

    /**
     * @notice Quotes the messaging fee for sending a read request with specific gas and calldata size.
     * @param from The address initiating the cross-chain transfer.
     * @param gasLimit The gas limit to allocate for actual transfer after lzRead.
     * @return fee The estimated messaging fee for the request.
     */
    function quoteTransfer(address from, uint128 gasLimit) public view returns (uint256 fee) {
        bytes memory cmd = getTransferCmd(from, _pendingTransfers.length);
        return IERC20xDGateway(gateway).quoteRead(cmd, gasLimit);
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
     */
    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory) {
        (uint16 appCmdLabel, EVMCallRequestV1[] memory requests,) = ReadCodecV1.decode(_cmd);
        if (appCmdLabel == CMD_TRANSFER) {
            if (requests.length == 0) revert InvalidRequests();
            // decode nonce from callData for availableLocalBalanceOf(address account, uint256 nonce)
            uint256 nonce = uint256(bytes32(requests[0].callData.slice(36, 32)));

            int256 availability;
            for (uint256 i; i < _responses.length; ++i) {
                int256 balance = abi.decode(_responses[i], (int256));
                availability += balance;
            }
            return abi.encode(appCmdLabel, nonce, availability);
        } else {
            revert InvalidCmd();
        }
    }

    /**
     * @notice Constructs the command payload for initiating a cross-chain transfer read request.
     * @param from The address initiating the cross-chain transfer.
     * @param nonce The unique identifier for the transfer.
     * @return cmd The encoded command data.
     * @dev Constructs read requests for each configured chain in the LiquidityMatrix.
     */
    function getTransferCmd(address from, uint256 nonce) public view returns (bytes memory) {
        (uint32[] memory eids,) = IERC20xDGateway(gateway).chainConfigs();
        address[] memory targets = new address[](eids.length);
        for (uint256 i; i < eids.length; ++i) {
            bytes32 peer = _getPeerOrRevert(eids[i]);
            targets[i] = AddressCast.toAddress(peer);
        }

        return IERC20xDGateway(gateway).getCmd(
            CMD_TRANSFER, targets, abi.encodeWithSelector(this.availableLocalBalanceOf.selector, from, nonce)
        );
    }

    function _getPeerOrRevert(uint32 _eid) internal view virtual returns (bytes32) {
        bytes32 peer = peers[_eid];
        if (peer == bytes32(0)) revert NoPeer(_eid);
        return peer;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function setPeer(uint32 _eid, bytes32 _peer) public virtual onlyOwner {
        peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    function updateLiquidityMatrix(address _liquidityMatrix) external onlyOwner {
        liquidityMatrix = _liquidityMatrix;

        emit UpdateLiquidityMatrix(_liquidityMatrix);
    }

    function updateGateway(address _gateway) external onlyOwner {
        gateway = _gateway;

        emit UpdateGateway(_gateway);
    }

    /**
     * @notice Transfers tokens locally on the current chain.
     * @dev The transfer is limited by availableLocalBalanceOf() to ensure it doesn't
     *      interfere with pending cross-chain transfers.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return success True if the transfer was successful.
     */
    function transfer(address to, uint256 amount) public override(BaseERC20, IERC20) returns (bool) {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        // Check available balance (local balance minus pending transfers)
        int256 available = availableLocalBalanceOf(msg.sender, 0);
        if (available < int256(amount)) revert InsufficientBalance();

        // Perform the transfer
        _transferFrom(msg.sender, to, amount);

        return true;
    }

    /**
     * @notice Initiates a transfer operation.
     * @dev It performs a global availability check using lzRead to ensure `amount <= availability`.
     *      The user must provide sufficient fees via `msg.value`.
     * @param to The recipient address on the target chain.
     * @param amount The amount of tokens to transfer.
     * @param data Extra data.
     * @return receipt The messaging receipt from LayerZero, confirming the request details.
     *         Includes the `guid` and `block` parameters for tracking.
     * @dev Emits a `Transfer` event upon successful initiation.
     */
    function transfer(address to, uint256 amount, bytes memory data)
        public
        payable
        returns (MessagingReceipt memory receipt)
    {
        return transfer(to, amount, "", 0, data);
    }

    /**
     * @notice Initiates a transfer operation.
     * @dev It performs a global availability check using lzRead to ensure `amount <= availability`.
     *      The user must provide sufficient fees via `msg.value`.
     * @param to The recipient address on the target chain.
     * @param amount The amount of tokens to transfer.
     * @param callData Optional calldata for executing a function on the recipient contract.
     * @param data Extra data.
     * @return receipt The messaging receipt from LayerZero, confirming the request details.
     *         Includes the `guid` and `block` parameters for tracking.
     * @dev Emits a `Transfer` event upon successful initiation.
     */
    function transfer(address to, uint256 amount, bytes memory callData, bytes memory data)
        public
        payable
        returns (MessagingReceipt memory receipt)
    {
        return transfer(to, amount, callData, 0, data);
    }

    /**
     * @notice Initiates a transfer operation.
     * @dev It performs a global availability check using lzRead to ensure `amount <= availability`.
     *      The user must provide sufficient fees via `msg.value`.
     * @param to The recipient address on the target chain.
     * @param amount The amount of tokens to transfer.
     * @param callData Optional calldata for executing a function on the recipient contract.
     * @param value Native cryptocurrency to be sent when calling the recipient with `callData`.
     * @param data Extra data.
     * @return receipt The messaging receipt from LayerZero, confirming the request details.
     *         Includes the `guid` and `block` parameters for tracking.
     * @dev Emits a `Transfer` event upon successful initiation.
     */
    function transfer(address to, uint256 amount, bytes memory callData, uint256 value, bytes memory data)
        public
        payable
        returns (MessagingReceipt memory receipt)
    {
        if (to == address(0)) revert InvalidAddress();

        return _transfer(msg.sender, to, amount, callData, value, data);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount,
        bytes memory callData,
        uint256 value,
        bytes memory data
    ) internal virtual returns (MessagingReceipt memory receipt) {
        if (amount == 0) revert InvalidAmount();
        if (amount > uint256(type(int256).max)) revert Overflow();
        if (amount > balanceOf(from)) revert InsufficientBalance();
        if (msg.value < value) revert InsufficientValue();

        uint256 nonce = _pendingNonce[from];
        if (nonce > 0) revert TransferPending();

        nonce = _pendingTransfers.length;
        _pendingTransfers.push(PendingTransfer(true, from, to, amount, callData, value));
        _pendingNonce[from] = nonce;

        bytes memory cmd = getTransferCmd(from, nonce);
        receipt = IERC20xDGateway(gateway).read{ value: msg.value - value }(cmd, data);

        emit Transfer(from, to, amount, nonce);
    }

    /**
     * @notice Cancels a pending cross-chain transfer.
     * @dev Only callable by the user who initiated the transfer.
     * @dev Emits a `CancelPendingTransfer` event upon successful cancellation.
     */
    function cancelPendingTransfer() external {
        uint256 nonce = _pendingNonce[msg.sender];
        PendingTransfer storage pending = _pendingTransfers[nonce];
        if (!pending.pending) revert TransferNotPending(nonce);

        pending.pending = false;
        _pendingNonce[msg.sender] = 0;

        AddressLib.transferNative(msg.sender, pending.value);

        emit CancelPendingTransfer(nonce);
    }

    /**
     * @notice Transfers a specified amount of tokens from one address to another, using the caller's allowance.
     * @dev The caller must be approved to transfer the specified amount on behalf of `from`.
     *      Also, this can only be called in a compose call.
     * @param from The address from which tokens will be transferred.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return true if the transfer is successful.
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override(BaseERC20, IERC20)
        returns (bool)
    {
        if (!_composing) revert NotComposing();

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _transferFrom(from, to, amount);

        return true;
    }

    function onRead(bytes calldata _message) external {
        if (msg.sender != gateway) revert Forbidden();

        uint16 appCmdLabel = abi.decode(_message, (uint16));
        if (appCmdLabel == CMD_TRANSFER) {
            (, uint256 nonce, int256 globalAvailability) = abi.decode(_message, (uint16, uint256, int256));
            _onTransfer(nonce, globalAvailability);
        } else {
            revert InvalidCmd();
        }
    }

    /**
     * @notice Executes a transfer after receiving global availability data.
     * @param nonce The unique identifier for the transfer.
     * @param globalAvailability The total available liquidity across all chains.
     * @dev This function performs availability checks, executes any optional calldata, and transfers tokens.
     *      It ensures that transfers are not reentrant and handles refunds in case of failures.
     */
    function _onTransfer(uint256 nonce, int256 globalAvailability) internal virtual {
        PendingTransfer storage pending = _pendingTransfers[nonce];
        address from = pending.from;
        if (!pending.pending) revert TransferNotPending(nonce);

        pending.pending = false;
        _pendingNonce[from] = 0;

        uint256 amount = pending.amount;
        int256 availability = localBalanceOf(from) + globalAvailability;
        if (availability < int256(amount)) revert InsufficientAvailability(nonce, amount, availability);

        uint256 balance = address(this).balance;
        _executePendingTransfer(pending);
        if (address(this).balance > balance - pending.value) {
            AddressLib.transferNative(from, address(this).balance + pending.value - balance);
        }
    }

    function _executePendingTransfer(PendingTransfer memory pending) internal virtual {
        (address to, bytes memory callData) = (pending.to, pending.callData);
        if (to != address(0) && to.isContract() && callData.length > 0) {
            _compose(pending.from, to, pending.amount, pending.value, callData);
        } else {
            _transferFrom(pending.from, to, pending.amount);
        }
    }

    function _compose(address from, address to, uint256 amount, uint256 value, bytes memory callData)
        internal
        virtual
    // TODO: should be kept or not: nonReentrant
    {
        int256 oldBalance = localBalanceOf(address(this));
        _transferFrom(from, address(this), amount);

        allowance[address(this)][to] = amount;
        _composing = true;

        // transferFrom() can be called multiple times inside the next call
        (bool ok, bytes memory reason) = to.call{ value: value }(callData);
        if (!ok) revert CallFailure(to, reason);

        allowance[address(this)][to] = 0;
        _composing = false;

        int256 newBalance = localBalanceOf(address(this));
        // refund the change if any
        if (oldBalance < newBalance) {
            _transferFrom(address(this), from, uint256(newBalance - oldBalance));
        }
    }

    function _transferFrom(address from, address to, uint256 amount) internal virtual {
        if (from != to) {
            if (amount > uint256(type(int256).max)) revert Overflow();

            if (from != address(0)) {
                ILiquidityMatrix(liquidityMatrix).updateLocalLiquidity(
                    from, ILiquidityMatrix(liquidityMatrix).getLocalLiquidity(address(this), from) - int256(amount)
                );
            }
            if (to != address(0)) {
                ILiquidityMatrix(liquidityMatrix).updateLocalLiquidity(
                    to, ILiquidityMatrix(liquidityMatrix).getLocalLiquidity(address(this), to) + int256(amount)
                );
            }
        }

        emit Transfer(from, to, amount);
    }
}
