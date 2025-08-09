// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IERC20xDHook } from "../interfaces/IERC20xDHook.sol";

/**
 * @title BaseERC20xDHook
 * @notice Abstract base contract for implementing ERC20xD hooks with common functionality
 * @dev Provides base implementation for hooks that need to interact with ERC20xD tokens.
 *      Includes token reference storage and validation logic. Hooks can override transfer callbacks
 *      to implement custom logic like dividend distribution, vault integration, or other mechanisms.
 */
abstract contract BaseERC20xDHook is IERC20xDHook {
    /// @notice The ERC20xD token this hook is attached to
    address public immutable token;

    error Forbidden();
    error InvalidToken();

    constructor(address _token) {
        if (_token == address(0)) revert InvalidToken();

        token = _token;
    }

    function onInitiateTransfer(
        address from,
        address to,
        uint256 amount,
        bytes memory callData,
        uint256 value,
        bytes memory data
    ) external { }

    function onReadGlobalAvailability(address account, int256 globalAvailability) external virtual { }

    function beforeTransfer(address from, address to, uint256 amount, bytes memory data) external virtual { }

    function afterTransfer(address from, address to, uint256 amount, bytes memory data) external virtual { }

    function onMapAccounts(bytes32 chainUID, address remoteAccount, address localAccount) external virtual { }

    function onSettleLiquidity(bytes32 chainUID, uint256 timestamp, address account, int256 liquidity)
        external
        virtual
    { }

    function onSettleTotalLiquidity(bytes32 chainUID, uint256 timestamp, int256 totalLiquidity) external virtual { }

    function onSettleData(bytes32 chainUID, uint256 timestamp, bytes32 key, bytes memory value) external virtual { }
}
