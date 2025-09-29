// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ArrayLib } from "../../src/libraries/ArrayLib.sol";

contract ArrayLibTest is Test {
    using ArrayLib for uint256[];

    uint256[] internal values;
    uint256[] internal indices;

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Reset arrays for each test
        delete values;
        delete indices;
    }

    /*//////////////////////////////////////////////////////////////
                    EXISTING FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_last_emptyArray() public view {
        assertEq(values.last(), 0);
    }

    function test_last_singleElement() public {
        values.push(100);
        assertEq(values.last(), 100);
    }

    function test_last_multipleElements() public {
        values.push(100);
        values.push(200);
        values.push(300);
        assertEq(values.last(), 300);
    }

    function test_findFloor_emptyArray() public view {
        assertEq(values.findFloor(100), 0);
    }

    function test_findFloor_sortedArray() public {
        values.push(100);
        values.push(200);
        values.push(300);

        assertEq(values.findFloor(50), 0);
        assertEq(values.findFloor(100), 100);
        assertEq(values.findFloor(150), 100);
        assertEq(values.findFloor(200), 200);
        assertEq(values.findFloor(250), 200);
        assertEq(values.findFloor(300), 300);
        assertEq(values.findFloor(350), 300);
    }
}
