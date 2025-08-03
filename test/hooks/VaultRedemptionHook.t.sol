// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { VaultRedemptionHook } from "src/hooks/VaultRedemptionHook.sol";
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { NativexD } from "src/NativexD.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { LiquidityMatrixMock } from "../mocks/LiquidityMatrixMock.sol";
import { ERC20xDGatewayMock } from "../mocks/ERC20xDGatewayMock.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

contract VaultRedemptionHookTest is Test {
    using SafeTransferLib for ERC20;

    VaultRedemptionHook public hookERC20;
    VaultRedemptionHook public hookNative;
    WrappedERC20xD public wrappedToken;
    NativexD public nativeToken;
    ERC20Mock public underlying;
    LiquidityMatrixMock public liquidityMatrix;
    ERC20xDGatewayMock public gateway;

    address constant owner = address(0x1);
    address constant alice = address(0x2);
    address constant bob = address(0x3);

    event RedemptionInitiated(address indexed recipient, uint256 amount, bool isLocal);
    event RedemptionFulfilled(address indexed recipient, uint256 amount);
    event CrossChainRedemptionInitiated(address indexed recipient, uint256 amount, uint32 eid);

    function setUp() public {
        // Deploy mocks
        liquidityMatrix = new LiquidityMatrixMock();
        gateway = new ERC20xDGatewayMock();
        underlying = new ERC20Mock("Mock USDC", "mUSDC", 6);

        // Deploy wrapped token for ERC20
        wrappedToken = new WrappedERC20xD(
            address(underlying), "Wrapped USDC", "wUSDC", 6, address(liquidityMatrix), address(gateway), owner
        );

        // Deploy wrapped token for native
        nativeToken = new NativexD("Wrapped ETH", "wETH", 18, address(liquidityMatrix), address(gateway), owner);

        // Deploy hooks
        hookERC20 = new VaultRedemptionHook(address(wrappedToken), address(underlying));
        hookNative = new VaultRedemptionHook(address(nativeToken), address(0));

        // Set peer for local chain (chain ID 1 from gateway mock)
        vm.prank(owner);
        wrappedToken.setPeer(1, bytes32(uint256(uint160(address(wrappedToken)))));

        vm.prank(owner);
        nativeToken.setPeer(1, bytes32(uint256(uint160(address(nativeToken)))));

        // Add hooks to tokens
        vm.prank(owner);
        wrappedToken.addHook(address(hookERC20));

        vm.prank(owner);
        nativeToken.addHook(address(hookNative));

        // Setup test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        underlying.mint(alice, 1000e6);
        underlying.mint(bob, 1000e6);

        // Approve tokens
        vm.prank(alice);
        underlying.approve(address(wrappedToken), type(uint256).max);
        vm.prank(bob);
        underlying.approve(address(wrappedToken), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                         HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _simulateGatewayResponse(BaseERC20xD token, uint256 nonce, int256 globalAvailability) internal {
        // Simulate the gateway calling onRead with the global availability response
        // CMD_READ_AVAILABILITY = 1
        bytes memory message = abi.encode(uint16(1), nonce, globalAvailability);
        vm.prank(address(gateway));
        token.onRead(message);
    }

    /*//////////////////////////////////////////////////////////////
                         ERC20 REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_erc20_localRedemption() public {
        // Setup: Deposit underlying to hook for redemption
        underlying.mint(address(hookERC20), 100e6);

        // Alice wraps tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);
        assertEq(wrappedToken.balanceOf(alice), 100e6);

        // Alice unwraps tokens
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "");

        // Simulate gateway response with sufficient global availability
        _simulateGatewayResponse(wrappedToken, 1, 0); // nonce 1, no additional global availability needed

        // Verify: Hook should have redeemed tokens to alice
        assertEq(underlying.balanceOf(alice), 950e6); // 1000 - 100 + 50
        assertEq(underlying.balanceOf(address(hookERC20)), 50e6); // 100 - 50
    }

    function test_erc20_localRedemption_fullAmount() public {
        // Setup: Deposit underlying to hook
        underlying.mint(address(hookERC20), 100e6);

        // Alice wraps and unwraps full amount
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 100e6, "");

        // Simulate gateway response
        _simulateGatewayResponse(wrappedToken, 1, 0);

        // Verify full redemption
        assertEq(underlying.balanceOf(alice), 1000e6); // Back to original
        assertEq(underlying.balanceOf(address(hookERC20)), 0);
    }

    function test_erc20_redemption_multipleUsers() public {
        // Setup: Deposit underlying to hook
        underlying.mint(address(hookERC20), 200e6);

        // Multiple users wrap
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        vm.prank(bob);
        wrappedToken.wrap(bob, 100e6);

        // Both unwrap partially
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "");

        vm.prank(bob);
        wrappedToken.unwrap{ value: fee }(bob, 30e6, "");

        // Simulate gateway responses
        _simulateGatewayResponse(wrappedToken, 1, 0); // Alice's unwrap
        _simulateGatewayResponse(wrappedToken, 2, 0); // Bob's unwrap

        // Verify redemptions
        assertEq(underlying.balanceOf(alice), 950e6);
        assertEq(underlying.balanceOf(bob), 930e6);
        assertEq(underlying.balanceOf(address(hookERC20)), 120e6); // 200 - 50 - 30
    }

    function test_erc20_redemption_insufficientBalance() public {
        // Alice wraps tokens but hook has no underlying
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        // Try to unwrap - should emit cross-chain event since no local balance
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "");

        // Simulate gateway response - hook should emit cross-chain event
        vm.expectEmit(true, false, false, true);
        emit CrossChainRedemptionInitiated(alice, 50e6, 0);

        _simulateGatewayResponse(wrappedToken, 1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         NATIVE REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_native_localRedemption() public {
        // Setup: Send ETH to hook for redemption
        vm.deal(address(hookNative), 10 ether);

        // Alice wraps native tokens
        vm.prank(alice);
        nativeToken.wrap{ value: 5 ether }(alice);
        assertEq(nativeToken.balanceOf(alice), 5 ether);

        uint256 aliceBalanceBefore = alice.balance;

        // Alice unwraps tokens
        uint256 fee = nativeToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        nativeToken.unwrap{ value: fee }(alice, 2 ether, "");

        // Simulate gateway response
        _simulateGatewayResponse(nativeToken, 1, 0);

        // Verify: Hook should have sent ETH to alice
        assertEq(alice.balance, aliceBalanceBefore - fee + 2 ether);
        assertEq(address(hookNative).balance, 8 ether); // 10 - 2
    }

    function test_native_redemption_fullAmount() public {
        // Setup: Send ETH to hook
        vm.deal(address(hookNative), 5 ether);

        // Alice wraps and unwraps full amount
        uint256 aliceInitialBalance = alice.balance;

        vm.prank(alice);
        nativeToken.wrap{ value: 5 ether }(alice);

        uint256 fee = nativeToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        nativeToken.unwrap{ value: fee }(alice, 5 ether, "");

        // Simulate gateway response
        _simulateGatewayResponse(nativeToken, 1, 0);

        // Verify full redemption (minus fees)
        assertApproxEqAbs(alice.balance, aliceInitialBalance - fee, 0.001 ether);
        assertEq(address(hookNative).balance, 0);
    }

    function test_native_redemption_multipleUsers() public {
        // Setup: Send ETH to hook
        vm.deal(address(hookNative), 10 ether);

        // Multiple users wrap
        vm.prank(alice);
        nativeToken.wrap{ value: 3 ether }(alice);

        vm.prank(bob);
        nativeToken.wrap{ value: 2 ether }(bob);

        // Track balances
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        // Both unwrap
        uint256 fee = nativeToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        nativeToken.unwrap{ value: fee }(alice, 1 ether, "");

        vm.prank(bob);
        nativeToken.unwrap{ value: fee }(bob, 1 ether, "");

        // Simulate gateway responses
        _simulateGatewayResponse(nativeToken, 1, 0);
        _simulateGatewayResponse(nativeToken, 2, 0);

        // Verify redemptions
        assertEq(alice.balance, aliceBalanceBefore - fee + 1 ether);
        assertEq(bob.balance, bobBalanceBefore - fee + 1 ether);
        assertEq(address(hookNative).balance, 8 ether); // 10 - 1 - 1
    }

    /*//////////////////////////////////////////////////////////////
                         HOOK ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onlyWrappedToken_modifier() public {
        // Try calling hook functions from non-token address
        vm.expectRevert(VaultRedemptionHook.OnlyWrappedToken.selector);
        hookERC20.afterTransfer(alice, address(0), 100e6, "");

        vm.expectRevert(VaultRedemptionHook.OnlyWrappedToken.selector);
        hookERC20.beforeTransfer(alice, bob, 100e6, "");

        vm.expectRevert(VaultRedemptionHook.OnlyWrappedToken.selector);
        hookERC20.onReadGlobalAvailability(alice, 100e6);
    }

    function test_afterTransfer_ignoredForNonBurns() public {
        // Hook should not process regular transfers
        underlying.mint(address(hookERC20), 100e6);

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        // Regular transfer (not burn)
        vm.prank(address(wrappedToken));
        hookERC20.afterTransfer(alice, bob, 50e6, "");

        // Underlying should not be transferred
        assertEq(underlying.balanceOf(address(hookERC20)), 100e6);
        assertEq(underlying.balanceOf(alice), 900e6);
        assertEq(underlying.balanceOf(bob), 1000e6);
    }

    /*//////////////////////////////////////////////////////////////
                         DEPOSIT FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositUnderlying_native() public {
        uint256 initialBalance = address(hookNative).balance;

        // Deposit native tokens
        hookNative.depositUnderlying{ value: 5 ether }();

        assertEq(address(hookNative).balance, initialBalance + 5 ether);
    }

    function test_depositUnderlyingERC20() public {
        uint256 initialBalance = underlying.balanceOf(address(hookERC20));

        // Mint and approve
        underlying.mint(address(this), 100e6);
        underlying.approve(address(hookERC20), 100e6);

        // Deposit ERC20 tokens
        hookERC20.depositUnderlyingERC20(100e6);

        assertEq(underlying.balanceOf(address(hookERC20)), initialBalance + 100e6);
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_integration_wrapUnwrapCycle() public {
        // Setup: Fund hook with underlying
        underlying.mint(address(hookERC20), 1000e6);

        // Multiple wrap/unwrap cycles
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            wrappedToken.wrap(alice, 100e6);

            uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
            vm.prank(alice);
            wrappedToken.unwrap{ value: fee }(alice, 100e6, "");

            // Simulate gateway response
            _simulateGatewayResponse(wrappedToken, i + 1, 0); // nonce starts at 1
        }

        // Alice should have same balance as start
        assertEq(underlying.balanceOf(alice), 1000e6);
        assertEq(wrappedToken.balanceOf(alice), 0);
    }

    function test_integration_partialUnwraps() public {
        // Setup: Fund hook
        underlying.mint(address(hookERC20), 500e6);

        // Alice wraps 200
        vm.prank(alice);
        wrappedToken.wrap(alice, 200e6);

        // Multiple partial unwraps
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "");
        _simulateGatewayResponse(wrappedToken, 1, 0);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 75e6, "");
        _simulateGatewayResponse(wrappedToken, 2, 0);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 25e6, "");
        _simulateGatewayResponse(wrappedToken, 3, 0);

        // Verify state
        assertEq(wrappedToken.balanceOf(alice), 50e6); // 200 - 50 - 75 - 25
        assertEq(underlying.balanceOf(alice), 950e6); // 1000 - 200 + 150
        assertEq(underlying.balanceOf(address(hookERC20)), 350e6); // 500 - 150
    }
}
