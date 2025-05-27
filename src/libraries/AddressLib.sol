// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library AddressLib {
    error TransferFailure(bytes data);

    /**
     * @notice Utility function to check if an address is a contract.
     * @param account The address to check.
     * @return True if the address is a contract, false otherwise.
     */
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function transferNative(address to, uint256 amount) internal {
        (bool ok, bytes memory data) = to.call{ value: amount }("");
        if (!ok) revert TransferFailure(data);
    }
}
