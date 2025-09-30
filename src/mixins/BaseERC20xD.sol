// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { BaseERC20 } from "./BaseERC20.sol";
import { IBaseERC20xD } from "../interfaces/IBaseERC20xD.sol";
import { ILiquidityMatrix } from "../interfaces/ILiquidityMatrix.sol";
import { IGateway } from "../interfaces/IGateway.sol";
import { IERC20xDHook } from "../interfaces/IERC20xDHook.sol";
import { ILiquidityMatrixHook } from "../interfaces/ILiquidityMatrixHook.sol";
import { IGatewayApp } from "../interfaces/IGatewayApp.sol";
import { AddressLib } from "../libraries/AddressLib.sol";
import { IUserWallet } from "../interfaces/IUserWallet.sol";
import { IUserWalletFactory } from "../interfaces/IUserWalletFactory.sol";

/**
 * @title BaseERC20xD
 * @notice An abstract cross-chain ERC20 token implementation that manages global liquidity
 *         and facilitates cross-chain transfer operations.
 * @dev This contract extends BaseERC20 and integrates with the IGateway interface and a
 *      LiquidityMatrix contract to track both local and settled liquidity across chains.
 *
 *      Key functionalities include:
 *      - Maintaining pending transfers and nonces to coordinate cross-chain token transfers.
 *      - Initiating cross-chain transfer requests via Gateway by composing a read command
 *        (global availability check) that aggregates liquidity across multiple chains.
 *      - Processing incoming responses through onRead() to execute transfers once the global
 *        liquidity check confirms sufficient availability.
 *      - Supporting cancellation of pending transfers and updating local liquidity via the
 *        LiquidityMatrix.
 *      - Implementing ILiquidityMatrixHook to receive notifications when remote state is settled.
 *      - Supporting extensible hook system for custom transfer logic.
 *
 *      Outgoing messages (transfers initiated by this contract) are composed and sent to remote chains
 *      for validation, while incoming messages (responses from remote chains) trigger the execution
 *      of the transfer logic.
 *
 *      Note: This contract is abstract and provides the core cross-chain transfer functionality.
 */
