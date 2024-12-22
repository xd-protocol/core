// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DynamicSparseMerkleTreeLib } from "../libraries/DynamicSparseMerkleTreeLib.sol";
import { Checkpoints } from "../libraries/Checkpoints.sol";
import { ISynchronizerCallbacks } from "../interfaces/ISynchronizerCallbacks.sol";

abstract contract SynchronizerLocal {
    using Checkpoints for Checkpoints.Checkpoint[];
    using DynamicSparseMerkleTreeLib for DynamicSparseMerkleTreeLib.Tree;

    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct AppState {
        Checkpoints.Checkpoint[] sumCheckpoints;
        mapping(bytes32 tag => Checkpoints.Checkpoint[]) checkpoints;
        DynamicSparseMerkleTreeLib.Tree tree;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant MAIN_TREE_HEIGHT = 32;
    uint256 internal constant SUB_TREE_HEIGHT = 256;

    mapping(address app => bool) internal _registered;
    mapping(address app => AppState) internal _appStates;
    DynamicSparseMerkleTreeLib.Tree internal _mainTree;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Checkpoint(address indexed app, bytes32 indexed tag, int256 value, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AppNotRegistered();
    error NotContract();
    error AlreadyRegistered();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp(address account) {
        if (!_registered[account]) revert AppNotRegistered();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _mainTree.initialize(MAIN_TREE_HEIGHT);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the root of the main Merkle tree and the current timestamp.
     * @return root The current root of the main tree.
     * @return timestamp The current block timestamp.
     */
    function getMainTreeRoot() external view returns (bytes32 root, uint256 timestamp) {
        return (_mainTree.root, block.timestamp);
    }

    /**
     * @notice Retrieves checkpoint values for a given application, array of tags, and timestamp.
     * @param app The address of the application.
     * @param tags The array of tags to query.
     * @param timestamp The timestamp at which to retrieve the checkpoint values.
     * @return values The array of checkpoint values for the given tags and timestamp.
     */
    function getCheckpoints(address app, bytes32[] memory tags, uint256 timestamp)
        public
        view
        returns (int256[] memory values)
    {
        values = new int256[](tags.length);
        for (uint256 i; i < values.length; ++i) {
            values[i] = getCheckpoint(app, tags[i], timestamp);
        }
    }

    /**
     * @notice Retrieves the checkpoint value for a specific application, tag, and timestamp.
     * @param app The address of the application.
     * @param tag The tag to query.
     * @param timestamp The timestamp at which to retrieve the checkpoint value.
     * @return value The checkpoint value for the given tag and timestamp.
     */
    function getCheckpoint(address app, bytes32 tag, uint256 timestamp) public view returns (int256 value) {
        return _appStates[app].checkpoints[tag].getValueAt(timestamp);
    }

    /**
     * @notice Retrieves the sum of all local values for an application at the current timestamp.
     * @param app The address of the application.
     * @return sum The total sum of local values for the application.
     */
    function getLocalSum(address app) public view returns (int256 sum) {
        return _appStates[app].sumCheckpoints.getValueAt(block.timestamp);
    }

    /**
     * @notice Retrieves the value of a specific tag for an application at the current timestamp.
     * @param app The address of the application.
     * @param tag The tag to query.
     * @return value The value of the given tag at the current timestamp.
     */
    function getLocalValue(address app, bytes32 tag) public view returns (int256 value) {
        return _appStates[app].checkpoints[tag].getValueAt(block.timestamp);
    }

    /**
     * @notice Utility function to check if an address is a contract.
     * @param account The address to check.
     * @return True if the address is a contract, false otherwise.
     */
    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new application, ensuring the caller is a contract.
     * @dev Initializes the application's state, including the Merkle tree.
     */
    function registerApp() external {
        if (!_isContract(msg.sender)) revert NotContract();
        if (_registered[msg.sender]) revert AlreadyRegistered();

        _registered[msg.sender] = true;
        _appStates[msg.sender].tree.initialize(SUB_TREE_HEIGHT);
    }

    /**
     * @notice Updates a local tag value and recalculates the corresponding sum for the application.
     * @param tag The tag to update.
     * @param value The new value for the tag.
     */
    function checkpoint(bytes32 tag, int256 value) external onlyApp(msg.sender) {
        AppState storage state = _appStates[msg.sender];
        Checkpoints.Checkpoint[] storage checkpoints = state.checkpoints[tag];
        int256 prev = checkpoints.getValueAt(block.timestamp);
        checkpoints.updateValueAtNow(value);

        Checkpoints.Checkpoint[] storage sumCheckpoints = state.sumCheckpoints;
        int256 sum = sumCheckpoints.getValueAt(block.timestamp);
        sumCheckpoints.updateValueAtNow(sum - prev + value);

        // Update the app's tree
        state.tree.updateNode(tag, bytes32(uint256(value)));

        // Update the mainTree with the app tree's root
        _mainTree.updateNode(bytes32(bytes20(msg.sender)), state.tree.root);

        emit Checkpoint(msg.sender, tag, value, block.timestamp);
    }
}
