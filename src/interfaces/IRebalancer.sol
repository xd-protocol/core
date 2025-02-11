// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRebalancerCallbacks {
    function onWithdraw(address asset, address to, uint256 amount) external;
}

interface IRebalancer {
    event Deposit(address indexed asset, address indexed to, uint256 amount);

    event Withdraw(address indexed asset, address indexed to, uint256 amount);

    function deposit(address asset, address to, uint256 amount) external;

    function withdraw(address asset, address to, uint256 amount) external;
}
