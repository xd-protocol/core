// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUserWalletFactory {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRegistry();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event WalletCreated(address indexed user, address indexed wallet);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The token registry contract address
     * @return The registry address
     */
    function registry() external view returns (address);

    /**
     * @notice Mapping to track deployed wallets (for convenience)
     * @param user The user address
     * @return wallet The wallet address for the user
     */
    function userWallets(address user) external view returns (address wallet);

    /**
     * @notice Compute the UserWallet address for a user without deploying
     * @dev Useful for predicting addresses before deployment
     * @param user The user address
     * @return The computed UserWallet address
     */
    function computeWalletAddress(address user) external view returns (address);

    /**
     * @notice Check if a wallet has been deployed for a user
     * @param user The user address to check
     * @return deployed Whether the wallet has been deployed
     */
    function isWalletDeployed(address user) external view returns (bool deployed);

    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get or create a UserWallet for a user
     * @dev Uses CREATE2 with user address as salt for deterministic addresses
     * @param user The user address to create wallet for
     * @return wallet The UserWallet address (existing or newly created)
     */
    function getOrCreateWallet(address user) external returns (address wallet);

    /**
     * @notice Batch create wallets for multiple users
     * @dev Useful for pre-deploying wallets
     * @param users Array of user addresses
     * @return wallets Array of created wallet addresses
     */
    function batchCreateWallets(address[] calldata users) external returns (address[] memory wallets);
}
