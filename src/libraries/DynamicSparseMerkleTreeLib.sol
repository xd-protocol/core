// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

library DynamicSparseMerkleTreeLib {
    struct Tree {
        mapping(uint256 => bytes32) nodes; // Sparse storage for tree nodes
        uint256 height;
        bytes32 root; // Current root of the Merkle tree
    }

    uint256 constant MAX_TREE_HEIGHT = 256; // Maximum height of the Merkle tree

    error InvalidTreeHeight();
    error InvalidLengths();
    error InvalidProof();

    /**
     * @notice Reconstructs the Merkle tree root from the given keys and values.
     * @param keys An array of keys for the nodes.
     * @param values An array of values corresponding to the keys.
     * @return The reconstructed root of the tree.
     * @dev Computes the root by iteratively hashing pairs of nodes until a single root remains.
     *      This is typically used for external verification or validation scenarios.
     *      Complexity is O(n log n), where `n` is the number of keys.
     */
    function getRoot(bytes32[] memory keys, bytes32[] memory values) internal pure returns (bytes32) {
        if (keys.length != values.length) revert InvalidLengths();

        uint256 treeSize = keys.length;
        bytes32[] memory hashes = new bytes32[](treeSize);

        // Step 1: Compute leaf node hashes
        for (uint256 i; i < treeSize; i++) {
            hashes[i] = keccak256(abi.encodePacked(keys[i], values[i]));
        }

        // Step 2: Reconstruct the tree level by level
        while (treeSize > 1) {
            uint256 nextTreeSize = (treeSize + 1) / 2; // Calculate the size of the next level
            for (uint256 i; i < nextTreeSize; i++) {
                if (2 * i + 1 < treeSize) {
                    // Pair two nodes to create a parent hash
                    hashes[i] = keccak256(abi.encodePacked(hashes[2 * i], hashes[2 * i + 1]));
                } else {
                    // If there's an odd node, it propagates to the next level
                    hashes[i] = hashes[2 * i];
                }
            }
            treeSize = nextTreeSize;
        }

        // Step 3: Return the final root
        return hashes[0];
    }

    /**
     * @notice Verifies the validity of a Merkle proof for a given node.
     * @param height The height of the Merkle tree.
     * @param key The unique key of the node to verify.
     * @param value The value of the node to verify.
     * @param proof An array of sibling hashes needed to reconstruct the root.
     * @param root The expected root of the Merkle tree.
     * @return True if the proof is valid and the reconstructed root matches the expected root.
     * @dev Traverses up the tree using the proof to recompute the root and compares it to the provided root.
     *      Assumes the `proof` array length matches the `height` of the tree.
     *      Complexity is O(h), where `h` is the tree height.
     */
    function verifyProof(uint256 height, bytes32 key, bytes32 value, bytes32[] memory proof, bytes32 root)
        internal
        pure
        returns (bool)
    {
        if (proof.length != height) revert InvalidProof();

        uint256 index = uint256(key) % (1 << height); // Ensure index is within tree bounds
        bytes32 hash = keccak256(abi.encodePacked(key, value)); // Start with the node hash
        uint256 currentIndex = index; // Start at the computed index

        // Traverse up the tree using the proof
        for (uint256 i; i < proof.length; i++) {
            bytes32 siblingHash = proof[i]; // Get the sibling hash from the proof

            if (currentIndex % 2 == 0) {
                hash = keccak256(abi.encodePacked(hash, siblingHash)); // Left child
            } else {
                hash = keccak256(abi.encodePacked(siblingHash, hash)); // Right child
            }

            currentIndex /= 2; // Move up to the parent node
        }

        return hash == root; // Compare the calculated hash with the current root
    }

    /**
     * @notice Initializes the Merkle tree with a given height and sets the root to the default hash.
     * @param self The Merkle tree to initialize.
     * @param height The height of the Merkle tree.
     * @dev Ensures the height is within the allowed range and sets the root to the default value.
     *      This function prepares the tree for updates and other operations.
     *      Complexity is O(h), where `h` is the height of the tree (due to default hash computation).
     */
    function initialize(Tree storage self, uint256 height) internal {
        if (height == 0 || height > MAX_TREE_HEIGHT) revert InvalidTreeHeight();

        self.height = height;
        self.root = defaultHash(0, height); // Set the initial root as the default hash at depth 0
    }

    /**
     * @notice Computes the default hash for a given tree level.
     * @param depth The depth of the tree level (0 being leaf level).
     * @param height The total height of the tree.
     * @return The default hash value for the given depth.
     * @dev Default hashes are used for "empty nodes" in sparse trees.
     *      Iteratively computes the hash for a given depth up to the height of the tree.
     *      Complexity is O(h - depth), where `h` is the tree height and `depth` is the current level.
     */
    function defaultHash(uint256 depth, uint256 height) internal pure returns (bytes32) {
        bytes32 hash = keccak256(abi.encodePacked(depth)); // Base hash for the given depth
        for (uint256 i = 1; i < height - depth; i++) {
            hash = keccak256(abi.encodePacked(hash, hash)); // Default parent = hash(child, child)
        }
        return hash;
    }

    /**
     * @notice Updates a node in the Merkle tree and propagates changes to the root.
     * @param self The Merkle tree to update.
     * @param key The unique key for the node.
     * @param value The value associated with the key.
     * @dev Computes the hash for the node and updates all parent nodes up to the root.
     *      Updates are performed incrementally, ensuring the root reflects all changes.
     *      Complexity is O(h), where `h` is the tree height.
     */
    function updateNode(Tree storage self, bytes32 key, bytes32 value) internal {
        uint256 index = uint256(key) % (1 << self.height); // Ensure index is within tree bounds
        uint256 currentIndex = index; // Start at the computed index
        bytes32 currentHash = keccak256(abi.encodePacked(key, value)); // Calculate the node hash

        // Propagate the hash update from the leaf to the root
        for (uint256 depth; depth <= self.height; depth++) {
            self.nodes[currentIndex] = currentHash; // Store the updated hash

            // If we've reached the root, update it and stop
            if (currentIndex == 0) {
                self.root = currentHash;
                break;
            }

            // Calculate the indices of the parent and sibling nodes
            uint256 parentIndex = currentIndex / 2; // Parent node is at index / 2
            uint256 siblingIndex = currentIndex ^ 1; // XOR with 1 toggles the last bit to get sibling

            // Get the sibling hash (use default hash if sibling doesn't exist)
            bytes32 siblingHash =
                self.nodes[siblingIndex] == 0 ? defaultHash(depth, self.height) : self.nodes[siblingIndex];

            // Calculate the parent hash using the current and sibling hashes
            if (currentIndex % 2 == 0) {
                currentHash = keccak256(abi.encodePacked(currentHash, siblingHash)); // Left child
            } else {
                currentHash = keccak256(abi.encodePacked(siblingHash, currentHash)); // Right child
            }

            currentIndex = parentIndex; // Move to the parent node
        }
    }

    /**
     * @notice Generates a Merkle proof for a given key and value in the tree.
     * @param self The Merkle tree.
     * @param key The unique key of the node for which to generate the proof.
     * @return proof An array of sibling hashes needed to verify the node.
     * @dev Traverses the tree to collect sibling hashes for the given key.
     *      The proof can be used to validate the node's membership in the tree.
     *      Complexity is O(h), where `h` is the tree height.
     */
    function generateProof(Tree storage self, bytes32 key) internal view returns (bytes32[] memory proof) {
        uint256 index = uint256(key) % (1 << self.height); // Ensure index is within tree bounds
        uint256 currentIndex = index;

        bytes32[] memory tempProof = new bytes32[](self.height);
        uint256 actualDepth;

        for (uint256 depth = 0; depth < self.height; depth++) {
            uint256 siblingIndex = currentIndex ^ 1;
            tempProof[depth] =
                self.nodes[siblingIndex] == 0 ? defaultHash(depth, self.height) : self.nodes[siblingIndex];
            currentIndex /= 2;
            actualDepth++;
        }

        // Resize the proof array
        proof = new bytes32[](actualDepth);
        for (uint256 i = 0; i < actualDepth; i++) {
            proof[i] = tempProof[i];
        }

        return proof;
    }
}
