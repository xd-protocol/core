// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { BasexDERC20 } from "./mixins/BasexDERC20.sol";

contract xDERC20 is BasexDERC20 {
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _synchronizer, address _owner)
        BasexDERC20(_name, _symbol, _decimals, _synchronizer, _owner)
    { }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints tokens.
     * @param to The recipient address of the minted tokens.
     * @param amount The amount of tokens to mint.
     * @dev This function should be called by derived contracts with appropriate access control.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _transfer(address(0), to, amount);
    }

    /**
     * @notice Burns tokens by transferring them to the zero address.
     * @param amount The amount of tokens to burn.
     * @param gasLimit The gas limit to allocate for actual transfer after lzRead.
     * @dev This function should be called by derived contracts with appropriate access control.
     */
    function burn(uint256 amount, uint128 gasLimit) external payable returns (MessagingReceipt memory receipt) {
        return transfer(address(0), amount, gasLimit);
    }
}