abstract contract BaseERC20xD is BaseERC20, Ownable, ReentrancyGuard, IBaseERC20xD, ILiquidityMatrixHook {
    using AddressLib for address;

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Context for composition operations to prevent unauthorized transfers
     * @param active Whether composition is currently active
     * @param authorizedSpender The address authorized to spend tokens during composition
     * @param fundingSource The address that provided the tokens for composition
     * @param maxSpendable The maximum amount that can be spent during composition
     */
    struct ComposeContext {
        bool active;
        address authorizedSpender;
        address fundingSource;
        uint256 maxSpendable;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    uint16 internal constant CMD_READ_AVAILABILITY = 1;

    address public liquidityMatrix;
    address public gateway;
    address public walletFactory; // UserWalletFactory for compose operations

    ComposeContext internal _composeContext;
    PendingTransfer[] internal _pendingTransfers;
    mapping(address account => uint256) internal _pendingNonce;

    // Hook storage - single hook instead of array
    address public hook;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ERC20xD contract with the necessary configurations.
     * @param _name The token name.
     * @param _symbol The token symbol.
     * @param _decimals The token decimals.
     * @param _liquidityMatrix The address of the LiquidityMatrix contract.
     * @param _gateway The address of the Gateway contract.
     * @param _owner The address that will be granted ownership privileges.
     * @param _settler The address of the whitelisted settler for this token.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner,
        address _settler
    ) BaseERC20(_name, _symbol, _decimals) Ownable(_owner) {
        liquidityMatrix = _liquidityMatrix;
        gateway = _gateway;
        _pendingTransfers.push();

        // Register this contract as an app in the LiquidityMatrix with callbacks enabled
        ILiquidityMatrix(_liquidityMatrix).registerApp(false, true, _settler);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaseERC20xD
    function pendingNonce(address account) external view returns (uint256) {
        return _pendingNonce[account];
    }

    /// @inheritdoc IBaseERC20xD
    function pendingTransfer(address account) external view returns (PendingTransfer memory) {
        uint256 nonce = _pendingNonce[account];
        return _pendingTransfers[nonce];
    }

    /**
     * @notice Returns the total supply of the token across all chains.
     * @return The total supply of the token as a `uint256`.
     */
    function totalSupply() public view override(BaseERC20, IERC20) returns (uint256) {
        return _toUint(ILiquidityMatrix(liquidityMatrix).getAggregatedSettledTotalLiquidity(address(this)));
    }

    /**
     * @notice Returns the synced balance of a specific account across all chains.
     * @param account The address of the account to query.
     * @return The synced balance of the account as a `uint256`.
     */
    function balanceOf(address account) public view override(BaseERC20, IERC20) returns (uint256) {
        return _toUint(ILiquidityMatrix(liquidityMatrix).getAggregatedSettledLiquidityAt(address(this), account));
    }

    /**
     * @dev Converts an `int256` value to `uint256`, returning 0 if the input is negative.
     * @param value The `int256` value to convert.
     * @return The converted `uint256` value.
     */
    function _toUint(int256 value) internal pure virtual returns (uint256) {
        return value < 0 ? 0 : uint256(value);
    }

    /// @inheritdoc IBaseERC20xD
    function localTotalSupply() external view returns (int256) {
        return ILiquidityMatrix(liquidityMatrix).getLocalTotalLiquidity(address(this));
    }

    /// @inheritdoc IBaseERC20xD
    function localBalanceOf(address account) public view returns (int256) {
        return ILiquidityMatrix(liquidityMatrix).getLocalLiquidity(address(this), account);
    }

    /// @inheritdoc IBaseERC20xD
    function quoteTransfer(address from, uint128 gasLimit) public view returns (uint256 fee) {
        return IGateway(gateway).quoteRead(
            address(this), abi.encodeWithSelector(this.availableLocalBalanceOf.selector, from), 256, gasLimit
        );
    }

    /// @inheritdoc IBaseERC20xD
    function availableLocalBalanceOf(address account) external view returns (int256 balance) {
        uint256 nonce = _pendingNonce[account];
        PendingTransfer storage pending = _pendingTransfers[nonce];
        return localBalanceOf(account) - int256(pending.pending ? pending.amount : 0);
    }

    /// @inheritdoc IGatewayApp
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

    /// @inheritdoc IBaseERC20xD
    function updateLiquidityMatrix(address _liquidityMatrix) external onlyOwner {
        liquidityMatrix = _liquidityMatrix;

        emit UpdateLiquidityMatrix(_liquidityMatrix);
    }

    /// @inheritdoc IBaseERC20xD
    function updateGateway(address _gateway) external onlyOwner {
        gateway = _gateway;

        emit UpdateGateway(_gateway);
    }

    /// @inheritdoc IBaseERC20xD
    function updateWalletFactory(address _walletFactory) external onlyOwner {
        walletFactory = _walletFactory;
        emit WalletFactoryUpdated(_walletFactory);
    }

    /// @inheritdoc IBaseERC20xD
    function updateReadTarget(bytes32 chainUID, bytes32 target) external onlyOwner {
        IGateway(gateway).updateReadTarget(chainUID, target);
    }

    /// @inheritdoc IBaseERC20xD
    function updateSyncMappedAccountsOnly(bool syncMappedAccountsOnly) external onlyOwner {
        ILiquidityMatrix(liquidityMatrix).updateSyncMappedAccountsOnly(syncMappedAccountsOnly);
    }

    /// @inheritdoc IBaseERC20xD
    function updateUseHook(bool useHook) external onlyOwner {
        ILiquidityMatrix(liquidityMatrix).updateUseHook(useHook);
    }

    /// @inheritdoc IBaseERC20xD
    function updateSettler(address settler) external onlyOwner {
        ILiquidityMatrix(liquidityMatrix).updateSettler(settler);
    }

    /// @inheritdoc IBaseERC20xD
    function updateRemoteApp(bytes32 chainUID, address app, uint256 appIndex) external onlyOwner {
        ILiquidityMatrix(liquidityMatrix).updateRemoteApp(chainUID, app, appIndex);
    }

    /// @inheritdoc IBaseERC20xD
    function setHook(address newHook) external onlyOwner {
        address oldHook = hook;
        hook = newHook;

        emit SetHook(oldHook, newHook);
    }

    /// @inheritdoc IBaseERC20xD
    function getHook() external view returns (address) {
        return hook;
    }

    /**
     * @notice Standard ERC20 transfer is not supported
     * @dev Reverts with Unsupported error
     */
    function transfer(address, uint256) public pure override(BaseERC20, IERC20) returns (bool) {
        revert Unsupported();
    }

    /// @inheritdoc IBaseERC20xD
    function transfer(address to, uint256 amount, bytes memory data) public payable returns (bytes32 guid) {
        return transfer(to, amount, "", 0, data);
    }

    /// @inheritdoc IBaseERC20xD
    function transfer(address to, uint256 amount, bytes memory callData, bytes memory data)
        public
        payable
        returns (bytes32 guid)
    {
        return transfer(to, amount, callData, 0, data);
    }

    /// @inheritdoc IBaseERC20xD
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
     * @param data Extra data for cross-chain messaging
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
            abi.encodeWithSelector(this.availableLocalBalanceOf.selector, from), abi.encode(nonce), 256, data
        );

        address _hook = hook;
        if (_hook != address(0)) {
            IERC20xDHook(_hook).onInitiateTransfer(from, to, amount, callData, value, data);
        }

        emit InitiateTransfer(from, to, amount, value, nonce);
    }

    /// @inheritdoc IBaseERC20xD
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
        if (!_composeContext.active) revert NotComposing();

        // Only allow transfers from the authorized spender during composition
        if (msg.sender != _composeContext.authorizedSpender) {
            revert UnauthorizedComposeSpender();
        }

        // Only allow spending from authorized sources during composition
        if (from == address(this)) {
            // Spending from the contract's balance (tokens transferred in for composition)
            // This is the intended behavior - spending the tokens provided for composition
        } else if (from == _composeContext.fundingSource) {
            // Allow spending from the original funding source, but validate balance
            int256 balance = localBalanceOf(from);
            if (balance < int256(amount)) revert InsufficientBalance();
        } else {
            // Prevent spending from any other account during composition
            revert UnauthorizedComposeSource();
        }

        // Ensure we don't exceed the maximum spendable amount
        if (amount > _composeContext.maxSpendable) revert InsufficientBalance();
        _composeContext.maxSpendable -= amount;

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _transferFrom(from, to, amount);

        return true;
    }

    /// @inheritdoc IGatewayApp
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

        address _hook = hook;
        if (_hook != address(0)) {
            IERC20xDHook(_hook).onReadGlobalAvailability(from, globalAvailability);
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
     * @param data Extra data containing cross-chain parameters
     * @dev When wallet factory is set, transfers tokens to user's wallet and executes call through wallet.
     *      Otherwise, uses contract as intermediary for backwards compatibility.
     */
    function _compose(address from, address to, uint256 amount, uint256 value, bytes memory callData, bytes memory data)
        internal
        virtual
    {
        bool useWalletFactory = walletFactory != address(0);
        address executionContext;
        address fundingSource;
        int256 oldBalance;

        // Determine execution context based on wallet factory availability
        if (useWalletFactory) {
            // Use UserWallet for execution
            executionContext = IUserWalletFactory(walletFactory).getOrCreateWallet(from);
            fundingSource = executionContext;
        } else {
            // Use contract itself for execution (backwards compatibility)
            executionContext = address(this);
            fundingSource = from;
            oldBalance = localBalanceOf(executionContext);
        }

        // Transfer tokens to execution context
        _transferFrom(from, executionContext, amount, data);

        // Set up compose context
        _composeContext =
            ComposeContext({ active: true, authorizedSpender: to, fundingSource: fundingSource, maxSpendable: amount });

        // Give the target contract allowance from execution context
        allowance[executionContext][to] = amount;

        // Execute the call
        bool ok;
        bytes memory reason;
        if (useWalletFactory) {
            // Execute through wallet (wallet becomes msg.sender)
            (ok, reason) = IUserWallet(payable(executionContext)).execute(to, value, callData);
        } else {
            // Execute directly from contract
            (ok, reason) = to.call{ value: value }(callData);
        }
        if (!ok) revert CallFailure(to, reason);

        // Clear allowances and context
        allowance[executionContext][to] = 0;
        _composeContext.active = false;

        // Handle refunds
        if (useWalletFactory) {
            // Return any remaining tokens from wallet to user
            int256 walletBalance = localBalanceOf(executionContext);
            if (walletBalance > 0) {
                _transferFrom(executionContext, from, uint256(walletBalance), data);
            }
        } else {
            // Refund the change if any (backwards compatibility mode)
            int256 newBalance = localBalanceOf(executionContext);
            if (oldBalance < newBalance) {
                _transferFrom(executionContext, from, uint256(newBalance - oldBalance), data);
            }
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
     * @param data Extra data containing cross-chain parameters when applicable
     * @dev Calls beforeTransfer and afterTransfer hooks, updates local liquidity, and emits Transfer event
     */
    function _transferFrom(address from, address to, uint256 amount, bytes memory data) internal virtual {
        address _hook = hook;
        if (_hook != address(0)) {
            IERC20xDHook(_hook).beforeTransfer(from, to, amount, data);
        }

        if (from != to) {
            if (amount > uint256(type(int256).max)) revert Overflow();

            address _liquidityMatrix = liquidityMatrix;
            if (from != address(0)) {
                ILiquidityMatrix(_liquidityMatrix).updateLocalLiquidity(
                    from, ILiquidityMatrix(_liquidityMatrix).getLocalLiquidity(address(this), from) - int256(amount)
                );
            }
            if (to != address(0)) {
                ILiquidityMatrix(_liquidityMatrix).updateLocalLiquidity(
                    to, ILiquidityMatrix(_liquidityMatrix).getLocalLiquidity(address(this), to) + int256(amount)
                );
            }
        }

        if (_hook != address(0)) {
            IERC20xDHook(_hook).afterTransfer(from, to, amount, data);
        }

        emit Transfer(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    ILiquidityMatrixHook
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called when remote accounts are successfully mapped to local accounts
     * @dev Allows apps to perform additional logic when account mappings are established
     * @param chainUID The chain unique identifier of the remote chain
     * @param remoteAccount The account address on the remote chain
     * @param localAccount The mapped local account address
     */
    function onMapAccounts(bytes32 chainUID, address remoteAccount, address localAccount) external virtual override {
        // Only allow calls from the LiquidityMatrix contract
        if (msg.sender != liquidityMatrix) revert Forbidden();

        // Call onMapAccounts on the registered hook
        address _hook = hook;
        if (_hook != address(0)) {
            try IERC20xDHook(_hook).onMapAccounts(chainUID, remoteAccount, localAccount) { }
            catch (bytes memory reason) {
                emit OnMapAccountsHookFailure(_hook, chainUID, remoteAccount, localAccount, reason);
            }
        }
    }

    /**
     * @notice Called when liquidity for a specific account is settled from a remote chain
     * @dev Triggered during settleLiquidity if callbacks are enabled for the app
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp of the settled data
     * @param account The account whose liquidity was updated
     */
    function onSettleLiquidity(bytes32 chainUID, uint256 version, uint64 timestamp, address account)
        external
        virtual
        override
    {
        // Allow calls from LiquidityMatrix or its registered RemoteAppChronicles
        if (msg.sender != liquidityMatrix) {
            // Check if sender is a valid RemoteAppChronicle for this app
            address chronicle =
                ILiquidityMatrix(liquidityMatrix).getRemoteAppChronicle(address(this), chainUID, version);
            if (msg.sender != chronicle) revert Forbidden();
        }

        // Call onSettleLiquidity on the registered hook
        address _hook = hook;
        if (_hook != address(0)) {
            int256 liquidity =
                ILiquidityMatrix(liquidityMatrix).getRemoteLiquidityAt(address(this), chainUID, account, timestamp);
            try IERC20xDHook(_hook).onSettleLiquidity(chainUID, timestamp, account, liquidity) { }
            catch (bytes memory reason) {
                emit OnSettleLiquidityHookFailure(_hook, chainUID, timestamp, account, liquidity, reason);
            }
        }
    }

    /**
     * @notice Called when the total liquidity is settled from a remote chain
     * @dev Triggered after all individual account liquidity updates are processed
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp of the settled data
     */
    function onSettleTotalLiquidity(bytes32 chainUID, uint256 version, uint64 timestamp) external virtual override {
        // Allow calls from LiquidityMatrix or its registered RemoteAppChronicles
        if (msg.sender != liquidityMatrix) {
            // Check if sender is a valid RemoteAppChronicle for this app
            address chronicle =
                ILiquidityMatrix(liquidityMatrix).getRemoteAppChronicle(address(this), chainUID, version);
            if (msg.sender != chronicle) revert Forbidden();
        }

        // Call onSettleTotalLiquidity on the registered hook
        address _hook = hook;
        if (_hook != address(0)) {
            int256 totalLiquidity =
                ILiquidityMatrix(liquidityMatrix).getRemoteTotalLiquidityAt(address(this), chainUID, timestamp);
            try IERC20xDHook(_hook).onSettleTotalLiquidity(chainUID, timestamp, totalLiquidity) { }
            catch (bytes memory reason) {
                emit OnSettleTotalLiquidityHookFailure(_hook, chainUID, timestamp, totalLiquidity, reason);
            }
        }
    }

    /**
     * @notice Called when data is settled from a remote chain
     * @dev Triggered during settleData if callbacks are enabled for the app
     * @param chainUID The chain unique identifier of the remote chain
     * @param timestamp The timestamp of the settled data
     * @param key The data key that was updated
     */
    function onSettleData(bytes32 chainUID, uint256 version, uint64 timestamp, bytes32 key) external virtual override {
        // Allow calls from LiquidityMatrix or its registered RemoteAppChronicles
        if (msg.sender != liquidityMatrix) {
            // Check if sender is a valid RemoteAppChronicle for this app
            address chronicle =
                ILiquidityMatrix(liquidityMatrix).getRemoteAppChronicle(address(this), chainUID, version);
            if (msg.sender != chronicle) revert Forbidden();
        }

        // Call onSettleData on the registered hook
        address _hook = hook;
        if (_hook != address(0)) {
            bytes memory value =
                ILiquidityMatrix(liquidityMatrix).getRemoteDataAt(address(this), chainUID, key, timestamp);
            try IERC20xDHook(_hook).onSettleData(chainUID, timestamp, key, value) { }
            catch (bytes memory reason) {
                emit OnSettleDataHookFailure(_hook, chainUID, timestamp, key, value, reason);
            }
        }
    }

    /// @inheritdoc IGatewayApp
    function onReceive(bytes32, bytes calldata) external virtual override {
        // Only allow calls from the gateway contract
        if (msg.sender != gateway) revert Forbidden();

        // BaseERC20xD doesn't process incoming messages by default
        // Derived contracts can override this to handle specific message types
    }
}
