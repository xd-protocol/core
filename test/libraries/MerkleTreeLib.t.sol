// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";

contract MerkleTreeLibTest is Test {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    MerkleTreeLib.Tree tree;
    MerkleTreeLib.Tree tree2;

    function test_initialize() public view {
        assertEq(tree.root, bytes32(0));
        assertEq(tree.size, 0);
    }

    function test_update(uint256 seed) public {
        bytes32 random = keccak256(abi.encodePacked(seed));
        for (uint256 i; i < 1000; ++i) {
            tree.update(random, keccak256(abi.encodePacked(random)));
            random = keccak256(abi.encodePacked(random, i));
        }
        assertEq(tree.size, 1000);
    }

    function test_computeRoot(uint256 seed) public {
        uint256 size = seed % 1000;

        bytes32[] memory keys = new bytes32[](size);
        bytes32[] memory values = new bytes32[](size);

        bytes32 random = keccak256(abi.encodePacked(seed));
        for (uint256 i; i < size; ++i) {
            bytes32 key = keccak256(abi.encodePacked(random, i));
            bytes32 value = keccak256(abi.encodePacked(key, i));
            tree.update(key, value);
            keys[i] = key;
            values[i] = value;
            random = keccak256(abi.encodePacked(value, i));
        }

        bytes32 updated = tree.root;
        bytes32 computed = MerkleTreeLib.computeRoot(keys, values);
        assertEq(updated, computed);
    }

    function test_verifyProof(uint256 seed) public pure {
        uint256 size = 1000;
        bytes32 random = keccak256(abi.encodePacked("RANDOM"));

        bytes32[] memory keys = new bytes32[](size);
        bytes32[] memory values = new bytes32[](size);
        for (uint256 i; i < size; ++i) {
            keys[i] = random;
            values[i] = keccak256(abi.encodePacked(keys[i], i));
            random = keccak256(abi.encodePacked(values[i], i));
        }

        uint256 index = seed % size;
        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, index);
        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        assertTrue(MerkleTreeLib.verifyProof(keys[index], values[index], index, proof, root));
    }
}
