// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { ILocalAppChronicleDeployer } from "./interfaces/ILocalAppChronicleDeployer.sol";
import { LocalAppChronicle } from "./LocalAppChronicle.sol";

/**
 * @title LocalAppChronicleDeployer
 * @notice Default deployer for LocalAppChronicle contracts
 * @dev Implements the standard deployment logic for LocalAppChronicle.
 *      This contract can be replaced in LiquidityMatrix to handle future
 *      requirements without changing the core protocol.
 */
contract LocalAppChronicleDeployer is ILocalAppChronicleDeployer {
    /// @inheritdoc ILocalAppChronicleDeployer
    function deploy(address liquidityMatrix, address app, uint256 version) external returns (address chronicle) {
        chronicle = address(new LocalAppChronicle{ salt: bytes32(version) }(liquidityMatrix, app, version));
    }
}
