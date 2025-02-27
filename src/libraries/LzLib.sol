// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

library LzLib {
    using BytesLib for bytes;

    error InvalidOptions();

    function encodeOptions(uint96 gasLimit, address refundTo) internal pure returns (bytes memory) {
        return abi.encodePacked(gasLimit, refundTo);
    }

    function decodeOptions(bytes memory options) internal pure returns (uint96 gasLimit, address refundTo) {
        if (options.length != 32) revert InvalidOptions();

        return (uint96(bytes12(options.slice(0, 96))), address(bytes20(options.slice(96, 160))));
    }
}
