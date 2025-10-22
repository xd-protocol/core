// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { UserWallet } from "../../src/wallet/UserWallet.sol";
import { IUserWallet } from "../../src/interfaces/IUserWallet.sol";
import { UserWalletFactory } from "../../src/wallet/UserWalletFactory.sol";
import { TokenRegistry } from "../../src/wallet/TokenRegistry.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

/**
 * @title UserWalletV2
 * @notice Upgraded version of UserWallet with new functionality
 */
contract UserWalletV2 is UserWallet {
    // Add new storage variable (safe because of delegate call pattern)
    uint256 public version;

    /**
     * @notice New function in V2
     */
    function getVersion() external pure returns (string memory) {
        return "v2";
    }

    /**
     * @notice Set version (demonstrates new functionality)
     */
    function setVersion(uint256 _version) external {
        if (msg.sender != owner) revert Unauthorized();
        version = _version;
    }
}

contract UserWalletUpgradeTest is Test {
    UserWalletFactory public factory;
    TokenRegistry public registry;
    UpgradeableBeacon public beacon;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    event Upgraded(address indexed implementation);

    function setUp() public {
        // Deploy registry and factory (owner is beacon owner)
        registry = new TokenRegistry(owner);
        factory = new UserWalletFactory(address(registry), owner);

        // Get beacon from factory
        beacon = UpgradeableBeacon(factory.beacon());

        // Create wallets for users
        factory.getOrCreateWallet(user1);
        factory.getOrCreateWallet(user2);
    }

    /*//////////////////////////////////////////////////////////////
                        UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_upgrade_allWalletsUpgraded() public {
        address wallet1 = factory.userWallets(user1);
        address wallet2 = factory.userWallets(user2);

        // Before upgrade, version function doesn't exist
        (bool success,) = wallet1.call(abi.encodeWithSignature("getVersion()"));
        assertFalse(success);

        // Deploy new implementation
        UserWalletV2 implementationV2 = new UserWalletV2();

        // Upgrade beacon (only owner can do this)
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(implementationV2));
        beacon.upgradeTo(address(implementationV2));

        // After upgrade, all wallets have new functionality
        assertEq(UserWalletV2(payable(wallet1)).getVersion(), "v2");
        assertEq(UserWalletV2(payable(wallet2)).getVersion(), "v2");

        // Test new functionality
        vm.prank(user1);
        UserWalletV2(payable(wallet1)).setVersion(42);
        assertEq(UserWalletV2(payable(wallet1)).version(), 42);

        // Wallet2 has independent storage
        assertEq(UserWalletV2(payable(wallet2)).version(), 0);
    }

    function test_upgrade_revertNotOwner() public {
        UserWalletV2 implementationV2 = new UserWalletV2();

        // Non-owner cannot upgrade
        vm.prank(user1);
        vm.expectRevert();
        beacon.upgradeTo(address(implementationV2));
    }

    function test_upgrade_revertInvalidImplementation() public {
        // Cannot upgrade to non-contract
        vm.prank(owner);
        vm.expectRevert();
        beacon.upgradeTo(address(0));

        // Cannot upgrade to EOA
        vm.prank(owner);
        vm.expectRevert();
        beacon.upgradeTo(user1);
    }

    function test_upgrade_existingFunctionalityStillWorks() public {
        address wallet1 = factory.userWallets(user1);

        // Deploy and upgrade
        UserWalletV2 implementationV2 = new UserWalletV2();
        vm.prank(owner);
        beacon.upgradeTo(address(implementationV2));

        // Old functionality still works
        assertEq(UserWallet(payable(wallet1)).owner(), user1);
        assertEq(UserWallet(payable(wallet1)).registry(), address(registry));
        assertTrue(UserWallet(payable(wallet1)).isAuthorized(user1));
    }

    function test_upgrade_newWalletsUseNewImplementation() public {
        // Deploy and upgrade before creating new wallet
        UserWalletV2 implementationV2 = new UserWalletV2();
        vm.prank(owner);
        beacon.upgradeTo(address(implementationV2));

        // Create new wallet after upgrade
        address user3 = makeAddr("user3");
        factory.getOrCreateWallet(user3);
        address wallet3 = factory.userWallets(user3);

        // New wallet has V2 functionality
        assertEq(UserWalletV2(payable(wallet3)).getVersion(), "v2");
    }

    function test_beaconImplementation() public view {
        // Beacon points to current implementation
        address impl = beacon.implementation();
        assertTrue(impl != address(0));
    }

    function test_factoryBeaconImmutable() public view {
        // Factory's beacon address is immutable
        address beaconAddr = factory.beacon();
        assertEq(beaconAddr, address(beacon));
    }
}
