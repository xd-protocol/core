// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ILocalAppChronicleDeployer } from "../interfaces/ILocalAppChronicleDeployer.sol";
import { LocalAppChronicle } from "./LocalAppChronicle.sol";

/**
 * @title LocalAppChronicleDeployer
 * @notice Default deployer for LocalAppChronicle contracts using Create2
 * @dev Implements the standard deployment logic for LocalAppChronicle using OpenZeppelin's Create2.
 *      This contract can be replaced in LiquidityMatrix to handle future
 *      requirements without changing the core protocol.
 *      Only the LiquidityMatrix contract can call deploy().
 */
contract LocalAppChronicleDeployer is ILocalAppChronicleDeployer {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev The LiquidityMatrix contract that is authorized to deploy chronicles
    address public immutable liquidityMatrix;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new LocalAppChronicleDeployer
     * @param _liquidityMatrix The LiquidityMatrix contract address
     */
    constructor(address _liquidityMatrix) {
        liquidityMatrix = _liquidityMatrix;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ILocalAppChronicleDeployer
    function computeAddress(address app, uint256 version) external view returns (address chronicle) {
        bytes32 salt = keccak256(abi.encodePacked(app, version));
        bytes memory bytecode =
            abi.encodePacked(type(LocalAppChronicle).creationCode, abi.encode(liquidityMatrix, app, version));
        return Create2.computeAddress(salt, keccak256(bytecode));
    }

    /// @inheritdoc ILocalAppChronicleDeployer
    function deploy(address app, uint256 version) external returns (address chronicle) {
        if (msg.sender != liquidityMatrix) revert Forbidden();

        bytes32 salt = keccak256(abi.encodePacked(app, version));
        bytes memory bytecode =
            abi.encodePacked(type(LocalAppChronicle).creationCode, abi.encode(liquidityMatrix, app, version));
        chronicle = Create2.deploy(0, salt, bytecode);
    }
}
