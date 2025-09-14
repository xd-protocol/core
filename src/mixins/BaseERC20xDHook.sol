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

    function onReadGlobalAvailability(address, int256) external virtual { }

    function beforeTransfer(address, address, uint256, bytes memory) external virtual { }

    function afterTransfer(address, address, uint256, bytes memory) external virtual { }

    function onMapAccounts(bytes32, address, address) external virtual { }

    function onSettleLiquidity(bytes32, uint256, address, int256) external virtual { }

    function onSettleTotalLiquidity(bytes32, uint256, int256) external virtual { }

    function onSettleData(bytes32, uint256, bytes32, bytes memory) external virtual { }

    function onWrap(address, address, uint256 amount) external payable virtual returns (uint256) {
        return amount;
    }

    function onUnwrap(address, address, uint256 shares) external virtual returns (uint256) {
        return shares;
    }
}
