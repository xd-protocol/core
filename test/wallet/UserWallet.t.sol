// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { UserWallet } from "../../src/wallet/UserWallet.sol";
import { IUserWallet } from "../../src/interfaces/IUserWallet.sol";
import { UserWalletFactory } from "../../src/wallet/UserWalletFactory.sol";
import { TokenRegistry } from "../../src/wallet/TokenRegistry.sol";
import { ITokenRegistry } from "../../src/interfaces/ITokenRegistry.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract UserWalletTest is Test {
    UserWallet public wallet;
    UserWalletFactory public factory;
    TokenRegistry public registry;
    ERC20Mock public token;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address tokenContract = makeAddr("tokenContract");
    address attacker = makeAddr("attacker");

    event Executed(address indexed target, uint256 value, bytes data, bool success, bytes result);
    event WalletCreated(address indexed user, address indexed wallet);
    event TokenRegistered(address indexed token, bool status);

    function setUp() public {
        // Deploy registry and factory
        registry = new TokenRegistry(owner);
        factory = new UserWalletFactory(address(registry));

        // Register token contract
        vm.prank(owner);
        registry.registerToken(tokenContract, true);

        // Deploy test token
        token = new ERC20Mock("Test", "TEST", 18);

        // Create wallet for user
        wallet = UserWallet(payable(factory.getOrCreateWallet(user)));

        // Fund wallet with tokens and ETH
        token.mint(address(wallet), 1000e18);
        vm.deal(address(wallet), 10 ether);
        // Fund user for sending msg.value to wallet.execute
        vm.deal(user, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        USERWALLET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wallet_constructor() public {
        assertEq(wallet.owner(), user);
        assertEq(wallet.registry(), address(registry));
    }

    function test_wallet_execute_asOwner() public {
        // Owner can execute calls
        vm.prank(user);

        bytes memory callData = abi.encodeWithSignature("transfer(address,uint256)", attacker, 100e18);

        vm.expectEmit(true, false, false, true);
        emit Executed(
            address(token), 0, callData, true, hex"0000000000000000000000000000000000000000000000000000000000000001"
        );

        (bool success, bytes memory result) = wallet.execute(address(token), callData);
        assertTrue(success);

        assertEq(token.balanceOf(attacker), 100e18);
    }

    function test_wallet_execute_asRegisteredToken() public {
        // Registered token can execute calls
        vm.prank(tokenContract);

        bytes memory callData = abi.encodeWithSignature("transfer(address,uint256)", user, 50e18);

        (bool success, bytes memory result) = wallet.execute(address(token), callData);
        assertTrue(success);

        assertEq(token.balanceOf(user), 50e18);
    }

    function test_wallet_execute_withValue() public {
        // Test executing with ETH value
        vm.prank(user);

        uint256 balanceBefore = attacker.balance;

        (bool success, bytes memory result) = wallet.execute{ value: 1 ether }(attacker, "");
        assertTrue(success);

        assertEq(attacker.balance - balanceBefore, 1 ether);
    }

    function test_wallet_execute_revertUnauthorized() public {
        // Non-owner and non-registered token cannot execute
        vm.prank(attacker);

        vm.expectRevert(IUserWallet.Unauthorized.selector);
        wallet.execute(address(token), "");
    }

    function test_wallet_execute_preventSelfCall() public {
        // Cannot call wallet itself to prevent storage corruption
        vm.prank(user);

        bytes memory callData = abi.encodeWithSignature("execute(address,bytes)", attacker, "");

        vm.expectRevert(IUserWallet.SelfCallNotAllowed.selector);
        wallet.execute(address(wallet), callData);
    }

    function test_wallet_execute_preventRegistryCall() public {
        // Cannot call registry to prevent privilege escalation
        vm.prank(user);

        bytes memory callData = abi.encodeWithSignature("registerToken(address,bool)", attacker, true);

        vm.expectRevert(IUserWallet.CannotCallRegistry.selector);
        wallet.execute(address(registry), callData);
    }

    function test_wallet_query() public {
        // Anyone can call query (read-only)
        bytes memory callData = abi.encodeWithSignature("balanceOf(address)", address(wallet));

        bytes memory result = wallet.query(address(token), callData);
        uint256 balance = abi.decode(result, (uint256));

        assertEq(balance, 1000e18);
    }

    function test_wallet_getTokenBalance() public {
        uint256 balance = wallet.getTokenBalance(address(token));
        assertEq(balance, 1000e18);
    }

    function test_wallet_isAuthorized() public {
        assertTrue(wallet.isAuthorized(user));
        assertTrue(wallet.isAuthorized(tokenContract));
        assertFalse(wallet.isAuthorized(attacker));
    }

    function test_wallet_receiveETH() public {
        uint256 balanceBefore = address(wallet).balance;

        // Send ETH directly
        vm.deal(user, 5 ether);
        vm.prank(user);
        (bool success,) = address(wallet).call{ value: 2 ether }("");
        assertTrue(success);

        assertEq(address(wallet).balance - balanceBefore, 2 ether);
    }

    /*//////////////////////////////////////////////////////////////
                      USERWALLETFACTORY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_factory_getOrCreateWallet_create() public {
        address newUser = makeAddr("newUser");

        // First call creates wallet
        vm.expectEmit(true, true, true, true);
        emit WalletCreated(newUser, factory.computeWalletAddress(newUser));

        address walletAddr = factory.getOrCreateWallet(newUser);

        // Verify wallet was created
        assertTrue(walletAddr != address(0));
        assertEq(factory.userWallets(newUser), walletAddr);

        // Verify wallet properties
        UserWallet newWallet = UserWallet(payable(walletAddr));
        assertEq(newWallet.owner(), newUser);
        assertEq(newWallet.registry(), address(registry));
    }

    function test_factory_getOrCreateWallet_existing() public {
        // First call creates wallet
        address walletAddr1 = factory.getOrCreateWallet(user);

        // Second call returns existing wallet (no event emitted)
        vm.recordLogs();
        address walletAddr2 = factory.getOrCreateWallet(user);

        assertEq(walletAddr1, walletAddr2);
        assertEq(vm.getRecordedLogs().length, 0); // No event emitted
    }

    function test_factory_computeWalletAddress() public {
        address newUser = makeAddr("newUser");

        // Compute address before deployment
        address computed = factory.computeWalletAddress(newUser);

        // Deploy wallet
        address deployed = factory.getOrCreateWallet(newUser);

        // Should match
        assertEq(computed, deployed);
    }

    function test_factory_create2Deterministic() public {
        // Deploy two factories with same registry
        UserWalletFactory factory2 = new UserWalletFactory(address(registry));

        address user1 = makeAddr("user1");

        // Both factories should compute same address for same user
        address computed1 = factory.computeWalletAddress(user1);
        address computed2 = factory2.computeWalletAddress(user1);

        // Addresses should be different (different factory addresses)
        assertTrue(computed1 != computed2);

        // But if we deploy factory at same address on different chain,
        // the wallet addresses would be the same (deterministic)
    }

    function test_factory_isWalletDeployed() public {
        address newUser = makeAddr("newUser");

        // Not deployed yet
        assertFalse(factory.isWalletDeployed(newUser));

        // Deploy wallet
        factory.getOrCreateWallet(newUser);

        // Now deployed
        assertTrue(factory.isWalletDeployed(newUser));
    }

    function test_factory_batchCreateWallets() public {
        address[] memory users = new address[](3);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");

        address[] memory wallets = factory.batchCreateWallets(users);

        assertEq(wallets.length, 3);

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(wallets[i], factory.userWallets(users[i]));
            assertTrue(factory.isWalletDeployed(users[i]));
        }
    }

    /*//////////////////////////////////////////////////////////////
                        TOKENREGISTRY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registry_registerToken() public {
        address newToken = makeAddr("newToken");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TokenRegistered(newToken, true);
        registry.registerToken(newToken, true);

        assertTrue(registry.isRegistered(newToken));
    }

    function test_registry_unregisterToken() public {
        vm.prank(owner);
        registry.registerToken(tokenContract, false);

        assertFalse(registry.isRegistered(tokenContract));
    }

    function test_registry_registerToken_revertNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.registerToken(attacker, true);
    }

    function test_registry_batchRegisterTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = makeAddr("token1");
        tokens[1] = makeAddr("token2");
        tokens[2] = makeAddr("token3");

        bool[] memory statuses = new bool[](3);
        statuses[0] = true;
        statuses[1] = true;
        statuses[2] = false;

        vm.prank(owner);
        registry.batchRegisterTokens(tokens, statuses);

        assertTrue(registry.isRegistered(tokens[0]));
        assertTrue(registry.isRegistered(tokens[1]));
        assertFalse(registry.isRegistered(tokens[2]));
    }

    function test_registry_batchRegisterTokens_revertLengthMismatch() public {
        address[] memory tokens = new address[](2);
        bool[] memory statuses = new bool[](3);

        vm.prank(owner);
        vm.expectRevert(ITokenRegistry.LengthMismatch.selector);
        registry.batchRegisterTokens(tokens, statuses);
    }

    /*//////////////////////////////////////////////////////////////
                      INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_integration_tokenUsesWallet() public {
        // Simulate token contract using wallet for compose
        address recipient = makeAddr("recipient");

        // Register actual token contract
        vm.prank(owner);
        registry.registerToken(address(token), true);

        // Token contract executes through wallet
        vm.prank(address(token));
        bytes memory callData = abi.encodeWithSignature("transfer(address,uint256)", recipient, 200e18);

        (bool success2, bytes memory result2) = wallet.execute(address(token), callData);
        assertTrue(success2);

        assertEq(token.balanceOf(recipient), 200e18);
        assertEq(token.balanceOf(address(wallet)), 800e18);
    }

    function test_integration_walletProtectsFromArbitraryCall() public {
        // Deploy malicious contract
        MaliciousContract malicious = new MaliciousContract();

        // User cannot be tricked into calling malicious contract from unregistered address
        vm.prank(attacker);
        vm.expectRevert(IUserWallet.Unauthorized.selector);
        wallet.execute(address(malicious), abi.encodeWithSignature("drain()"));

        // Even if user calls it, wallet isolates the damage
        vm.prank(user);
        (bool success3, bytes memory result3) = wallet.execute(address(malicious), abi.encodeWithSignature("drain()"));
        assertTrue(success3);

        // Only wallet's assets are at risk, not token contract's
        // This is the key security improvement
    }

    function testFuzz_wallet_execute(address target, uint256 value, bytes memory data) public {
        // ensure caller has enough ETH to send
        vm.assume(value <= 10 ether);
        vm.assume(target != address(0));
        vm.assume(target != address(wallet)); // No self-calls
        vm.assume(target != address(registry)); // No registry calls
        vm.prank(user);
        wallet.execute{ value: value }(target, data);
        // Should not revert for valid inputs
    }
}

contract MaliciousContract {
    function drain() external {
        // Try to drain caller's tokens
        // With UserWallet, only the wallet's tokens are at risk
        // Not the token contract's tokens
    }
}
