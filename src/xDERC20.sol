// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

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

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(amount);
    }
}
