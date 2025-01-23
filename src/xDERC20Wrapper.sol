// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { BasexDERC20 } from "./mixins/BasexDERC20.sol";

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
        address _synchronizer,
        address _owner
    ) BasexDERC20(_name, _symbol, _decimals, _synchronizer, _owner) {
        underlying = _underlying;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    function wrap(address to, uint256 amount) external {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        _transfer(address(0), to, amount);
    }

    function unwrap(address to, uint256 amount, uint128 gasLimit) external returns (MessagingReceipt memory receipt) {
        return transfer(address(0), amount, abi.encode(to), gasLimit);
    }

    function _onTransfer(uint256 nonce, int256 globalAvailability) internal override {
        super._onTransfer(nonce, globalAvailability);

        PendingTransfer storage pending = _pendingTransfers[nonce];
        if (pending.from != address(0) && pending.to == address(0)) {
            ERC20(underlying).safeTransfer(abi.decode(pending.callData, (address)), pending.amount);
        }
    }
}
