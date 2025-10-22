// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IUserWalletFactory } from "../interfaces/IUserWalletFactory.sol";
import { UserWallet } from "./UserWallet.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title UserWalletFactory
 * @notice Factory for deploying UserWallet beacon proxies
 * @dev Uses beacon proxy pattern for upgradeability - all wallets can be upgraded via beacon
 * @dev Uses OpenZeppelin's BeaconProxy with CREATE2 for deterministic addresses
 * @dev All wallets can be upgraded simultaneously by upgrading the beacon
 */
contract UserWalletFactory is IUserWalletFactory {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUserWalletFactory
    address public immutable override registry;

    /// @notice Beacon contract that stores the current implementation
    address public immutable beacon;

    /// @inheritdoc IUserWalletFactory
    mapping(address user => address wallet) public override userWallets;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _registry, address _beaconOwner) {
        if (_registry == address(0)) revert InvalidRegistry();
        registry = _registry;

        // Deploy implementation and beacon
        address implementation = address(new UserWallet());
        beacon = address(new UpgradeableBeacon(implementation, _beaconOwner));
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get or create a UserWallet for a user
     * @dev Uses CREATE2 for deterministic addresses
     * @dev Deploys BeaconProxy that delegates to beacon's implementation
     * @dev All wallets can be upgraded by upgrading the beacon
     * @param user The user address to create wallet for
     * @return wallet The UserWallet address (existing or newly created)
     */
    function getOrCreateWallet(address user) external returns (address wallet) {
        wallet = userWallets[user];

        if (wallet == address(0)) {
            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(UserWallet.initialize.selector, user, registry);

            // Use user address as salt for deterministic deployment
            bytes32 salt = bytes32(uint256(uint160(user)));

            // Deploy BeaconProxy with CREATE2
            // Benefit: All wallets upgradeable via single beacon upgrade
            wallet = address(new BeaconProxy{ salt: salt }(beacon, initData));

            // Store in mapping for convenience
            userWallets[user] = wallet;

            emit WalletCreated(user, wallet);
        }

        return wallet;
    }

    /**
     * @notice Compute the UserWallet address for a user without deploying
     * @dev Useful for predicting addresses before deployment
     * @param user The user address
     * @return The computed UserWallet address
     */
    function computeWalletAddress(address user) external view returns (address) {
        bytes32 salt = bytes32(uint256(uint160(user)));
        bytes memory initData = abi.encodeWithSelector(UserWallet.initialize.selector, user, registry);
        bytes memory bytecode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(beacon, initData));
        return Create2.computeAddress(salt, keccak256(bytecode));
    }

    /**
     * @notice Check if a wallet has been deployed for a user
     * @param user The user address to check
     * @return deployed Whether the wallet has been deployed
     */
    function isWalletDeployed(address user) external view returns (bool deployed) {
        address wallet = userWallets[user];
        if (wallet != address(0)) {
            return true;
        }

        // Also check if wallet exists at computed address
        // (in case it was deployed on another chain)
        address computedAddress = this.computeWalletAddress(user);
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(computedAddress)
        }
        return codeSize > 0;
    }

    /**
     * @notice Batch create wallets for multiple users
     * @dev Useful for pre-deploying wallets
     * @param users Array of user addresses
     * @return wallets Array of created wallet addresses
     */
    function batchCreateWallets(address[] calldata users) external returns (address[] memory wallets) {
        wallets = new address[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            wallets[i] = this.getOrCreateWallet(users[i]);
        }
        return wallets;
    }
}
