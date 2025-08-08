// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { BaseERC20 } from "./BaseERC20.sol";
import { IBaseERC20xD } from "../interfaces/IBaseERC20xD.sol";
import { ILiquidityMatrix } from "../interfaces/ILiquidityMatrix.sol";
import { IGateway } from "../interfaces/IGateway.sol";
import { IERC20xDHook } from "../interfaces/IERC20xDHook.sol";
import { ILiquidityMatrixCallbacks } from "../interfaces/ILiquidityMatrixCallbacks.sol";
import { IGatewayApp } from "../interfaces/IGatewayApp.sol";
import { AddressLib } from "../libraries/AddressLib.sol";

/**
 * @title BaseERC20xD
 * @notice An abstract cross-chain ERC20 token implementation that manages global liquidity
 *         and facilitates cross-chain transfer operations.
 * @dev This contract extends BaseERC20 and integrates with LayerZero's OAppRead protocol and a
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
 *      - Implementing ILiquidityMatrixCallbacks to receive notifications when remote state is settled.
 *
 *      Outgoing messages (transfers initiated by this contract) are composed and sent to remote chains
 *      for validation, while incoming messages (responses from remote chains) trigger the execution
 *      of the transfer logic.
 *
 *      Note: This contract is abstract and requires derived implementations to provide specific logic
 *      for functions such as _compose() and _transferFrom() as well as other operational details.
 */
