// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IUserWalletFactory } from "../interfaces/IUserWalletFactory.sol";
import { UserWallet } from "./UserWallet.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title UserWalletFactory
 * @notice Factory for deploying UserWallet contracts with deterministic addresses using CREATE2
 * @dev Ensures same wallet address across all chains when deployed at same factory address
 */
contract UserWalletFactory is IUserWalletFactory {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUserWalletFactory
    address public immutable override registry;

    /// @inheritdoc IUserWalletFactory
    mapping(address user => address wallet) public override userWallets;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _registry) {
        if (_registry == address(0)) revert InvalidRegistry();
        registry = _registry;
    }

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get or create a UserWallet for a user
     * @dev Uses CREATE2 with user address as salt for deterministic addresses
     * @param user The user address to create wallet for
     * @return wallet The UserWallet address (existing or newly created)
     */
    function getOrCreateWallet(address user) external returns (address wallet) {
        wallet = userWallets[user];

        if (wallet == address(0)) {
            // Use user address as salt for CREATE2
            // This ensures deterministic addresses across chains
            bytes32 salt = bytes32(uint256(uint160(user)));

            // Deploy new UserWallet with CREATE2
            wallet = address(new UserWallet{ salt: salt }(user, registry));

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

        // Compute CREATE2 address using OpenZeppelin's Create2 library
        bytes32 bytecodeHash = keccak256(abi.encodePacked(type(UserWallet).creationCode, abi.encode(user, registry)));

        return Create2.computeAddress(salt, bytecodeHash, address(this));
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
