// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { BaseERC20xD } from "./mixins/BaseERC20xD.sol";

contract ERC20xD is BaseERC20xD {
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _liquidityMatrix, address _owner)
        BaseERC20xD(_name, _symbol, _decimals, _liquidityMatrix, _owner)
    { }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function quoteBurn(address from, uint128 gasLimit) public view returns (uint256 fee) {
        return quoteTransfer(from, gasLimit);
    }

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
        _transferFrom(address(0), to, amount);
    }

    /**
     * @notice Burns tokens by transferring them to the zero address.
     * @param amount The amount of tokens to burn.
     * @param options Additional options for the transfer call.
     * @dev This function should be called by derived contracts with appropriate access control.
     */
    function burn(uint256 amount, bytes calldata options) external payable returns (MessagingReceipt memory receipt) {
        return _transfer(msg.sender, address(0), amount, "", 0, options);
    }
}
