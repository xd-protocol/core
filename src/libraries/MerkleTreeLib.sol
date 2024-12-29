// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library MerkleTreeLib {
    struct Tree {
        mapping(bytes32 => uint256) keyToIndex; // Maps keys to unique indices
        mapping(uint256 => mapping(uint256 => bytes32)) nodes; // Compact array of nodes
        uint256 size; // Number of nodes added
        bytes32 root; // Current Merkle root
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant EMPTY_NODE = bytes32(0);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidLengths();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
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

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the Merkle tree with an empty structure.
     * @param self The Merkle tree structure.
     */
    function initialize(Tree storage self) internal {
        self.root = EMPTY_NODE; // Empty root
    }

    /**
     * @notice Updates a node in the tree incrementally. If the key is new, it is added compactly with a unique index.
     * @param self The Merkle tree structure.
     * @param key The key for the node.
     * @param value The value to set at the node.
     */
    function update(Tree storage self, bytes32 key, bytes32 value) internal returns (uint256 index) {
        bytes32 node = keccak256(abi.encodePacked(key, value));

        index = self.keyToIndex[key];
        if (index == 0) {
            // Add 1 to index to represent 0 for null
            index = self.size + 1;
            self.keyToIndex[key] = index;
            self.size++;
        }
        self.nodes[0][index - 1] = node;

        _updateRoot(self, index - 1);

        return index - 1;
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
