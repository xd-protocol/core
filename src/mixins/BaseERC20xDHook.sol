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

    function beforeTransfer(address from, address to, uint256 amount, bytes memory data) external { }

    function afterTransfer(address from, address to, uint256 amount, bytes memory data) external { }

    function onMapAccounts(uint32 eid, address remoteAccount, address localAccount) external { }

    function onSettleLiquidity(uint32 eid, uint256 timestamp, address account, int256 liquidity) external { }

    function onSettleTotalLiquidity(uint32 eid, uint256 timestamp, int256 totalLiquidity) external { }

    function onSettleData(uint32 eid, uint256 timestamp, bytes32 key, bytes memory value) external { }
}
