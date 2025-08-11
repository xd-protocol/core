// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { IRemoteAppChronicleDeployer } from "../interfaces/IRemoteAppChronicleDeployer.sol";
import { RemoteAppChronicle } from "./RemoteAppChronicle.sol";

/**
 * @title RemoteAppChronicleDeployer
 * @notice Default deployer for RemoteAppChronicle contracts
 * @dev Implements the standard deployment logic for RemoteAppChronicle.
 *      This contract can be replaced in LiquidityMatrix to handle future
 *      requirements without changing the core protocol.
 */
contract RemoteAppChronicleDeployer is IRemoteAppChronicleDeployer {
    /// @inheritdoc IRemoteAppChronicleDeployer
    function deploy(address liquidityMatrix, address app, bytes32 chainUID, uint256 version)
        external
        returns (address chronicle)
    {
        chronicle = address(new RemoteAppChronicle{ salt: bytes32(version) }(liquidityMatrix, app, chainUID, version));
    }
}
