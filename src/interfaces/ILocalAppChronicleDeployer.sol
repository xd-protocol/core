// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILocalAppChronicleDeployer
 * @notice Interface for deploying LocalAppChronicle contracts
 * @dev This deployer pattern allows for upgradeable chronicle creation logic.
 *      The deployer is set in LiquidityMatrix and can be updated by the owner
 *      to handle future requirements like gas optimization or new features.
 */
interface ILocalAppChronicleDeployer {
    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys a new LocalAppChronicle contract
     * @dev Called by LiquidityMatrix when an app needs a new local chronicle.
     *      The deployer must return a contract that implements ILocalAppChronicle.
     * @param liquidityMatrix The LiquidityMatrix contract address
     * @param app The application this chronicle will serve
     * @param version The version number for state isolation
     * @return chronicle The address of the deployed LocalAppChronicle
     */
    function deploy(address liquidityMatrix, address app, uint256 version) external returns (address chronicle);
}
