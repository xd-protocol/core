// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStaker {
    function stake(uint256 amount) external payable;

    function unstake(uint256 amount) external;
}
