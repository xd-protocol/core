// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IRebalancer } from "../interfaces/IRebalancer.sol";

contract IdleRebalancer is IRebalancer {
    using SafeTransferLib for ERC20;

    mapping(address account => mapping(address underlying => uint256)) public canWithdraw;

    function deposit(address underlying, uint256 amount) external {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        canWithdraw[msg.sender][underlying] += amount;
    }

    function withdraw(address underlying, uint256 amount) external {
        canWithdraw[msg.sender][underlying] -= amount;

        ERC20(underlying).safeTransfer(msg.sender, amount);
    }
}
