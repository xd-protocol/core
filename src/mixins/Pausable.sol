// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Pausable
 * @notice Implements a bitfield-based pause mechanism where each action can be individually paused
 * @dev Each contract extending Pausable defines its own action bit mappings (bits 1-32).
 *      Only the owner can pause/unpause actions via setPaused(bytes32).
 *      This contract should be inherited by contracts that already inherit from Ownable.
 */
abstract contract Pausable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Bitfield storing pause state for each action
    /// @dev Each bit represents a different pausable action (1 = paused, 0 = not paused)
    ///      Bits 1-32 can be used for contract-specific actions
    bytes32 public pauseFlags;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PauseUpdated(bytes32 previousFlags, bytes32 newFlags);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ActionPaused(uint8 actionId);
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures the action is not paused
     * @param actionId The bit position representing the action to check (1-32)
     */
    modifier whenNotPaused(uint8 actionId) {
        if (_isPaused(actionId)) revert ActionPaused(actionId);
        _;
    }

    // No constructor needed as parent contract should handle Ownable

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if a specific action is paused
     * @param actionId The bit position of the action to check (1-32)
     * @return True if the action is paused
     */
    function isPaused(uint8 actionId) external view returns (bool) {
        return _isPaused(actionId);
    }

    /*//////////////////////////////////////////////////////////////
                              LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the pause state for all actions
     * @param newPauseFlags The new pause state bitfield where each bit represents an action
     * @dev Only callable by owner. Each inheriting contract defines its own bit-to-action mapping.
     *      The inheriting contract must also inherit from Ownable for this to work.
     */
    function setPaused(bytes32 newPauseFlags) external {
        _requirePauser();
        bytes32 previousFlags = pauseFlags;
        pauseFlags = newPauseFlags;
        emit PauseUpdated(previousFlags, newPauseFlags);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to check if an action is paused
     * @param actionId The bit position of the action (1-32)
     * @return True if the action is paused
     */
    function _isPaused(uint8 actionId) internal view returns (bool) {
        require(actionId > 0 && actionId <= 32, "Invalid action ID");
        return (pauseFlags & bytes32(uint256(1) << (actionId - 1))) != 0;
    }

    /**
     * @notice Internal function that must be overridden to check pauser authorization
     * @dev This should revert if msg.sender is not authorized to pause/unpause
     */
    function _requirePauser() internal view virtual;
}
