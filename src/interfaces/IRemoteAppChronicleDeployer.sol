// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IRemoteAppChronicleDeployer
 * @notice Interface for deploying RemoteAppChronicle contracts
 * @dev This deployer pattern allows for upgradeable chronicle creation logic.
 *      The deployer is set in LiquidityMatrix and can be updated by the owner
 *      to handle future requirements like gas optimization or new features.
 */
interface IRemoteAppChronicleDeployer {
    /**
     * @notice Deploys a new RemoteAppChronicle contract
     * @dev Called by LiquidityMatrix when an app needs a new remote chronicle.
     *      The deployer must return a contract that implements IRemoteAppChronicle.
     * @param liquidityMatrix The LiquidityMatrix contract address
     * @param app The application this chronicle will serve
     * @param chainUID The remote chain identifier
     * @param version The version number for state isolation
     * @return chronicle The address of the deployed RemoteAppChronicle
     */
    function deploy(address liquidityMatrix, address app, bytes32 chainUID, uint256 version)
        external
        returns (address chronicle);
}
