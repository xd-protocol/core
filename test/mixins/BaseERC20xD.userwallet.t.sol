// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { ERC20xD } from "../../src/ERC20xD.sol";
import { UserWallet } from "../../src/wallet/UserWallet.sol";
import { UserWalletFactory } from "../../src/wallet/UserWalletFactory.sol";
import { TokenRegistry } from "../../src/wallet/TokenRegistry.sol";
import { LiquidityMatrix } from "../../src/LiquidityMatrix.sol";
import { LocalAppChronicleDeployer } from "../../src/chronicles/LocalAppChronicleDeployer.sol";
import { RemoteAppChronicleDeployer } from "../../src/chronicles/RemoteAppChronicleDeployer.sol";
import { LayerZeroGatewayMock } from "../mocks/LayerZeroGatewayMock.sol";
import { ILiquidityMatrix } from "../../src/interfaces/ILiquidityMatrix.sol";
import { IBaseERC20xD } from "../../src/interfaces/IBaseERC20xD.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { SettlerMock } from "../mocks/SettlerMock.sol";

/**
 * @title Mock DeFi Protocol for testing
 */
contract MockDeFiProtocol {
    event Deposited(address user, address token, uint256 amount);
    event Swapped(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    mapping(address => mapping(address => uint256)) public deposits;

    function deposit(address payable token, uint256 amount) external {
        // Standard DeFi pattern: transferFrom(msg.sender, ...)
        ERC20xD(token).transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][token] = deposits[msg.sender][token] + amount;
        emit Deposited(msg.sender, token, amount);
    }

    function swap(address payable tokenIn, address payable tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut)
    {
        // Transfer in the input token
        ERC20xD(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Simple 1:1 swap for testing
        amountOut = amountIn;

        // Mint output tokens (in real protocol would come from reserves)
        if (tokenOut != address(0)) {
            ERC20xD(tokenOut).mint(msg.sender, amountOut);
        }

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }
}

/**
 * @title Integration test for BaseERC20xD with UserWallet
 */
contract BaseERC20xDUserWalletTest is Test {
    ERC20xD public token;
    LiquidityMatrix public liquidityMatrix;
    LayerZeroGatewayMock public gateway;
    SettlerMock public settler;

    UserWalletFactory public walletFactory;
    TokenRegistry public registry;
    MockDeFiProtocol public defiProtocol;

    address public owner = makeAddr("owner");
    address public registryOwner = makeAddr("registryOwner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    bytes32 public constant CHAIN_UID = bytes32("ETHEREUM");

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event WalletCreated(address indexed user, address indexed wallet);
    event InitiateTransfer(address indexed from, address indexed to, uint256 amount, uint256 value, uint256 nonce);

    function setUp() public {
        // Deploy infrastructure
        // We need to predict the LiquidityMatrix address first
        // Since we can't predict it easily, we'll deploy it twice

        // First deployment to get the address
        LiquidityMatrix tempMatrix = new LiquidityMatrix(owner, block.timestamp, address(0), address(0));

        // Now deploy deployers with the actual address we'll use
        LocalAppChronicleDeployer localDeployer = new LocalAppChronicleDeployer(address(tempMatrix));
        RemoteAppChronicleDeployer remoteDeployer = new RemoteAppChronicleDeployer(address(tempMatrix));

        // Update the LiquidityMatrix to use the new deployers
        vm.startPrank(owner);
        tempMatrix.updateLocalAppChronicleDeployer(address(localDeployer));
        tempMatrix.updateRemoteAppChronicleDeployer(address(remoteDeployer));
        vm.stopPrank();

        liquidityMatrix = tempMatrix;

        gateway = new LayerZeroGatewayMock();
        settler = new SettlerMock(address(liquidityMatrix));

        // Whitelist settler
        vm.prank(owner);
        liquidityMatrix.updateSettlerWhitelisted(address(settler), true);

        // Deploy wallet infrastructure
        registry = new TokenRegistry(registryOwner);
        walletFactory = new UserWalletFactory(address(registry), owner);

        // Deploy token
        token =
            new ERC20xD("Test Token", "TEST", 18, address(liquidityMatrix), address(gateway), owner, address(settler));

        // Configure token with wallet factory
        vm.prank(owner);
        token.updateWalletFactory(address(walletFactory));

        // Register token in registry so it can use wallets
        vm.prank(registryOwner);
        registry.registerToken(address(token), true);

        // Deploy DeFi protocol
        defiProtocol = new MockDeFiProtocol();

        // Setup token for testing
        vm.startPrank(owner);
        token.mint(alice, 1000 ether);

        // Configure read chains and targets for the token
        bytes32[] memory readChains = new bytes32[](1);
        address[] memory targets = new address[](1);
        readChains[0] = bytes32(uint256(1)); // Just use a dummy chain ID
        targets[0] = address(token);
        token.addReadChains(readChains, targets);
        vm.stopPrank();

        // Setup gateway
        // gateway.registerApp(address(token)); // Not available in mock

        // Add RemoteAppChronicle for the chain we're reading from
        vm.prank(address(settler));
        liquidityMatrix.addRemoteAppChronicle(address(token), bytes32(uint256(1)), 1);

        // Fund for gas
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC WALLET CREATION
    //////////////////////////////////////////////////////////////*/

    function test_walletCreation_onFirstCompose() public {
        // Check no wallet exists initially
        address walletBefore = walletFactory.userWallets(alice);
        assertEq(walletBefore, address(0));

        // Prepare compose call
        bytes memory callData = abi.encodeWithSignature("deposit(address,uint256)", address(token), 100 ether);

        // Execute transfer with compose
        vm.prank(alice);
        bytes32 guid = token.transfer{ value: 0.1 ether }(
            address(defiProtocol), 100 ether, callData, 0, abi.encodePacked(uint128(2_000_000), alice)
        );

        // Wallet is created during onRead callback (nonce 1)
        vm.prank(address(gateway));
        token.onRead(abi.encode(int256(0)), abi.encode(uint256(0), uint256(1))); // MODE_SINGLE_TRANSFER, nonce

        // Check wallet was created
        address walletAfter = walletFactory.userWallets(alice);
        assertTrue(walletAfter != address(0));

        // Verify wallet owner
        assertEq(UserWallet(payable(walletAfter)).owner(), alice);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPOSE WITH WALLET
    //////////////////////////////////////////////////////////////*/

    function test_compose_throughUserWallet() public {
        // Prepare compose call
        bytes memory callData = abi.encodeWithSignature("deposit(address,uint256)", address(token), 100 ether);

        // Get alice's balance before
        int256 aliceBalanceBefore = token.localBalanceOf(alice);

        // Execute transfer with compose
        vm.prank(alice);
        bytes32 guid = token.transfer{ value: 0.1 ether }(
            address(defiProtocol), 100 ether, callData, 0, abi.encodePacked(uint128(2_000_000), alice)
        );

        // Simulate gateway callback (nonce 1)
        vm.prank(address(gateway));
        token.onRead(
            abi.encode(int256(0)), // No global availability needed for this test
            abi.encode(uint256(0), uint256(1)) // MODE_SINGLE_TRANSFER, nonce
        );

        // Get wallet address
        address wallet = walletFactory.userWallets(alice);

        // Check balances
        int256 aliceBalanceAfter = token.localBalanceOf(alice);
        int256 walletBalance = token.localBalanceOf(wallet);
        int256 protocolBalance = token.localBalanceOf(address(defiProtocol));

        // Alice should have 100 less tokens
        assertEq(aliceBalanceAfter, aliceBalanceBefore - 100 ether);

        // Wallet should have 0 tokens (all transferred)
        assertEq(walletBalance, 0);

        // Protocol should have received 100 tokens
        assertEq(protocolBalance, 100 ether);

        // Verify deposit was recorded
        assertEq(defiProtocol.deposits(wallet, address(token)), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    WALLET REUSE ACROSS CALLS
    //////////////////////////////////////////////////////////////*/

    function test_walletReuse_multipleComposes() public {
        // First compose
        bytes memory callData1 = abi.encodeWithSignature("deposit(address,uint256)", address(token), 50 ether);

        vm.prank(alice);
        bytes32 guid1 = token.transfer{ value: 0.1 ether }(
            address(defiProtocol), 50 ether, callData1, 0, abi.encodePacked(uint128(2_000_000), alice)
        );

        // First transfer uses nonce 1 (0 is reserved)
        vm.prank(address(gateway));
        token.onRead(abi.encode(int256(0)), abi.encode(uint256(0), uint256(1))); // MODE_SINGLE_TRANSFER, nonce

        address wallet = walletFactory.userWallets(alice);
        address firstWallet = wallet;

        // Second compose - should reuse same wallet
        bytes memory callData2 = abi.encodeWithSignature("deposit(address,uint256)", address(token), 30 ether);

        vm.prank(alice);
        bytes32 guid2 = token.transfer{ value: 0.1 ether }(
            address(defiProtocol), 30 ether, callData2, 0, abi.encodePacked(uint128(2_000_000), alice)
        );

        // Second transfer uses nonce 2
        vm.prank(address(gateway));
        token.onRead(abi.encode(int256(0)), abi.encode(uint256(0), uint256(2))); // MODE_SINGLE_TRANSFER, nonce

        address secondWallet = walletFactory.userWallets(alice);

        // Should be same wallet
        assertEq(firstWallet, secondWallet);

        // Total deposits should be 80
        assertEq(defiProtocol.deposits(wallet, address(token)), 80 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        REFUND MECHANISM
    //////////////////////////////////////////////////////////////*/

    function test_refund_unusedTokens() public {
        // Create a protocol that only uses half the tokens
        MockPartialProtocol partialProtocol = new MockPartialProtocol();

        // Prepare compose call requesting 100 but only using 40
        bytes memory callData = abi.encodeWithSignature("usePartial(address,uint256)", address(token), 40 ether);

        int256 aliceBalanceBefore = token.localBalanceOf(alice);

        // Execute transfer with compose
        vm.prank(alice);
        bytes32 guid = token.transfer{ value: 0.1 ether }(
            address(partialProtocol), 100 ether, callData, 0, abi.encodePacked(uint128(2_000_000), alice)
        );

        vm.prank(address(gateway));
        token.onRead(abi.encode(int256(0)), abi.encode(uint256(0), uint256(1))); // MODE_SINGLE_TRANSFER, nonce

        // Check final balances
        int256 aliceBalanceAfter = token.localBalanceOf(alice);
        int256 protocolBalance = token.localBalanceOf(address(partialProtocol));

        // Alice should only be down 40 tokens (60 refunded)
        assertEq(aliceBalanceAfter, aliceBalanceBefore - 40 ether);

        // Protocol should have 40 tokens
        assertEq(protocolBalance, 40 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    SECURITY: ISOLATION
    //////////////////////////////////////////////////////////////*/

    function test_security_walletIsolation() public {
        // Deploy malicious contract
        MaliciousContract malicious = new MaliciousContract(address(token));

        // Alice tries to compose with malicious contract
        bytes memory callData = abi.encodeWithSignature("exploit()");

        vm.prank(alice);
        bytes32 guid = token.transfer{ value: 0.1 ether }(
            address(malicious), 50 ether, callData, 0, abi.encodePacked(uint128(2_000_000), alice)
        );

        vm.prank(address(gateway));
        token.onRead(abi.encode(int256(0)), abi.encode(uint256(0), uint256(1))); // MODE_SINGLE_TRANSFER, nonce

        // The malicious contract cannot steal extra tokens because:
        // 1. Only 50 ether was sent to the wallet
        // 2. The wallet refunds unused tokens to alice
        // 3. Since exploit() fails to transfer, all 50 are refunded
        int256 aliceBalance = token.localBalanceOf(alice);
        assertEq(aliceBalance, 1000 ether); // No tokens lost due to refund

        // Token contract itself should have no balance
        int256 tokenBalance = token.localBalanceOf(address(token));
        assertEq(tokenBalance, 0);

        // Malicious contract should have no balance
        int256 maliciousBalance = token.localBalanceOf(address(malicious));
        assertEq(maliciousBalance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    BACKWARDS COMPATIBILITY
    //////////////////////////////////////////////////////////////*/

    function test_backwardsCompatibility_noWalletFactory() public {
        // Deploy token without wallet factory
        ERC20xD legacyToken = new ERC20xD(
            "Legacy Token", "LEGACY", 18, address(liquidityMatrix), address(gateway), owner, address(settler)
        );

        // Note: walletFactory is not set (defaults to address(0))

        // Setup
        vm.startPrank(owner);
        legacyToken.mint(alice, 1000 ether);

        // Configure read chains and targets for the legacy token
        bytes32[] memory readChains = new bytes32[](1);
        address[] memory targets = new address[](1);
        readChains[0] = bytes32(uint256(1)); // Just use a dummy chain ID
        targets[0] = address(legacyToken);
        legacyToken.addReadChains(readChains, targets);
        vm.stopPrank();

        // Add RemoteAppChronicle for the legacy token
        vm.prank(address(settler));
        liquidityMatrix.addRemoteAppChronicle(address(legacyToken), bytes32(uint256(1)), 1);

        // Prepare compose call
        bytes memory callData = abi.encodeWithSignature("deposit(address,uint256)", address(legacyToken), 100 ether);

        // Initiate transfer (does not revert yet)
        vm.prank(alice);
        bytes32 guid = legacyToken.transfer{ value: 0.1 ether }(
            address(defiProtocol), 100 ether, callData, 0, abi.encodePacked(uint128(2_000_000), alice)
        );

        // Expect revert when executing compose without wallet factory set
        vm.expectRevert(IBaseERC20xD.UserWalletFactoryNotSet.selector);
        vm.prank(address(gateway));
        legacyToken.onRead(abi.encode(int256(0)), abi.encode(uint256(0), uint256(1))); // MODE_SINGLE_TRANSFER, nonce
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN SCENARIO
    //////////////////////////////////////////////////////////////*/

    function test_crossChain_withWallet() public {
        // Note: In production, wallet addresses would differ per chain
        // This test simulates the local chain behavior

        // Setup cross-chain transfer
        bytes memory callData = abi.encodeWithSignature("deposit(address,uint256)", address(token), 200 ether);

        // Alice initiates cross-chain transfer with compose
        vm.prank(alice);
        bytes32 guid = token.transfer{ value: 0.2 ether }(
            address(defiProtocol), 200 ether, callData, 0, abi.encodePacked(uint128(2_000_000), alice)
        );

        // Simulate cross-chain read aggregation (nonce 1)
        // In reality, this would aggregate balances from multiple chains
        vm.prank(address(gateway));
        token.onRead(
            abi.encode(int256(500 ether)), // Simulated global availability
            abi.encode(uint256(0), uint256(1)) // MODE_SINGLE_TRANSFER, nonce
        );

        // Verify transfer completed
        int256 protocolBalance = token.localBalanceOf(address(defiProtocol));
        assertEq(protocolBalance, 200 ether);
    }
}

/**
 * @title Mock protocol that only uses part of the tokens
 */
contract MockPartialProtocol {
    function usePartial(address payable token, uint256 amount) external {
        // Only transfer the specified amount, not all available
        ERC20xD(token).transferFrom(msg.sender, address(this), amount);
    }
}

/**
 * @title Malicious contract for security testing
 */
contract MaliciousContract {
    address payable public token;

    constructor(address _token) {
        token = payable(_token);
    }

    function exploit() external {
        // Try to drain as much as possible
        uint256 maxAmount = 1_000_000 ether;
        try ERC20xD(token).transferFrom(msg.sender, address(this), maxAmount) {
        // If this succeeds, we've stolen tokens
        }
            catch {
            // Expected to fail or only get what was authorized
        }
    }
}
