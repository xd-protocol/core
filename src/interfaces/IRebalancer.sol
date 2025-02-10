// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRebalancer {
    function deposit(address underlying, uint256 amount) external;

    function withdraw(address underlying, uint256 amount) external;
}
