// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IRemoteAppChronicleDeployer
 * @notice Interface for deploying RemoteAppChronicle contracts using Create2
 * @dev This deployer pattern allows for upgradeable chronicle creation logic.
 *      The deployer is set in LiquidityMatrix and can be updated by the owner
 *      to handle future requirements like gas optimization or new features.
 *      Uses Create2 for deterministic deployment addresses.
 */
interface IRemoteAppChronicleDeployer {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Computes the address of a RemoteAppChronicle before deployment
     * @dev Uses Create2 to compute the deterministic address
     * @param app The application this chronicle will serve
     * @param chainUID The remote chain identifier
     * @param version The version number for state isolation
     * @return chronicle The computed address of the RemoteAppChronicle
     */
    function computeAddress(address app, bytes32 chainUID, uint256 version) external view returns (address chronicle);

    /**
     * @notice Deploys a new RemoteAppChronicle contract using Create2
     * @dev Called by LiquidityMatrix when an app needs a new remote chronicle.
     *      The deployer must return a contract that implements IRemoteAppChronicle.
     *      Only callable by the liquidityMatrix set in the constructor.
     * @param app The application this chronicle will serve
     * @param chainUID The remote chain identifier
     * @param version The version number for state isolation
     * @return chronicle The address of the deployed RemoteAppChronicle
     */
    function deploy(address app, bytes32 chainUID, uint256 version) external returns (address chronicle);
}
