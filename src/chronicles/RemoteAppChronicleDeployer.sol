// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IRemoteAppChronicleDeployer } from "../interfaces/IRemoteAppChronicleDeployer.sol";
import { RemoteAppChronicle } from "./RemoteAppChronicle.sol";

/**
 * @title RemoteAppChronicleDeployer
 * @notice Default deployer for RemoteAppChronicle contracts using Create2
 * @dev Implements the standard deployment logic for RemoteAppChronicle using OpenZeppelin's Create2.
 *      This contract can be replaced in LiquidityMatrix to handle future
 *      requirements without changing the core protocol.
 *      Only the LiquidityMatrix contract can call deploy().
 */
contract RemoteAppChronicleDeployer is IRemoteAppChronicleDeployer {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev The LiquidityMatrix contract that is authorized to deploy chronicles
    address public immutable liquidityMatrix;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new RemoteAppChronicleDeployer
     * @param _liquidityMatrix The LiquidityMatrix contract address
     */
    constructor(address _liquidityMatrix) {
        liquidityMatrix = _liquidityMatrix;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRemoteAppChronicleDeployer
    function computeAddress(address app, bytes32 chainUID, uint256 version) external view returns (address chronicle) {
        bytes32 salt = keccak256(abi.encodePacked(app, chainUID, version));
        bytes memory bytecode =
            abi.encodePacked(type(RemoteAppChronicle).creationCode, abi.encode(liquidityMatrix, app, chainUID, version));
        return Create2.computeAddress(salt, keccak256(bytecode));
    }

    /// @inheritdoc IRemoteAppChronicleDeployer
    function deploy(address app, bytes32 chainUID, uint256 version) external returns (address chronicle) {
        if (msg.sender != liquidityMatrix) revert Forbidden();

        bytes32 salt = keccak256(abi.encodePacked(app, chainUID, version));
        bytes memory bytecode =
            abi.encodePacked(type(RemoteAppChronicle).creationCode, abi.encode(liquidityMatrix, app, chainUID, version));
        chronicle = Create2.deploy(0, salt, bytecode);
    }
}
