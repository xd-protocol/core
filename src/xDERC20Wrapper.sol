// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BasexDERC20 } from "./mixins/BasexDERC20.sol";
import { IRebalancer, IRebalancerCallbacks } from "./interfaces/IRebalancer.sol";

contract xDERC20 is BasexDERC20, IRebalancerCallbacks {
    using SafeTransferLib for ERC20;

    enum TimeLockType {
        Invalid,
        UpdateTimeLockPeriod,
        UpdateRebalancer
    }

    struct TimeLock {
        TimeLockType _type;
        bytes params;
        uint64 startedAt;
        bool executed;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable underlying;

    uint64 public timeLockPeriod;
    TimeLock[] public timeLocks;

    address rebalancer;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event QueueTimeLock(uint256 indexed id, TimeLockType _type, uint64 timestamp);
    event ExecuteTimeLock(uint256 indexed id);
    event UpdateTimeLockPeriod(uint64 timeLockPeriod);
    event UpdateRebalancer(address indexed rebalancer);
    event Rebalance(uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TimeLockExecuted();
    error TimeNotPassed();
    error InvalidTimeLockType();
    error TransferFailure(bytes data);
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

    function queueUpdateTimeLockPeriod(uint64 _timeLockPeriod) external onlyOwner {
        _queueTimeLock(TimeLockType.UpdateTimeLockPeriod, abi.encode(_timeLockPeriod));
    }

    function queueUpdateRebalancer(address _rebalancer) external onlyOwner {
        _queueTimeLock(TimeLockType.UpdateRebalancer, abi.encode(_rebalancer));
    }

    function _queueTimeLock(TimeLockType _type, bytes memory params) internal {
        if (_type != TimeLockType.UpdateTimeLockPeriod && _type != TimeLockType.UpdateRebalancer) {
            revert InvalidTimeLockType();
        }

        uint256 id = timeLocks.length;
        timeLocks.push(TimeLock(_type, params, uint64(block.timestamp), false));

        emit QueueTimeLock(id, _type, uint64(block.timestamp));
    }

    function executeTimeLock(uint256 id) external payable {
        TimeLock storage timeLock = timeLocks[id];
        if (timeLock.executed) revert TimeLockExecuted();
        if (block.timestamp < timeLock.startedAt + timeLockPeriod) revert TimeNotPassed();

        emit ExecuteTimeLock(id);

        if (timeLock._type == TimeLockType.UpdateTimeLockPeriod) {
            timeLockPeriod = abi.decode(timeLock.params, (uint64));

            emit UpdateTimeLockPeriod(timeLockPeriod);
        } else if (timeLock._type == TimeLockType.UpdateRebalancer) {
            address _rebalancer = abi.decode(timeLock.params, (address));
            rebalancer = _rebalancer;

            emit UpdateRebalancer(_rebalancer);
        } else {
            revert InvalidTimeLockType();
        }
    }

    function rebalance(uint256 amount, bytes calldata extra) external payable onlyOwner {
        ERC20(underlying).approve(rebalancer, amount);
        uint256 balance = address(this).balance;
        IRebalancer(rebalancer).rebalance{ value: msg.value }(underlying, amount, extra);
        // refund remainder
        if (address(this).balance > balance) {
            (bool ok, bytes memory data) = msg.sender.call{ value: address(this).balance - balance }("");
            if (!ok) revert TransferFailure(data);
        }
        ERC20(underlying).approve(rebalancer, 0);

        emit Rebalance(amount);
    }

    function wrap(address to, uint256 amount) external {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        _transferFrom(address(0), to, amount);
    }

    function unwrap(address to, uint256 amount, uint128 gasLimit) external returns (MessagingReceipt memory receipt) {
        return _transfer(address(0), amount, abi.encode(to), 0, gasLimit);
    }

    function _onTransfer(uint256 nonce, int256 globalAvailability) internal override {
        super._onTransfer(nonce, globalAvailability);

        PendingTransfer storage pending = _pendingTransfers[nonce];
        // only when transferred by unwrap()
        if (pending.from != address(0) && pending.to == address(0)) {
            address to = abi.decode(pending.callData, (address));
            IRebalancer(rebalancer).withdraw(underlying, to, pending.amount);
        }
    }

    // IRebalancerCallbacks
    function onWithdraw(address asset, address to, uint256 amount) external {
        if (msg.sender != rebalancer) revert Forbidden();

        ERC20(asset).safeTransferFrom(msg.sender, to, amount);
    }
}
