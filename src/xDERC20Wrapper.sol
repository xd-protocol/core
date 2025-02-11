// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BasexDERC20 } from "./mixins/BasexDERC20.sol";
import { IRebalancer, IRebalancerCallbacks } from "./interfaces/IRebalancer.sol";

contract xDERC20 is BasexDERC20, IRebalancerCallbacks {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable underlying;
    address public immutable rebalancer;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _underlying,
        address _rebalancer,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _synchronizer,
        address _owner
    ) BasexDERC20(_name, _symbol, _decimals, _synchronizer, _owner) {
        underlying = _underlying;
        rebalancer = _rebalancer;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function wrap(address to, uint256 amount) external {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        ERC20(underlying).approve(rebalancer, amount);
        IRebalancer(rebalancer).deposit(underlying, msg.sender, amount);
        ERC20(underlying).approve(rebalancer, 0);

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
