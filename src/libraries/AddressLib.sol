// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library AddressLib {
    /**
     * @notice Utility function to check if an address is a contract.
     * @param account The address to check.
     * @return True if the address is a contract, false otherwise.
     */
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
