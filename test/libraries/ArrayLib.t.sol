// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ArrayLib } from "../../src/libraries/ArrayLib.sol";

contract ArrayLibTest is Test {
    using ArrayLib for uint256[];

    uint256[] private testArray;

    function setUp() public {
        // Reset array before each test
        delete testArray;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function assertArrayEquals(uint256[] memory a, uint256[] memory b) internal pure {
        require(a.length == b.length, "Array length mismatch");
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] == b[i], "Array element mismatch");
        }
    }

    function isSorted(uint256[] memory arr) internal pure returns (bool) {
        for (uint256 i = 1; i < arr.length; i++) {
            if (arr[i - 1] > arr[i]) {
                return false;
            }
        }
        return true;
    }
}
