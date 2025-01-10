// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BasexDERC20 } from "./mixins/BasexDERC20.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

contract xDERC20 is BasexDERC20 {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable underlying;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _owner
    ) BasexDERC20(_name, _symbol, _decimals, _liquidityMatrix, _owner) {
        underlying = _underlying;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        _burn(amount);

        ERC20(underlying).safeTransfer(to, amount);
    }
}
