// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface IWrappedERC20xD is IBaseERC20xD {
    /**
     * @notice Returns the underlying ERC20 token address
     * @return The address of the underlying token
     */
    function underlying() external view returns (address);

    /**
     * @notice Wraps underlying tokens into xD tokens
     * @param to The recipient of the wrapped tokens
     * @param amount The amount of underlying tokens to wrap
     */
    function wrap(address to, uint256 amount) external payable;

    /**
     * @notice Unwraps xD tokens back to underlying tokens
     * @param to The recipient of the underlying tokens
     * @param amount The amount of xD tokens to unwrap
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters for cross-chain operations
     * @return guid The unique identifier for this unwrap operation
     */
    function unwrap(address to, uint256 amount, bytes memory data) external payable returns (bytes32 guid);

    fallback() external payable;
    receive() external payable;
}
