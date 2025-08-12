// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

/**
 * @title MerkleTreeLib
 * @notice Library for managing dynamic Merkle trees with efficient insertion and root calculation
 * @dev Implements a binary Merkle tree that supports incremental updates and maintains a current root.
 *      Uses a compact storage structure with key-to-index mapping for efficient lookups and updates.
 *      Designed for tracking state changes in liquidity matrices and cross-chain synchronization.
 */
library MerkleTreeLib {
    struct Tree {
        mapping(bytes32 key => bool) present;
        mapping(bytes32 key => uint256) keyToIndex; // Maps keys to unique indices
        mapping(uint256 => mapping(uint256 => bytes32)) nodes; // Compact array of nodes
        uint256 size; // Number of nodes added
        bytes32 root; // Current Merkle root
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant EMPTY_NODE = keccak256("MERKLE_EMPTY_LEAF_V1");

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidLengths();
    error IndexOutOfBounds();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getRoot(Tree storage self) internal view returns (bytes32) {
        return self.size == 0 ? EMPTY_NODE : self.root;
    }

    /**
     * @notice Verifies a Merkle proof for a given key-value pair.
     * @param key The key to verify.
     * @param value The value corresponding to the key.
     * @param index The index of the key.
     * @param proof An array of sibling hashes that make up the Merkle proof.
     * @param root The expected Merkle root.
     * @return true if the proof is valid and the computed root matches the expected root, otherwise false.
     */
    function verifyProof(bytes32 key, bytes32 value, uint256 index, bytes32[] memory proof, bytes32 root)
        internal
        pure
        returns (bool)
    {
        bytes32 hash = keccak256(abi.encodePacked(key, value)); // Start with the leaf hash

        for (uint256 i; i < proof.length; ++i) {
            bytes32 siblingHash = proof[i];
            if (index % 2 == 0) {
                // If index is even, current hash is the left child
                hash = keccak256(abi.encodePacked(hash, siblingHash));
            } else {
                // If index is odd, current hash is the right child
                hash = keccak256(abi.encodePacked(siblingHash, hash));
            }
            index /= 2; // Move up to the next level
        }

        // Compare the computed root with the expected root
        return hash == root;
    }

    /**
     * @notice Computes the Merkle root from a given list of keys and values.
     * @param keys An array of keys.
     * @param values An array of values corresponding to the keys.
     * @return The computed Merkle root.
     */
    function computeRoot(bytes32[] memory keys, bytes32[] memory values) internal pure returns (bytes32) {
        if (keys.length != values.length) revert InvalidLengths();
        if (keys.length == 0) {
            return EMPTY_NODE;
        }

        // Compute leaf nodes
        bytes32[] memory nodes = new bytes32[](keys.length);
        for (uint256 i; i < keys.length; ++i) {
            nodes[i] = keccak256(abi.encodePacked(keys[i], values[i]));
        }

        // Compute parent nodes level by level
        uint256 size = nodes.length;
        uint256 level = 1;

        while (size > 1) {
            uint256 parentSize = (size + 1) / 2;
            bytes32[] memory parentNodes = new bytes32[](parentSize);

            for (uint256 i; i < size; i += 2) {
                if (i + 1 < size) {
                    parentNodes[i / 2] = keccak256(abi.encodePacked(nodes[i], nodes[i + 1]));
                } else {
                    parentNodes[i / 2] = keccak256(abi.encodePacked(nodes[i], EMPTY_NODE));
                }
            }

            nodes = parentNodes;
            size = parentSize;
            level++;
        }

        return nodes[0];
    }

    /**
     * @notice Generates a Merkle proof for a given node (key and value) in the tree.
     * @param keys An array of keys.
     * @param values An array of values corresponding to the keys.
     * @param index The index of the key-value pair to generate the proof for.
     * @return proof An array of sibling hashes representing the Merkle proof.
     */
    function getProof(bytes32[] memory keys, bytes32[] memory values, uint256 index)
        internal
        pure
        returns (bytes32[] memory proof)
    {
        if (keys.length != values.length) revert InvalidLengths();
        if (index >= keys.length) revert IndexOutOfBounds();

        // Compute leaf nodes
        bytes32[] memory nodes = new bytes32[](keys.length);
        for (uint256 i; i < keys.length; ++i) {
            nodes[i] = keccak256(abi.encodePacked(keys[i], values[i]));
        }

        // Prepare to collect the proof
        uint256 size = nodes.length;
        uint256 proofIndex = 0;
        proof = new bytes32[](_computeProofLength(size));

        // Traverse up the tree, collecting sibling hashes
        while (size > 1) {
            uint256 parentSize = (size + 1) / 2;
            bytes32[] memory parentNodes = new bytes32[](parentSize);

            for (uint256 i; i < size; i += 2) {
                if (i + 1 < size) {
                    parentNodes[i / 2] = keccak256(abi.encodePacked(nodes[i], nodes[i + 1]));
                } else {
                    parentNodes[i / 2] = keccak256(abi.encodePacked(nodes[i], EMPTY_NODE));
                }

                // Collect the sibling hash if it matches the current index
                if (i == index || (i + 1 == index)) {
                    proof[proofIndex] = i == index ? (i + 1 < size ? nodes[i + 1] : EMPTY_NODE) : nodes[i];
                    proofIndex++;
                    index = i / 2; // Update index to the parent's position
                }
            }

            nodes = parentNodes;
            size = parentSize;
        }

        return proof;
    }

    /**
     * @notice Computes the maximum length of a proof for a tree of a given size.
     * @param size The number of leaf nodes in the tree.
     * @return The maximum length of a proof for the tree.
     */
    function _computeProofLength(uint256 size) private pure returns (uint256) {
        uint256 length = 0;
        while (size > 1) {
            size = (size + 1) / 2;
            length++;
        }
        return length;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates a node in the tree. If the key is new, it is added compactly with a unique index.
     * @param self The Merkle tree structure.
     * @param key The key for the node.
     * @param value The value to set at the node.
     * @return index The index of the node that key represents.
     */
    function update(Tree storage self, bytes32 key, bytes32 value) internal returns (uint256 index) {
        bool present = self.present[key];
        if (present) {
            index = self.keyToIndex[key];
        } else {
            self.present[key] = true;
            index = self.size;
            self.keyToIndex[key] = index;
            self.size = index + 1;
        }

        bytes32 node = keccak256(abi.encodePacked(key, value));
        self.nodes[0][index] = node;

        _updateRoot(self, index);
    }

    /**
     * @notice Updates the Merkle root incrementally from a single node change, accounting for a compact layout.
     * @param self The Merkle tree structure.
     * @param index The index of the updated node in the compact array.
     */
    function _updateRoot(Tree storage self, uint256 index) private {
        bytes32 hash = self.nodes[0][index];
        uint256 size = self.size;
        uint256 level;

        while (true) {
            // If we reach the root, update and stop
            if (size == 1) {
                self.root = hash;
                break;
            }

            uint256 parentIndex = index / 2;
            uint256 siblingIndex = index % 2 == 0 ? index + 1 : index - 1;
            bytes32 siblingHash = siblingIndex >= size ? EMPTY_NODE : self.nodes[level][siblingIndex];

            // Compute the parent hash
            if (index % 2 == 0) {
                hash = keccak256(abi.encodePacked(hash, siblingHash));
            } else {
                hash = keccak256(abi.encodePacked(siblingHash, hash));
            }

            // Move up to the parent level
            self.nodes[level + 1][parentIndex] = hash;

            index = parentIndex;
            size = (size + 1) / 2;
            level++;
        }
    }
}
