// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library ArrayLib {
    /**
     * @notice Converts an array of `address` values into an array of `bytes32`.
     * @param values The array of `address` values to be converted.
     * @return result The array of `bytes32` values.
     */
    function convertToBytes32(address[] memory values) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](values.length); // Allocate memory for the result array
        for (uint256 i; i < values.length; i++) {
            unchecked {
                result[i] = bytes32(uint256(uint160(values[i]))); // Convert address to bytes32
            }
        }
        return result;
    }

    /**
     * @notice Converts an array of `int256` values into an array of `bytes32`.
     * @param values The array of `int256` values to be converted.
     * @return result The array of `bytes32` values.
     */
    function convertToBytes32(int256[] memory values) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](values.length); // Allocate memory for the result array
        for (uint256 i; i < values.length; i++) {
            unchecked {
                result[i] = bytes32(uint256(values[i])); // Convert int256 to bytes32
            }
        }
        return result;
    }

    function hashElements(bytes[] memory values) internal pure returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](values.length); // Allocate memory for the result array
        for (uint256 i; i < values.length; i++) {
            unchecked {
                result[i] = keccak256(values[i]); // Hash value
            }
        }
        return result;
    }
}
