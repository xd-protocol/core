// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface INativexD is IBaseERC20xD {
    /**
     * @notice Returns the underlying native token address (typically address(0) for ETH)
     * @return The address of the underlying native token
     */
    function underlying() external view returns (address);

    /**
     * @notice Wraps native currency into xD tokens
     * @param to The recipient of the wrapped tokens
     */
    function wrap(address to) external payable;

    /**
     * @notice Unwraps xD tokens back to native currency
     * @param to The recipient of the native currency
     * @param amount The amount of xD tokens to unwrap
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters for cross-chain operations
     * @return guid The unique identifier for this unwrap operation
     */
    function unwrap(address to, uint256 amount, bytes memory data) external payable returns (bytes32 guid);

    fallback() external payable;
    receive() external payable;
}
