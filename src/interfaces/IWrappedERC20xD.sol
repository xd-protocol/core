// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface IWrappedERC20xD is IBaseERC20xD {
    function underlying() external view returns (address);

    function wrap(address to, uint256 amount) external payable;

    function unwrap(address to, uint256 amount, bytes memory data) external payable returns (bytes32 guid);

    fallback() external payable;
    receive() external payable;
}
