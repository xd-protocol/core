// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

/**
 * @title AddressLib
 * @notice Library providing low-level address and native currency transfer utilities
 * @dev Contains functions for safe native currency transfers using low-level calls.
 *      Designed to handle native transfers in cross-chain token operations and unwrapping scenarios.
 *      Provides proper error handling for failed transfers.
 */
library AddressLib {
    error TransferFailure(bytes data);

    /**
     * @notice Transfers native currency to a specified address
     * @param to The recipient address
     * @param amount The amount of native currency to transfer
     * @dev Uses low-level call to handle transfer, reverts with TransferFailure on failure
     */
    function transferNative(address to, uint256 amount) internal {
        (bool ok, bytes memory data) = to.call{ value: amount }("");
        if (!ok) revert TransferFailure(data);
    }
}