abstract contract BaseERC20xD is BaseERC20, Ownable, ReentrancyGuard, IBaseERC20xD, ILiquidityMatrixCallbacks {
    using AddressLib for address;
    using BytesLib for bytes;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint16 internal constant CMD_READ_AVAILABILITY = 1;

    address public liquidityMatrix;
    address public gateway;

    bool internal _composing;
    PendingTransfer[] internal _pendingTransfers;
    mapping(address acount => uint256) internal _pendingNonce;

    // Hooks storage
    address[] public hooks;
    mapping(address => bool) public isHook;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UpdateLiquidityMatrix(address indexed liquidityMatrix);
    event UpdateGateway(address indexed gateway);
    event InitiateTransfer(
        address indexed from, address indexed to, uint256 amount, uint256 value, uint256 indexed nonce
    );
    event CancelPendingTransfer(uint256 indexed nonce);
    event HookAdded(address indexed hook);
    event HookRemoved(address indexed hook);
    event OnInitiateTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, uint256 value, bytes reason
    );
    event OnReadGlobalAvailabilityHookFailure(
        address indexed hook, address indexed account, int256 globalAvailability, bytes reason
    );
    event BeforeTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, bytes reason
    );
    event AfterTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, bytes reason
    );
    event OnMapAccountsHookFailure(
        address indexed hook, uint32 indexed eid, address remoteAccount, address localAccount, bytes reason
    );
    event OnSettleLiquidityHookFailure(
        address indexed hook,
        uint32 indexed eid,
        uint256 timestamp,
        address indexed account,
        int256 liquidity,
        bytes reason
    );
    event OnSettleTotalLiquidityHookFailure(
        address indexed hook, uint32 indexed eid, uint256 timestamp, int256 totalLiquidity, bytes reason
    );
    event OnSettleDataHookFailure(
        address indexed hook, uint32 indexed eid, uint256 timestamp, bytes32 indexed key, bytes value, bytes reason
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRequests();
    error Unsupported();
    error Forbidden();
    error TransferNotPending(uint256 nonce);
    error InvalidAmount();
    error InvalidAddress();
    error InsufficientBalance();
    error InsufficientValue();
    error TransferPending();
    error Overflow();
    error InsufficientAvailability(uint256 nonce, uint256 amount, int256 availabillity);
    error CallFailure(address to, bytes reason);
    error NotComposing();
    error HookAlreadyAdded();
    error HookNotFound();

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

        // Register this contract as an app in the LiquidityMatrix with callbacks enabled
        ILiquidityMatrix(_liquidityMatrix).registerApp(false, true, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the pending transfer nonce for an account
     * @param account The account to check
     * @return The pending transfer nonce (0 if no pending transfer)
     */
    function pendingNonce(address account) external view returns (uint256) {
        return _pendingNonce[account];
    }

    /**
     * @notice Returns the pending transfer details for an account
     * @param account The account to check
     * @return The pending transfer struct
     */
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
     * @notice Returns the total supply on the current chain.
     * @return The local total supply of the token as an `int256`.
     */
    function localTotalSupply() public view returns (int256) {
        return ILiquidityMatrix(liquidityMatrix).getLocalTotalLiquidity(address(this));
    }

    /**
     * @notice Returns the local balance of a specific account on the current chain.
     * @param account The account to query.
     * @return The local balance of the account on this chain as an `int256`.
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
        return IGateway(gateway).quoteRead(
            address(this), abi.encodeWithSelector(this.availableLocalBalanceOf.selector, from), 256, gasLimit
        );
    }

    /**
     * @notice Retrieves available balance of account on current chain.
     * @dev This will be called by lzRead from remote chains.
     * @param account The owner of available balance to read.
     * @return balance The balance that can be spent on current chain.
     */
    function availableLocalBalanceOf(address account) public view returns (int256 balance) {
        uint256 nonce = _pendingNonce[account];
        PendingTransfer storage pending = _pendingTransfers[nonce];
        return localBalanceOf(account) - int256(pending.pending ? pending.amount : 0);
    }

    function reduce(IGatewayApp.Request[] calldata requests, bytes calldata, bytes[] calldata responses)
        external
        pure
        returns (bytes memory)
    {
        if (requests.length == 0) revert InvalidRequests();

        int256 availability;
        for (uint256 i; i < responses.length; ++i) {
            int256 balance = abi.decode(responses[i], (int256));
            availability += balance;
        }
        return abi.encode(availability);
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the liquidity matrix contract address
     * @param _liquidityMatrix The new liquidity matrix address
     */
    function updateLiquidityMatrix(address _liquidityMatrix) external onlyOwner {
        liquidityMatrix = _liquidityMatrix;

        emit UpdateLiquidityMatrix(_liquidityMatrix);
    }

    /**
     * @notice Updates the gateway contract address
     * @param _gateway The new gateway address
     */
    function updateGateway(address _gateway) external onlyOwner {
        gateway = _gateway;

        emit UpdateGateway(_gateway);
    }

    function updateReadTarget(bytes32 chainIdentifier, bytes32 target) external onlyOwner {
        IGateway(gateway).updateReadTarget(chainIdentifier, target);
    }

    /**
     * @notice Updates whether the app syncs only mapped accounts
     * @param syncMappedAccountsOnly If true, only mapped accounts will be synced
     */
    function updateSyncMappedAccountsOnly(bool syncMappedAccountsOnly) external onlyOwner {
        ILiquidityMatrix(liquidityMatrix).updateSyncMappedAccountsOnly(syncMappedAccountsOnly);
    }

    /**
     * @notice Updates whether this app uses callbacks from LiquidityMatrix
     * @param useCallbacks Whether to enable callbacks
     */
    function updateUseCallbacks(bool useCallbacks) external onlyOwner {
        ILiquidityMatrix(liquidityMatrix).updateUseCallbacks(useCallbacks);
    }

    /**
     * @notice Updates the authorized settler address for this app
     * @param settler The new settler address
     */
    function updateSettler(address settler) external onlyOwner {
        ILiquidityMatrix(liquidityMatrix).updateSettler(settler);
    }

    /**
     * @notice Adds a new hook contract to receive balance change notifications
     * @dev Hooks are called in the order they were added
     * @param hook The address of the hook contract implementing IERC20xDHook
     */
    function addHook(address hook) external onlyOwner {
        if (hook == address(0)) revert InvalidAddress();
        if (isHook[hook]) revert HookAlreadyAdded();

        hooks.push(hook);
        isHook[hook] = true;

        emit HookAdded(hook);
    }

    /**
     * @notice Removes a hook contract from receiving balance change notifications
     * @param hook The address of the hook contract to remove
     */
    function removeHook(address hook) external onlyOwner {
        if (!isHook[hook]) revert HookNotFound();

        // Find and remove hook from array
        uint256 length = hooks.length;
        for (uint256 i; i < length; ++i) {
            if (hooks[i] == hook) {
                // Move the last element to this position and pop
                hooks[i] = hooks[length - 1];
                hooks.pop();
                break;
            }
        }

        isHook[hook] = false;
        emit HookRemoved(hook);
    }

    /**
     * @notice Returns all registered hooks
     * @return Array of hook contract addresses
     */
    function getHooks() external view returns (address[] memory) {
        return hooks;
    }

    /**
     * @notice Standard ERC20 transfer is not supported
     * @dev Reverts with Unsupported error
     */
    function transfer(address, uint256) public pure override(BaseERC20, IERC20) returns (bool) {
        revert Unsupported();
    }

    /**
     * @notice Initiates a transfer operation.
     * @dev It performs a global availability check using lzRead to ensure `amount <= availability`.
     *      The user must provide sufficient fees via `msg.value`.
     * @param to The recipient address on the target chain.
     * @param amount The amount of tokens to transfer.
     * @param data Extra data.
     * @dev Emits a `InitiateTransfer` event upon successful initiation.
     */
    function transfer(address to, uint256 amount, bytes memory data) public payable returns (bytes32 guid) {
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
     * @dev Emits a `InitiateTransfer` event upon successful initiation.
     */
    function transfer(address to, uint256 amount, bytes memory callData, bytes memory data)
        public
        payable
        returns (bytes32 guid)
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
     * @dev Emits a `InitiateTransfer` event upon successful initiation.
     */
    function transfer(address to, uint256 amount, bytes memory callData, uint256 value, bytes memory data)
        public
        payable
        returns (bytes32 guid)
    {
        if (to == address(0)) revert InvalidAddress();

        return _transfer(msg.sender, to, amount, callData, value, data);
    }

    /**
     * @dev Internal function to initiate a cross-chain transfer
     * @param from The sender address
     * @param to The recipient address
     * @param amount The amount of tokens to transfer
     * @param callData Optional calldata for executing on recipient
     * @param value Native token value to send with callData execution
     * @param data Extra data for LayerZero messaging
     */
    function _transfer(
        address from,
        address to,
        uint256 amount,
        bytes memory callData,
        uint256 value,
        bytes memory data
    ) internal virtual returns (bytes32 guid) {
        if (amount == 0) revert InvalidAmount();
        if (amount > uint256(type(int256).max)) revert Overflow();
        if (amount > balanceOf(from)) revert InsufficientBalance();
        if (msg.value < value) revert InsufficientValue();

        uint256 nonce = _pendingNonce[from];
        if (nonce > 0) revert TransferPending();

        nonce = _pendingTransfers.length;
        _pendingTransfers.push(PendingTransfer(true, from, to, amount, callData, value, data));
        _pendingNonce[from] = nonce;

        guid = IGateway(gateway).read{ value: msg.value - value }(
            abi.encodeWithSelector(this.availableLocalBalanceOf.selector, from, nonce), abi.encode(nonce), 256, data
        );

        address[] memory _hooks = hooks;
        uint256 length = _hooks.length;
        for (uint256 i; i < length; ++i) {
            try IERC20xDHook(_hooks[i]).onInitiateTransfer(from, to, amount, callData, value, data) { }
            catch (bytes memory reason) {
                emit OnInitiateTransferHookFailure(_hooks[i], from, to, amount, value, reason);
            }
        }

        emit InitiateTransfer(from, to, amount, value, nonce);
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

    /**
     * @notice Callback function for LayerZero read responses
     * @dev Only callable by the gateway contract
     * @param _message The encoded message containing the read response
     */
    function onRead(bytes calldata _message, bytes calldata _extra) external {
        if (msg.sender != gateway) revert Forbidden();

        int256 globalAvailability = abi.decode(_message, (int256));
        uint256 nonce = abi.decode(_extra, (uint256));

        _onReadGlobalAvailability(nonce, globalAvailability);
    }

    /**
     * @notice Executes a transfer after receiving global availability data.
     * @param nonce The unique identifier for the transfer.
     * @param globalAvailability The total available liquidity across all chains.
     * @dev This function performs availability checks, executes any optional calldata, and transfers tokens.
     *      It ensures that transfers are not reentrant and handles refunds in case of failures.
     */
    function _onReadGlobalAvailability(uint256 nonce, int256 globalAvailability) internal virtual {
        PendingTransfer storage pending = _pendingTransfers[nonce];
        if (!pending.pending) revert TransferNotPending(nonce);

        address from = pending.from;
        pending.pending = false;
        _pendingNonce[from] = 0;

        uint256 amount = pending.amount;
        int256 availability = localBalanceOf(from) + globalAvailability;
        if (availability < int256(amount)) revert InsufficientAvailability(nonce, amount, availability);

        address[] memory _hooks = hooks;
        uint256 length = _hooks.length;
        for (uint256 i; i < length; ++i) {
            try IERC20xDHook(_hooks[i]).onReadGlobalAvailability(from, globalAvailability) { }
            catch (bytes memory reason) {
                emit OnReadGlobalAvailabilityHookFailure(_hooks[i], from, globalAvailability, reason);
            }
        }

        _executePendingTransfer(pending);
    }

    /**
     * @dev Executes a pending transfer after global availability check
     * @param pending The pending transfer details to execute
     * @dev Routes to _compose if callData is provided, otherwise to _transferFrom
     */
    function _executePendingTransfer(PendingTransfer memory pending) internal virtual {
        (address to, bytes memory callData) = (pending.to, pending.callData);
        if (to != address(0) /*to.isContract() &&*/ && callData.length > 0) {
            _compose(pending.from, to, pending.amount, pending.value, callData, pending.data);
        } else {
            _transferFrom(pending.from, to, pending.amount, pending.data);
        }
    }

    /**
     * @dev Handles composable transfers with calldata execution
     * @param from The sender address
     * @param to The recipient contract address
     * @param amount The amount of tokens to transfer
     * @param value Native token value to send with the call
     * @param callData The calldata to execute on the recipient
     * @param data Extra data containing LayerZero parameters
     * @dev Transfers tokens to this contract, sets allowance, executes call, and refunds any remaining tokens
     */
    function _compose(address from, address to, uint256 amount, uint256 value, bytes memory callData, bytes memory data)
        internal
        virtual
    // TODO: should be kept or not: nonReentrant
    {
        int256 oldBalance = localBalanceOf(address(this));
        _transferFrom(from, address(this), amount, data);

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
            _transferFrom(address(this), from, uint256(newBalance - oldBalance), data);
        }
    }

    /**
     * @dev Internal transfer function that updates liquidity in the LiquidityMatrix
     * @param from The sender address (can be address(0) for minting)
     * @param to The recipient address (can be address(0) for burning)
     * @param amount The amount of tokens to transfer
     * @dev Calls beforeTransfer and afterTransfer hooks, updates local liquidity, and emits Transfer event
     */
    function _transferFrom(address from, address to, uint256 amount) internal virtual {
        _transferFrom(from, to, amount, "");
    }

    /**
     * @dev Internal transfer function that updates liquidity in the LiquidityMatrix
     * @param from The sender address (can be address(0) for minting)
     * @param to The recipient address (can be address(0) for burning)
     * @param amount The amount of tokens to transfer
     * @param data Extra data containing LayerZero parameters when applicable
     * @dev Calls beforeTransfer and afterTransfer hooks, updates local liquidity, and emits Transfer event
     */
    function _transferFrom(address from, address to, uint256 amount, bytes memory data) internal virtual {
        address[] memory _hooks = hooks;
        uint256 length = _hooks.length;
        for (uint256 i; i < length; ++i) {
            try IERC20xDHook(_hooks[i]).beforeTransfer(from, to, amount, data) { }
            catch (bytes memory reason) {
                emit BeforeTransferHookFailure(_hooks[i], from, to, amount, reason);
            }
        }

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

        for (uint256 i; i < length; ++i) {
            try IERC20xDHook(_hooks[i]).afterTransfer(from, to, amount, data) { }
            catch (bytes memory reason) {
                emit AfterTransferHookFailure(_hooks[i], from, to, amount, reason);
            }
        }

        emit Transfer(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    ILiquidityMatrixCallbacks
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called when remote accounts are successfully mapped to local accounts
     * @dev Allows apps to perform additional logic when account mappings are established
     * @param eid The endpoint ID of the remote chain
     * @param remoteAccount The account address on the remote chain
     * @param localAccount The mapped local account address
     */
    function onMapAccounts(uint32 eid, address remoteAccount, address localAccount) external virtual override {
        // Only allow calls from the LiquidityMatrix contract
        if (msg.sender != liquidityMatrix) revert Forbidden();

        // Call onMapAccounts on all registered hooks
        address[] memory _hooks = hooks;
        uint256 length = _hooks.length;
        for (uint256 i; i < length; ++i) {
            try IERC20xDHook(_hooks[i]).onMapAccounts(eid, remoteAccount, localAccount) { }
            catch (bytes memory reason) {
                emit OnMapAccountsHookFailure(_hooks[i], eid, remoteAccount, localAccount, reason);
            }
        }
    }

    /**
     * @notice Called when liquidity for a specific account is settled from a remote chain
     * @dev Triggered during settleLiquidity if callbacks are enabled for the app
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp of the settled data
     * @param account The account whose liquidity was updated
     * @param liquidity The settled liquidity value
     */
    function onSettleLiquidity(uint32 eid, uint256 timestamp, address account, int256 liquidity)
        external
        virtual
        override
    {
        // Only allow calls from the LiquidityMatrix contract
        if (msg.sender != liquidityMatrix) revert Forbidden();

        // Call onSettleLiquidity on all registered hooks
        address[] memory _hooks = hooks;
        uint256 length = _hooks.length;
        for (uint256 i; i < length; ++i) {
            try IERC20xDHook(_hooks[i]).onSettleLiquidity(eid, timestamp, account, liquidity) { }
            catch (bytes memory reason) {
                emit OnSettleLiquidityHookFailure(_hooks[i], eid, timestamp, account, liquidity, reason);
            }
        }
    }

    /**
     * @notice Called when the total liquidity is settled from a remote chain
     * @dev Triggered after all individual account liquidity updates are processed
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp of the settled data
     * @param totalLiquidity The total liquidity across all accounts
     */
    function onSettleTotalLiquidity(uint32 eid, uint256 timestamp, int256 totalLiquidity) external virtual override {
        // Only allow calls from the LiquidityMatrix contract
        if (msg.sender != liquidityMatrix) revert Forbidden();

        // Call onSettleTotalLiquidity on all registered hooks
        address[] memory _hooks = hooks;
        uint256 length = _hooks.length;
        for (uint256 i; i < length; ++i) {
            try IERC20xDHook(_hooks[i]).onSettleTotalLiquidity(eid, timestamp, totalLiquidity) { }
            catch (bytes memory reason) {
                emit OnSettleTotalLiquidityHookFailure(_hooks[i], eid, timestamp, totalLiquidity, reason);
            }
        }
    }

    /**
     * @notice Called when data is settled from a remote chain
     * @dev Triggered during settleData if callbacks are enabled for the app
     * @param eid The endpoint ID of the remote chain
     * @param timestamp The timestamp of the settled data
     * @param key The data key that was updated
     * @param value The settled data value
     */
    function onSettleData(uint32 eid, uint256 timestamp, bytes32 key, bytes memory value) external virtual override {
        // Only allow calls from the LiquidityMatrix contract
        if (msg.sender != liquidityMatrix) revert Forbidden();

        // Call onSettleData on all registered hooks
        address[] memory _hooks = hooks;
        uint256 length = _hooks.length;
        for (uint256 i; i < length; ++i) {
            try IERC20xDHook(_hooks[i]).onSettleData(eid, timestamp, key, value) { }
            catch (bytes memory reason) {
                emit OnSettleDataHookFailure(_hooks[i], eid, timestamp, key, value, reason);
            }
        }
    }

    /**
     * @notice Handles incoming messages from the gateway
     * @dev Implementation of IGatewayApp.onReceive
     */
    function onReceive(bytes32, bytes calldata) external virtual override {
        // Only allow calls from the gateway contract
        if (msg.sender != gateway) revert Forbidden();

        // BaseERC20xD doesn't process incoming messages by default
        // Derived contracts can override this to handle specific message types
    }
}
