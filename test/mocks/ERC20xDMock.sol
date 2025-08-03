// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";

contract ERC20xDMock is BaseERC20xD {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner
    ) BaseERC20xD(_name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner) { }

    function testTransferFrom(address from, address to, uint256 amount) external returns (bool) {
        // Directly call _transferFrom which handles hooks
        _transferFrom(from, to, amount);
        return true;
    }

    // Simple transfer without hooks for debugging
    function simpleTransfer(address from, address, uint256 amount) external {
        if (from != address(0)) {
            int256 fromBalance = ILiquidityMatrix(liquidityMatrix).getLocalLiquidity(address(this), from);
            ILiquidityMatrix(liquidityMatrix).updateLocalLiquidity(from, fromBalance - int256(amount));
        }
    }

    function testOnReadGlobalAvailability(uint256 nonce, int256 globalAvailability) external {
        _onReadGlobalAvailability(nonce, globalAvailability);
    }

    function testExecutePendingTransfer(PendingTransfer memory pending) external {
        _executePendingTransfer(pending);
    }
}
