// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseERC20xD } from "./IBaseERC20xD.sol";

interface IERC20xD is IBaseERC20xD {
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Quotes the fee for burning tokens (cross-chain transfer to zero address)
     * @param from The address burning the tokens
     * @param gasLimit The gas limit for the cross-chain operation
     * @return fee The estimated fee for the burn operation
     */
    function quoteBurn(address from, uint128 gasLimit) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints tokens by transferring from the zero address
     * @param to The recipient address of the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns tokens by transferring them to the zero address with cross-chain availability check
     * @param amount The amount of tokens to burn
     * @param data Encoded (uint128 gasLimit, address refundTo) parameters for cross-chain operations
     * @return guid The unique identifier for this cross-chain operation
     */
    function burn(uint256 amount, bytes calldata data) external payable returns (bytes32 guid);

    /**
     * @notice Receive function to accept Ether transfers
     */
    receive() external payable;
}
