// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";

contract MerkleTreeLibTest is Test {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    MerkleTreeLib.Tree tree;
    MerkleTreeLib.Tree tree2;

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize() public view {
        assertEq(tree.root, bytes32(0));
        assertEq(tree.size, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_update_singleNode() public {
        bytes32 key = keccak256("key1");
        bytes32 value = keccak256("value1");

        uint256 index = tree.update(key, value);

        assertEq(index, 0);
        assertEq(tree.size, 1);
        assertEq(tree.root, keccak256(abi.encodePacked(key, value)));
    }

    function test_update_multipleNodes() public {
        bytes32[] memory keys = new bytes32[](3);
        bytes32[] memory values = new bytes32[](3);

        keys[0] = keccak256("key1");
        keys[1] = keccak256("key2");
        keys[2] = keccak256("key3");

        values[0] = keccak256("value1");
        values[1] = keccak256("value2");
        values[2] = keccak256("value3");

        for (uint256 i = 0; i < 3; i++) {
            tree.update(keys[i], values[i]);
        }

        assertEq(tree.size, 3);
        assertEq(tree.root, MerkleTreeLib.computeRoot(keys, values));
    }

    function test_update_duplicateKey() public {
        bytes32 key = keccak256("key1");
        bytes32 value1 = keccak256("value1");
        bytes32 value2 = keccak256("value2");

        uint256 index1 = tree.update(key, value1);
        uint256 index2 = tree.update(key, value2);

        // Same key should return same index
        assertEq(index1, index2);
        assertEq(tree.size, 1);

        // Root should be updated with new value
        assertEq(tree.root, keccak256(abi.encodePacked(key, value2)));
    }

    function test_update_largeTree(uint256 seed) public {
        bytes32 random = keccak256(abi.encodePacked(seed));
        for (uint256 i; i < 1000; ++i) {
            tree.update(random, keccak256(abi.encodePacked(random)));
            random = keccak256(abi.encodePacked(random, i));
        }
        assertEq(tree.size, 1000);
    }

    function test_update_sequentialKeys() public {
        uint256 numKeys = 10;
        bytes32[] memory keys = new bytes32[](numKeys);
        bytes32[] memory values = new bytes32[](numKeys);

        for (uint256 i = 0; i < numKeys; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
            tree.update(keys[i], values[i]);
        }

        assertEq(tree.size, numKeys);
        assertEq(tree.root, MerkleTreeLib.computeRoot(keys, values));
    }

    /*//////////////////////////////////////////////////////////////
                          COMPUTE ROOT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_computeRoot_emptyTree() public {
        bytes32[] memory keys = new bytes32[](0);
        bytes32[] memory values = new bytes32[](0);

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        assertEq(root, bytes32(0));
    }

    function test_computeRoot_singleNode() public {
        bytes32[] memory keys = new bytes32[](1);
        bytes32[] memory values = new bytes32[](1);

        keys[0] = keccak256("key1");
        values[0] = keccak256("value1");

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        assertEq(root, keccak256(abi.encodePacked(keys[0], values[0])));
    }

    function test_computeRoot_evenNumberOfNodes() public {
        bytes32[] memory keys = new bytes32[](4);
        bytes32[] memory values = new bytes32[](4);

        for (uint256 i = 0; i < 4; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);

        // Manually compute expected root
        bytes32 leaf0 = keccak256(abi.encodePacked(keys[0], values[0]));
        bytes32 leaf1 = keccak256(abi.encodePacked(keys[1], values[1]));
        bytes32 leaf2 = keccak256(abi.encodePacked(keys[2], values[2]));
        bytes32 leaf3 = keccak256(abi.encodePacked(keys[3], values[3]));

        bytes32 parent0 = keccak256(abi.encodePacked(leaf0, leaf1));
        bytes32 parent1 = keccak256(abi.encodePacked(leaf2, leaf3));

        bytes32 expectedRoot = keccak256(abi.encodePacked(parent0, parent1));
        assertEq(root, expectedRoot);
    }

    function test_computeRoot_oddNumberOfNodes() public {
        bytes32[] memory keys = new bytes32[](3);
        bytes32[] memory values = new bytes32[](3);

        for (uint256 i = 0; i < 3; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);

        // Manually compute expected root
        bytes32 leaf0 = keccak256(abi.encodePacked(keys[0], values[0]));
        bytes32 leaf1 = keccak256(abi.encodePacked(keys[1], values[1]));
        bytes32 leaf2 = keccak256(abi.encodePacked(keys[2], values[2]));

        bytes32 parent0 = keccak256(abi.encodePacked(leaf0, leaf1));
        bytes32 parent1 = keccak256(abi.encodePacked(leaf2, bytes32(0)));

        bytes32 expectedRoot = keccak256(abi.encodePacked(parent0, parent1));
        assertEq(root, expectedRoot);
    }

    function test_computeRoot_invalidLengths() public {
        bytes32[] memory keys = new bytes32[](2);
        bytes32[] memory values = new bytes32[](3);

        vm.expectRevert(MerkleTreeLib.InvalidLengths.selector);
        this.callComputeRoot(keys, values);
    }

    function test_computeRoot_matchesIncrementalUpdate(uint256 seed) public {
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

    /*//////////////////////////////////////////////////////////////
                           GET PROOF TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getProof_singleNode() public {
        bytes32[] memory keys = new bytes32[](1);
        bytes32[] memory values = new bytes32[](1);

        keys[0] = keccak256("key1");
        values[0] = keccak256("value1");

        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, 0);
        assertEq(proof.length, 0);
    }

    function test_getProof_twoNodes() public {
        bytes32[] memory keys = new bytes32[](2);
        bytes32[] memory values = new bytes32[](2);

        keys[0] = keccak256("key1");
        keys[1] = keccak256("key2");
        values[0] = keccak256("value1");
        values[1] = keccak256("value2");

        bytes32[] memory proof0 = MerkleTreeLib.getProof(keys, values, 0);
        bytes32[] memory proof1 = MerkleTreeLib.getProof(keys, values, 1);

        assertEq(proof0.length, 1);
        assertEq(proof1.length, 1);

        // Proof for index 0 should contain leaf at index 1
        assertEq(proof0[0], keccak256(abi.encodePacked(keys[1], values[1])));

        // Proof for index 1 should contain leaf at index 0
        assertEq(proof1[0], keccak256(abi.encodePacked(keys[0], values[0])));
    }

    function test_getProof_invalidIndex() public {
        bytes32[] memory keys = new bytes32[](2);
        bytes32[] memory values = new bytes32[](2);

        vm.expectRevert(MerkleTreeLib.IndexOutOfBounds.selector);
        this.callGetProof(keys, values, 2);
    }

    function test_getProof_invalidLengths() public {
        bytes32[] memory keys = new bytes32[](2);
        bytes32[] memory values = new bytes32[](3);

        vm.expectRevert(MerkleTreeLib.InvalidLengths.selector);
        this.callGetProof(keys, values, 0);
    }

    function test_getProof_powerOfTwo() public {
        uint256 size = 8; // Power of 2
        bytes32[] memory keys = new bytes32[](size);
        bytes32[] memory values = new bytes32[](size);

        for (uint256 i = 0; i < size; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        // Test proof for each leaf
        for (uint256 i = 0; i < size; i++) {
            bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, i);
            assertEq(proof.length, 3); // log2(8) = 3

            bytes32 root = MerkleTreeLib.computeRoot(keys, values);
            assertTrue(MerkleTreeLib.verifyProof(keys[i], values[i], i, proof, root));
        }
    }

    function test_getProof_nonPowerOfTwo() public {
        uint256 size = 7; // Not a power of 2
        bytes32[] memory keys = new bytes32[](size);
        bytes32[] memory values = new bytes32[](size);

        for (uint256 i = 0; i < size; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        // Test proof for each leaf
        for (uint256 i = 0; i < size; i++) {
            bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, i);
            assertEq(proof.length, 3); // ceil(log2(7)) = 3

            bytes32 root = MerkleTreeLib.computeRoot(keys, values);
            assertTrue(MerkleTreeLib.verifyProof(keys[i], values[i], i, proof, root));
        }
    }

    /*//////////////////////////////////////////////////////////////
                         VERIFY PROOF TESTS
    //////////////////////////////////////////////////////////////*/

    function test_verifyProof_validProof() public {
        bytes32[] memory keys = new bytes32[](4);
        bytes32[] memory values = new bytes32[](4);

        for (uint256 i = 0; i < 4; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, 1);

        assertTrue(MerkleTreeLib.verifyProof(keys[1], values[1], 1, proof, root));
    }

    function test_verifyProof_invalidProof() public {
        bytes32[] memory keys = new bytes32[](4);
        bytes32[] memory values = new bytes32[](4);

        for (uint256 i = 0; i < 4; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, 1);

        // Modify proof to make it invalid
        proof[0] = keccak256("invalid");

        assertFalse(MerkleTreeLib.verifyProof(keys[1], values[1], 1, proof, root));
    }

    function test_verifyProof_wrongKey() public {
        bytes32[] memory keys = new bytes32[](4);
        bytes32[] memory values = new bytes32[](4);

        for (uint256 i = 0; i < 4; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, 1);

        // Use wrong key
        assertFalse(MerkleTreeLib.verifyProof(keccak256("wrong"), values[1], 1, proof, root));
    }

    function test_verifyProof_wrongValue() public {
        bytes32[] memory keys = new bytes32[](4);
        bytes32[] memory values = new bytes32[](4);

        for (uint256 i = 0; i < 4; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, 1);

        // Use wrong value
        assertFalse(MerkleTreeLib.verifyProof(keys[1], keccak256("wrong"), 1, proof, root));
    }

    function test_verifyProof_wrongIndex() public {
        bytes32[] memory keys = new bytes32[](4);
        bytes32[] memory values = new bytes32[](4);

        for (uint256 i = 0; i < 4; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, 1);

        // Use wrong index
        assertFalse(MerkleTreeLib.verifyProof(keys[1], values[1], 2, proof, root));
    }

    function test_verifyProof_wrongRoot() public {
        bytes32[] memory keys = new bytes32[](4);
        bytes32[] memory values = new bytes32[](4);

        for (uint256 i = 0; i < 4; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, 1);

        // Use wrong root
        assertFalse(MerkleTreeLib.verifyProof(keys[1], values[1], 1, proof, keccak256("wrong root")));
    }

    function test_verifyProof_emptyProof() public {
        bytes32[] memory keys = new bytes32[](1);
        bytes32[] memory values = new bytes32[](1);

        keys[0] = keccak256("key1");
        values[0] = keccak256("value1");

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        bytes32[] memory proof = new bytes32[](0);

        // For single node, empty proof should work
        assertTrue(MerkleTreeLib.verifyProof(keys[0], values[0], 0, proof, root));
    }

    function test_verifyProof_fuzz(uint256 seed) public {
        uint256 size = (seed % 100) + 1; // 1 to 100 nodes
        bytes32 random = keccak256(abi.encodePacked("RANDOM", seed));

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

    /*//////////////////////////////////////////////////////////////
                          EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_largeTree_gasConsumption() public {
        uint256 size = 256;
        bytes32[] memory keys = new bytes32[](size);
        bytes32[] memory values = new bytes32[](size);

        for (uint256 i = 0; i < size; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
        }

        // Measure gas for computing root
        uint256 gasStart = gasleft();
        bytes32 root = MerkleTreeLib.computeRoot(keys, values);
        uint256 gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas used for computing root of 256 nodes", gasUsed);

        // Measure gas for getting proof
        gasStart = gasleft();
        bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, 128);
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas used for getting proof from 256 nodes", gasUsed);

        // Measure gas for verifying proof
        gasStart = gasleft();
        bool valid = MerkleTreeLib.verifyProof(keys[128], values[128], 128, proof, root);
        gasUsed = gasStart - gasleft();
        emit log_named_uint("Gas used for verifying proof", gasUsed);

        assertTrue(valid);
    }

    function test_consecutiveUpdates_maintainsConsistency() public {
        bytes32[] memory keys = new bytes32[](5);
        bytes32[] memory values = new bytes32[](5);

        // Add nodes one by one and verify consistency
        for (uint256 i = 0; i < 5; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
            tree.update(keys[i], values[i]);

            // Create arrays for computeRoot with only added elements
            bytes32[] memory partialKeys = new bytes32[](i + 1);
            bytes32[] memory partialValues = new bytes32[](i + 1);

            for (uint256 j = 0; j <= i; j++) {
                partialKeys[j] = keys[j];
                partialValues[j] = values[j];
            }

            // Verify root matches computed root
            assertEq(tree.root, MerkleTreeLib.computeRoot(partialKeys, partialValues));
        }
    }

    function test_updateExistingValue_preservesTreeStructure() public {
        uint256 size = 10;
        bytes32[] memory keys = new bytes32[](size);
        bytes32[] memory values = new bytes32[](size);

        // Initial tree setup
        for (uint256 i = 0; i < size; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32((i + 1) * 100);
            tree.update(keys[i], values[i]);
        }

        // Update middle value
        bytes32 newValue = bytes32(uint256(999));
        tree.update(keys[5], newValue);
        values[5] = newValue;

        // Verify root matches computed root with updated value
        assertEq(tree.root, MerkleTreeLib.computeRoot(keys, values));
        assertEq(tree.size, size); // Size should not change
    }

    function test_allZeroValues() public {
        uint256 size = 4;
        bytes32[] memory keys = new bytes32[](size);
        bytes32[] memory values = new bytes32[](size);

        for (uint256 i = 0; i < size; i++) {
            keys[i] = bytes32(i + 1);
            values[i] = bytes32(0); // All zero values
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);

        // Verify proofs work with zero values
        for (uint256 i = 0; i < size; i++) {
            bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, i);
            assertTrue(MerkleTreeLib.verifyProof(keys[i], values[i], i, proof, root));
        }
    }

    function test_identicalKeys_differentValues() public {
        uint256 size = 4;
        bytes32[] memory keys = new bytes32[](size);
        bytes32[] memory values = new bytes32[](size);

        bytes32 sameKey = keccak256("same_key");

        for (uint256 i = 0; i < size; i++) {
            keys[i] = sameKey; // All same keys
            values[i] = bytes32(i + 1); // Different values
        }

        bytes32 root = MerkleTreeLib.computeRoot(keys, values);

        // Even with identical keys, proofs should work
        for (uint256 i = 0; i < size; i++) {
            bytes32[] memory proof = MerkleTreeLib.getProof(keys, values, i);
            assertTrue(MerkleTreeLib.verifyProof(keys[i], values[i], i, proof, root));
        }
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Helper functions to make calls external for expectRevert
    function callComputeRoot(bytes32[] memory keys, bytes32[] memory values) external pure returns (bytes32) {
        return MerkleTreeLib.computeRoot(keys, values);
    }

    function callGetProof(bytes32[] memory keys, bytes32[] memory values, uint256 index)
        external
        pure
        returns (bytes32[] memory)
    {
        return MerkleTreeLib.getProof(keys, values, index);
    }
}
