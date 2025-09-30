// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { NativexD } from "src/NativexD.sol";
import { INativexD } from "src/interfaces/INativexD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";
import { LiquidityMatrixMock } from "./mocks/LiquidityMatrixMock.sol";
import { LayerZeroGatewayMock } from "./mocks/LayerZeroGatewayMock.sol";
import { YieldVaultHookMock } from "./mocks/hooks/YieldVaultHookMock.sol";
import { FailingRedemptionHookMock } from "./mocks/hooks/FailingRedemptionHookMock.sol";
import { HookMock } from "./mocks/hooks/HookMock.sol";
import { CallOrderTrackerMock } from "./mocks/CallOrderTrackerMock.sol";

contract NativexDHooksTest is Test {
    NativexD public nativeToken;
    LiquidityMatrixMock public liquidityMatrix;
    LayerZeroGatewayMock public gateway;

    YieldVaultHookMock public yieldHook;
    FailingRedemptionHookMock public failingHook;
    HookMock public trackingHook;

    address constant owner = address(0x1);
    address constant alice = address(0x2);
    address constant bob = address(0x3);
    address constant settler = address(0x4);

    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 shares, uint256 assets);

    function setUp() public {
        // Deploy mocks
        liquidityMatrix = new LiquidityMatrixMock();
        gateway = new LayerZeroGatewayMock();

        // Whitelist settler in liquidityMatrix
        liquidityMatrix.updateSettlerWhitelisted(settler, true);

        // Deploy native token wrapper
        nativeToken = new NativexD("Native xD", "NxD", 18, address(liquidityMatrix), address(gateway), owner, settler);

        // Set read target for local chain (chain ID 1 from gateway mock)
        vm.prank(owner);
        nativeToken.updateReadTarget(bytes32(uint256(1)), bytes32(uint256(uint160(address(nativeToken)))));

        // Deploy hooks
        yieldHook = new YieldVaultHookMock(address(nativeToken), address(0)); // address(0) for native
        failingHook = new FailingRedemptionHookMock();
        trackingHook = new HookMock();

        // Setup test accounts with native tokens
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(address(yieldHook), 10_000 ether); // Fund yield hook for returns
    }

    /*//////////////////////////////////////////////////////////////
                         HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _simulateGatewayResponse(uint256 nonce, int256 globalAvailability) internal {
        // Simulate the gateway calling onRead with the global availability response
        bytes memory message = abi.encode(globalAvailability);
        vm.prank(address(gateway));
        nativeToken.onRead(message, abi.encode(nonce));
    }

    /*//////////////////////////////////////////////////////////////
                        WRAP WITH HOOKS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_withHook_transfersNativeToContract() public {
        vm.prank(owner);
        nativeToken.setHook(address(yieldHook));

        uint256 contractBalanceBefore = address(nativeToken).balance;
        uint256 hookBalanceBefore = address(yieldHook).balance;

        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");

        // Native tokens should go to contract first, then hook receives them
        assertEq(address(nativeToken).balance, contractBalanceBefore); // Contract forwards to hook
        assertEq(address(yieldHook).balance, hookBalanceBefore + 100 ether);
    }

    function test_wrap_withHook_mintsCorrectAmount() public {
        vm.prank(owner);
        nativeToken.setHook(address(yieldHook));

        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");

        // Should mint the amount returned by hook
        assertEq(nativeToken.balanceOf(alice), 100 ether);
    }

    function test_wrap_withHookFailure_revertsTransaction() public {
        vm.prank(owner);
        nativeToken.setHook(address(failingHook));

        // Expect the transaction to revert
        vm.expectRevert("Wrap disabled");

        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");
    }

    function test_wrap_withoutHook_worksNormally() public {
        // No hook set
        uint256 contractBalanceBefore = address(nativeToken).balance;

        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");

        // Native tokens should stay in contract
        assertEq(address(nativeToken).balance, contractBalanceBefore + 100 ether);
        assertEq(nativeToken.balanceOf(alice), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                     UNWRAP WITH HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrapWithRedemptionHook() public {
        // Set yield hook
        vm.prank(owner);
        nativeToken.setHook(address(yieldHook));

        // Alice wraps native tokens
        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");
        assertEq(nativeToken.balanceOf(alice), 100 ether);

        uint256 aliceBalanceBefore = alice.balance;

        // Alice unwraps tokens
        uint256 fee = nativeToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        nativeToken.unwrap{ value: fee }(alice, 50 ether, "", "");

        // Simulate gateway response - this is when the redemption happens
        _simulateGatewayResponse(1, 0);

        // Verify: Tokens burned and native returned
        assertEq(nativeToken.balanceOf(alice), 50 ether);
        assertEq(alice.balance, aliceBalanceBefore - fee + 50 ether); // Got back native minus fee
    }

    function test_unwrap_withHook_returnsMoreThanShares() public {
        // Setup: wrap and accrue yield
        vm.prank(owner);
        nativeToken.setHook(address(yieldHook));

        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");

        // Simulate 10% yield accrual
        yieldHook.accrueYield();

        uint256 aliceBalanceBefore = alice.balance;

        // Unwrap half the shares
        uint256 fee = nativeToken.quoteUnwrap(500_000);

        vm.prank(alice);
        nativeToken.unwrap{ value: fee }(alice, 50 ether, abi.encode(uint128(500_000), alice), "");

        // Expect event during gateway response
        vm.expectEmit(true, false, false, true);
        emit Unwrap(alice, 50 ether, 55 ether); // Expect 50 ether shares to return 55 ether assets (10% yield)

        _simulateGatewayResponse(1, 0);

        // Alice should receive more native than shares burned
        assertEq(alice.balance, aliceBalanceBefore - fee + 55 ether); // Initial - fee + unwrapped with yield
    }

    function test_unwrap_withHookFailure_revertsTransaction() public {
        // Setup with failing hook
        vm.prank(owner);
        nativeToken.setHook(address(failingHook));

        // Wrap should fail with this hook
        vm.expectRevert("Wrap disabled");
        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");
    }

    /*//////////////////////////////////////////////////////////////
                        ROUND-TRIP WITH HOOKS
    //////////////////////////////////////////////////////////////*/

    function test_wrapUnwrap_roundTrip_withYield() public {
        // Setup with yield hook
        vm.prank(owner);
        nativeToken.setHook(address(yieldHook));

        uint256 aliceInitialBalance = alice.balance;

        // Wrap
        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");

        // Accrue 20% yield
        yieldHook.setYieldPercentage(2000);
        yieldHook.accrueYield();

        // Unwrap all
        uint256 fee = nativeToken.quoteUnwrap(500_000);
        vm.prank(alice);
        nativeToken.unwrap{ value: fee }(alice, 100 ether, abi.encode(uint128(500_000), alice), "");

        _simulateGatewayResponse(1, 0);

        // Should have original + yield minus fee
        assertEq(nativeToken.balanceOf(alice), 0);
        assertEq(alice.balance, aliceInitialBalance - fee + 20 ether); // 20% yield on 100 ether
    }

    /*//////////////////////////////////////////////////////////////
                     NATIVE-SPECIFIC HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_hookReceivesNativeTokens() public {
        vm.prank(owner);
        nativeToken.setHook(address(yieldHook));

        uint256 hookBalanceBefore = address(yieldHook).balance;

        vm.prank(alice);
        nativeToken.wrap{ value: 50 ether }(alice, "");

        // Hook should receive the native tokens
        assertEq(address(yieldHook).balance, hookBalanceBefore + 50 ether);
    }

    function test_hookReturnsNativeTokens() public {
        vm.prank(owner);
        nativeToken.setHook(address(yieldHook));

        // Wrap first
        vm.prank(alice);
        nativeToken.wrap{ value: 100 ether }(alice, "");

        uint256 contractBalanceBefore = address(nativeToken).balance;

        // Unwrap
        uint256 fee = nativeToken.quoteUnwrap(500_000);
        vm.prank(alice);
        nativeToken.unwrap{ value: fee }(alice, 100 ether, abi.encode(uint128(500_000), alice), "");

        _simulateGatewayResponse(1, 0);

        // Contract should have received native from hook and forwarded to user
        // After unwrap, contract balance should be back to what it was before (hook returned the native)
        // The fee goes to the gateway, not the contract
        assertEq(address(nativeToken).balance, contractBalanceBefore);
    }
}
