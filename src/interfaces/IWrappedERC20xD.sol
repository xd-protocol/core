// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface IWrappedERC20xD is IBaseERC20xD {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 shares, uint256 assets);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the underlying ERC20 token address
     * @return The address of the underlying token
     */
    function underlying() external view returns (address);

    /**
     * @notice Quotes the fee for unwrapping tokens
     * @param gasLimit The gas limit for the cross-chain operation
     * @return fee The fee required for the unwrap operation
     */
    function quoteUnwrap(uint128 gasLimit) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Wraps underlying tokens into xD tokens
     * @param to The recipient of the wrapped tokens
     * @param amount The amount of underlying tokens to wrap
     * @param hookData Custom data to pass to the onWrap hook
     */
    function wrap(address to, uint256 amount, bytes memory hookData) external payable;

    /**
     * @notice Unwraps xD tokens back to underlying tokens
     * @param to The recipient of the underlying tokens
     * @param amount The amount of xD tokens to unwrap
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters for cross-chain operations
     * @param hookData Custom data to pass to the onUnwrap hook
     * @return guid The unique identifier for this unwrap operation
     */
    function unwrap(address to, uint256 amount, bytes memory data, bytes memory hookData)
        external
        payable
        returns (bytes32 guid);

    /**
     * @notice Fallback function to receive Ether
     */
    fallback() external payable;
    /**
     * @notice Receive function to accept Ether transfers
     */
    receive() external payable;
}
