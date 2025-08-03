// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../interfaces/IERC20xDHook.sol";

abstract contract BaseERC20xDHook is IERC20xDHook {
    function onInitiateTransfer(
        address from,
        address to,
        uint256 amount,
        bytes memory callData,
        uint256 value,
        bytes memory data
    ) external { }

    function onReadGlobalAvailability(address account, int256 globalAvailability) external { }

    function beforeTransfer(address from, address to, uint256 amount) external { }

    function afterTransfer(address from, address to, uint256 amount) external { }
}
