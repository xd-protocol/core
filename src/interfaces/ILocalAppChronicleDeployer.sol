// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILocalAppChronicleDeployer
 * @notice Interface for deploying LocalAppChronicle contracts using Create2
 * @dev This deployer pattern allows for upgradeable chronicle creation logic.
 *      The deployer is set in LiquidityMatrix and can be updated by the owner
 *      to handle future requirements like gas optimization or new features.
 *      Uses Create2 for deterministic deployment addresses.
 */
interface ILocalAppChronicleDeployer {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Forbidden();

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Computes the address of a LocalAppChronicle before deployment
     * @dev Uses Create2 to compute the deterministic address
     * @param app The application this chronicle will serve
     * @param version The version number for state isolation
     * @return chronicle The computed address of the LocalAppChronicle
     */
    function computeAddress(address app, uint256 version) external view returns (address chronicle);

    /**
     * @notice Deploys a new LocalAppChronicle contract using Create2
     * @dev Called by LiquidityMatrix when an app needs a new local chronicle.
     *      The deployer must return a contract that implements ILocalAppChronicle.
     *      Only callable by the liquidityMatrix set in the constructor.
     * @param app The application this chronicle will serve
     * @param version The version number for state isolation
     * @return chronicle The address of the deployed LocalAppChronicle
     */
    function deploy(address app, uint256 version) external returns (address chronicle);
}
