// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IRebalancer, IRebalancerCallbacks } from "../interfaces/IRebalancer.sol";

contract IdleRebalancer is IRebalancer {
    using SafeTransferLib for ERC20;

    mapping(address account => mapping(address asset => uint256)) public canWithdraw;

    function deposit(address asset, address to, uint256 amount) external {
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        canWithdraw[to][asset] += amount;

        emit Deposit(asset, to, amount);
    }

    function withdraw(address asset, address to, uint256 amount) external {
        canWithdraw[msg.sender][asset] -= amount;

        emit Withdraw(asset, to, amount);

        ERC20(asset).approve(msg.sender, amount);
        IRebalancerCallbacks(msg.sender).onWithdraw(asset, to, amount);
        ERC20(asset).approve(msg.sender, 0);
    }
}
