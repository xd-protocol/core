// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRebalancerCallbacks {
    function onWithdraw(address asset, address to, uint256 amount) external;
}

interface IRebalancer {
    event Rebalance(address indexed asset, uint256 amount);

    event Withdraw(address indexed asset, address indexed to, uint256 amount);

    function rebalance(address asset, uint256 amount, bytes calldata extra) external payable;

    function withdraw(address asset, address to, uint256 amount) external;
}
