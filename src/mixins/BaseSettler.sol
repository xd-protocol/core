// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { ISynchronizer } from "../interfaces/ISynchronizer.sol";
import { MerkleTreeLib } from "../libraries/MerkleTreeLib.sol";

abstract contract BaseSettler is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    address immutable synchronizer;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event VerifyMainTreeRoot(address indexed app, bytes32 indexed root);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AppNotRegistered();
    error SettlerNotSet();
    error RemoteAppNotSet();
    error InvalidLengths();
    error MainTreeRootNotFound();
    error InvalidRoot();

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyApp(address account) {
        (bool registered,,, address settler) = ISynchronizer(synchronizer).getAppSetting(account);
        if (!registered) revert AppNotRegistered();
        if (settler != address(this)) revert SettlerNotSet();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _synchronizer) {
        synchronizer = _synchronizer;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getRemoteAppOrRevert(address app, uint32 eid) internal view virtual returns (address remoteApp) {
        remoteApp = ISynchronizer(synchronizer).getRemoteApp(app, eid);
        if (remoteApp == address(0)) revert RemoteAppNotSet();
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies a Merkle tree root for an application and marks it as settled.
     * @param app The address of the application for which the root is being verified.
     * @param appRoot The Merkle root of the application.
     * @param mainTreeIndex The index of application in the main tree on the remote chain.
     * @param mainTreeProof The Merkle proof connecting the application's subtree root to the main tree root.
     * @param mainTreeRoot The expected root of the main Merkle tree.
     *
     * @dev This function:
     * - Constructs the application's subtree root using the given keys and values.
     * - Validates the Merkle proof to ensure the application's subtree is correctly connected to the main tree.
     */
    function _verifyMainTreeRoot(
        address app,
        bytes32 appRoot,
        uint256 mainTreeIndex,
        bytes32[] memory mainTreeProof,
        bytes32 mainTreeRoot
    ) internal virtual {
        if (mainTreeRoot == bytes32(0)) revert MainTreeRootNotFound();

        bool valid = MerkleTreeLib.verifyProof(
            bytes32(uint256(uint160(app))), appRoot, mainTreeIndex, mainTreeProof, mainTreeRoot
        );
        if (!valid) revert InvalidRoot();

        emit VerifyMainTreeRoot(app, mainTreeRoot);
    }
}
