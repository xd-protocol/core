// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library AddressLib {
    error TransferFailure(bytes data);

    function transferNative(address to, uint256 amount) internal {
        (bool ok, bytes memory data) = to.call{ value: amount }("");
        if (!ok) revert TransferFailure(data);
    }
}
