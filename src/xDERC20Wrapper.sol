// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BasexDERC20 } from "./mixins/BasexDERC20.sol";
import { IStakingVault, IStakingVaultCallbacks } from "./interfaces/IStakingVault.sol";
import { AddressLib } from "./libraries/AddressLib.sol";

contract xDERC20Wrapper is BasexDERC20, IStakingVaultCallbacks {
    using SafeTransferLib for ERC20;

    enum TimeLockType {
        Invalid,
        UpdateTimeLockPeriod,
        UpdateVault
    }

    struct TimeLock {
        TimeLockType _type;
        bytes params;
        uint64 startedAt;
        bool executed;
    }

    struct FailedWithdrawal {
        bool resolved;
        uint256 amount;
        bytes data;
        uint256 value;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable underlying;

    uint64 public timeLockPeriod;
    TimeLock[] public timeLocks;

    address vault;

    FailedWithdrawal[] public failedWithdrawals;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event QueueTimeLock(uint256 indexed id, TimeLockType _type, uint64 timestamp);
    event ExecuteTimeLock(uint256 indexed id);
    event UpdateTimeLockPeriod(uint64 timeLockPeriod);
    event UpdateVault(address indexed vault);
    event Wrap(uint256 amount);
    event WithdrawFail(uint256 id, bytes reason);
    event Unwrap(address to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TimeLockExecuted();
    error TimeNotPassed();
    error InvalidTimeLockType();
    error InvalidId();
    error Forbidden();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _underlying,
        uint64 _timeLockPeriod,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _synchronizer,
        address _owner
    ) BasexDERC20(_name, _symbol, _decimals, _synchronizer, _owner) {
        underlying = _underlying;
        timeLockPeriod = _timeLockPeriod;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    fallback() external payable { }

    receive() external payable { }

    function queueUpdateTimeLockPeriod(uint64 _timeLockPeriod) external onlyOwner {
        _queueTimeLock(TimeLockType.UpdateTimeLockPeriod, abi.encode(_timeLockPeriod));
    }

    function queueUpdateVault(address _vault) external onlyOwner {
        _queueTimeLock(TimeLockType.UpdateVault, abi.encode(_vault));
    }

    function _queueTimeLock(TimeLockType _type, bytes memory params) internal {
        if (_type != TimeLockType.UpdateTimeLockPeriod && _type != TimeLockType.UpdateVault) {
            revert InvalidTimeLockType();
        }

        uint256 id = timeLocks.length;
        timeLocks.push(TimeLock(_type, params, uint64(block.timestamp), false));

        emit QueueTimeLock(id, _type, uint64(block.timestamp));
    }

    function executeTimeLock(uint256 id) external payable nonReentrant {
        TimeLock storage timeLock = timeLocks[id];
        if (timeLock.executed) revert TimeLockExecuted();
        if (block.timestamp < timeLock.startedAt + timeLockPeriod) revert TimeNotPassed();

        emit ExecuteTimeLock(id);

        if (timeLock._type == TimeLockType.UpdateTimeLockPeriod) {
            timeLockPeriod = abi.decode(timeLock.params, (uint64));

            emit UpdateTimeLockPeriod(timeLockPeriod);
        } else if (timeLock._type == TimeLockType.UpdateVault) {
            address _vault = abi.decode(timeLock.params, (address));
            vault = _vault;

            emit UpdateVault(_vault);
        } else {
            revert InvalidTimeLockType();
        }
    }

    function wrap(address to, uint256 amount, uint256 minAmount, uint128 gasLimit) external payable nonReentrant {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        _transferFrom(address(0), to, amount);

        uint256 balance = address(this).balance;

        ERC20(underlying).approve(vault, amount);
        IStakingVault(vault).deposit{ value: msg.value }(underlying, amount, minAmount, gasLimit, msg.sender);
        ERC20(underlying).approve(vault, 0);

        // refund remainder
        if (address(this).balance > balance - msg.value) {
            AddressLib.transferNative(msg.sender, address(this).balance - balance + msg.value);
        }

        emit Wrap(amount);
    }

    function unwrap(address to, uint256 amount, uint128 readGasLimit, uint128 withdrawGasLimit, uint256 withdrawFee)
        external
        payable
        nonReentrant
        returns (MessagingReceipt memory receipt)
    {
        if (to == address(0)) revert InvalidAddress();

        receipt = _transfer(
            msg.sender, address(0), amount, abi.encode(msg.sender, withdrawGasLimit), withdrawFee, readGasLimit
        );

        emit Unwrap(to, amount);
    }

    function _executePendingTransfer(PendingTransfer memory pending) internal override {
        // only when transferred by unwrap()
        if (pending.from != address(0) && pending.to == address(0)) {
            (address to, uint128 gasLimit) = abi.decode(pending.callData, (address, uint128));
            bytes memory data = abi.encode(pending.from, to);
            try IStakingVault(vault).withdraw{ value: pending.value }(
                underlying, pending.amount, data, gasLimit, pending.from
            ) { } catch (bytes memory reason) {
                uint256 id = failedWithdrawals.length;
                failedWithdrawals.push(FailedWithdrawal(false, pending.amount, data, pending.value));
                emit WithdrawFail(id, reason);
            }
        } else {
            super._executePendingTransfer(pending);
        }
    }

    function retryWithdraw(uint256 id, uint128 gasLimit) external payable {
        FailedWithdrawal storage withdrawal = failedWithdrawals[id];
        if (withdrawal.resolved) revert InvalidId();

        withdrawal.resolved = true;

        IStakingVault(vault).withdraw{ value: withdrawal.value + msg.value }(
            underlying, withdrawal.amount, withdrawal.data, gasLimit, msg.sender
        );
    }

    // IStakingVaultCallbacks
    function onWithdraw(address, uint256 amount, bytes calldata data) external {
        if (msg.sender != vault) revert Forbidden();

        (address from, address to) = abi.decode(data, (address, address));
        _transferFrom(from, address(0), amount);
        ERC20(underlying).safeTransferFrom(msg.sender, to, amount);
    }
}
