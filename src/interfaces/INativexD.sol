// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface INativexD is IBaseERC20xD {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error LiquidityCapExceeded(address account, uint256 currentWrapped, uint256 attemptedAmount, uint256 cap);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 shares, uint256 assets);
    event LiquidityCapUpdated(uint256 newCap);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the underlying native token address (typically address(0) for ETH)
     * @return The address of the underlying native token
     */
    function underlying() external view returns (address);

    /**
     * @notice Quotes the fee for unwrapping tokens
     * @param gasLimit The gas limit for the cross-chain operation
     * @return fee The fee required for the unwrap operation
     */
    function quoteUnwrap(uint128 gasLimit) external view returns (uint256);

    /**
     * @notice Returns the current liquidity cap (0 means unlimited)
     * @return The maximum amount of tokens that can be wrapped per account
     */
    function liquidityCap() external view returns (uint256);

    /**
     * @notice Returns the amount of tokens wrapped by an account
     * @return The current wrapped balance for the account
     */
    function wrappedAmount(address account) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Wraps native currency into xD tokens
     * @param to The recipient of the wrapped tokens
     * @param hookData Custom data to pass to the onWrap hook
     */
    function wrap(address to, bytes memory hookData) external payable;

    /**
     * @notice Unwraps xD tokens back to native currency
     * @param to The recipient of the native currency
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
     * @notice Sets the liquidity cap for wrapped tokens per account (owner only)
     * @param newCap The new liquidity cap (0 for unlimited)
     */
    function setLiquidityCap(uint256 newCap) external;

    /**
     * @notice Receive function to accept Ether transfers
     */
    receive() external payable;
}
