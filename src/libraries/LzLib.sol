// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

library LzLib {
    using BytesLib for bytes;

    error InvalidOptions();

    function isValidOptions(bytes memory options) internal pure returns (bool) {
        return options.length == 32;
    }

    function encodeOptions(uint96 gasLimit, address refundTo) internal pure returns (bytes memory) {
        return abi.encodePacked(gasLimit, refundTo);
    }

    function decodeOptions(bytes memory options) internal pure returns (uint96 gasLimit, address refundTo) {
        if (!isValidOptions(options)) revert InvalidOptions();

        return (uint96(bytes12(options.slice(0, 12))), address(bytes20(options.slice(12, 20))));
    }
}
