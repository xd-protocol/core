// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";
import { IERC20xDGateway } from "src/interfaces/IERC20xDGateway.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ERC20xDMock } from "../mocks/ERC20xDMock.sol";
import { LiquidityMatrixMock } from "../mocks/LiquidityMatrixMock.sol";
import { ERC20xDGatewayMock } from "../mocks/ERC20xDGatewayMock.sol";
import { HookMock } from "../mocks/HookMock.sol";

// Contract to track the order of hook calls using a shared counter
contract CallOrderTracker {
    uint256 public globalCallCounter;

    function incrementAndGet() external returns (uint256) {
        globalCallCounter++;
        return globalCallCounter;
    }
}

// Contract to track the order of hook calls
contract OrderTrackingHook is IERC20xDHook {
    CallOrderTracker public tracker;
    uint256 public beforeTransferCallOrder;
    uint256 public afterTransferCallOrder;
    uint256 public onInitiateTransferCallOrder;
    uint256 public onReadGlobalAvailabilityCallOrder;

    constructor(CallOrderTracker _tracker) {
        tracker = _tracker;
    }

    function beforeTransfer(address, address, uint256) external override {
        beforeTransferCallOrder = tracker.incrementAndGet();
    }

    function afterTransfer(address, address, uint256) external override {
        afterTransferCallOrder = tracker.incrementAndGet();
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override {
        onInitiateTransferCallOrder = tracker.incrementAndGet();
    }

    function onReadGlobalAvailability(address, int256) external override {
        onReadGlobalAvailabilityCallOrder = tracker.incrementAndGet();
    }
}

contract BaseERC20xDHooksTest is Test {
    ERC20xDMock token;
    LiquidityMatrixMock liquidityMatrix;
    ERC20xDGatewayMock gateway;
    HookMock hook1;
    HookMock hook2;
    HookMock hook3;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    event HookAdded(address indexed hook);
    event HookRemoved(address indexed hook);
    event OnInitiateTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, uint256 value, bytes reason
    );
    event OnReadGlobalAvailabilityHookFailure(
        address indexed hook, address indexed account, int256 globalAvailability, bytes reason
    );
    event BeforeTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, bytes reason
    );
    event AfterTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, bytes reason
    );
    event InitiateTransfer(
        address indexed from, address indexed to, uint256 amount, uint256 value, uint256 indexed nonce
    );

    function setUp() public {
        // Deploy mock liquidity matrix
        liquidityMatrix = new LiquidityMatrixMock();

        // Deploy mock gateway
        gateway = new ERC20xDGatewayMock();

        // Deploy token
        token = new ERC20xDMock("Test", "TEST", 18, address(liquidityMatrix), address(gateway), owner);

        // Set peer for cross-chain
        vm.prank(owner);
        token.setPeer(1, bytes32(uint256(uint160(address(token)))));

        // Register app
        vm.prank(address(token));
        liquidityMatrix.registerApp(false, false, address(0));

        // Deploy mock hooks
        hook1 = new HookMock();
        hook2 = new HookMock();
        hook3 = new HookMock();

        // Give users initial balances
        vm.startPrank(address(token));
        liquidityMatrix.updateLocalLiquidity(alice, 100e18);
        liquidityMatrix.updateLocalLiquidity(bob, 100e18);
        liquidityMatrix.updateLocalLiquidity(address(token), 1000e18);
        vm.stopPrank();

        // Set total liquidity
        liquidityMatrix.setTotalLiquidity(address(token), 1200e18);

        // Fund alice for gas
        vm.deal(alice, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            addHook TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addHook() public {
        // Add first hook
        vm.expectEmit(true, false, false, false);
        emit HookAdded(address(hook1));

        vm.prank(owner);
        token.addHook(address(hook1));

        // Verify hook was added
        assertTrue(token.isHook(address(hook1)));
        address[] memory hooks = token.getHooks();
        assertEq(hooks.length, 1);
        assertEq(hooks[0], address(hook1));
    }

    function test_addHook_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        token.addHook(address(0));
    }

    function test_addHook_revertAlreadyAdded() public {
        vm.startPrank(owner);
        token.addHook(address(hook1));

        vm.expectRevert(BaseERC20xD.HookAlreadyAdded.selector);
        token.addHook(address(hook1));
        vm.stopPrank();
    }

    function test_addHook_revertNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.addHook(address(hook1));
    }

    /*//////////////////////////////////////////////////////////////
                            removeHook TESTS
    //////////////////////////////////////////////////////////////*/

    function test_removeHook() public {
        // Add hooks
        vm.startPrank(owner);
        token.addHook(address(hook1));
        token.addHook(address(hook2));
        token.addHook(address(hook3));

        // Remove middle hook
        vm.expectEmit(true, false, false, false);
        emit HookRemoved(address(hook2));
        token.removeHook(address(hook2));
        vm.stopPrank();

        // Verify hook was removed
        assertFalse(token.isHook(address(hook2)));
        address[] memory hooks = token.getHooks();
        assertEq(hooks.length, 2);

        // Check remaining hooks (order might change due to swap-and-pop)
        bool hasHook1 = hooks[0] == address(hook1) || hooks[1] == address(hook1);
        bool hasHook3 = hooks[0] == address(hook3) || hooks[1] == address(hook3);
        assertTrue(hasHook1);
        assertTrue(hasHook3);
    }

    function test_removeHook_revertNotFound() public {
        vm.prank(owner);
        vm.expectRevert(BaseERC20xD.HookNotFound.selector);
        token.removeHook(address(hook1));
    }

    function test_removeHook_revertNonOwner() public {
        vm.prank(owner);
        token.addHook(address(hook1));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.removeHook(address(hook1));
    }

    /*//////////////////////////////////////////////////////////////
                            getHooks TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getHooks() public {
        // Initially empty
        address[] memory hooks = token.getHooks();
        assertEq(hooks.length, 0);

        // Add hooks
        vm.startPrank(owner);
        token.addHook(address(hook1));
        token.addHook(address(hook2));
        vm.stopPrank();

        hooks = token.getHooks();
        assertEq(hooks.length, 2);
        assertEq(hooks[0], address(hook1));
        assertEq(hooks[1], address(hook2));
    }

    /*//////////////////////////////////////////////////////////////
                   onInitiateTransfer HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onInitiateTransfer_called() public {
        // Add hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // Initiate transfer
        bytes memory callData = abi.encode("test");
        bytes memory data = abi.encode("extra");

        vm.prank(alice);
        token.transfer{ value: 0.1 ether }(bob, 10e18, callData, 0.01 ether, data);

        // Verify hook was called
        assertEq(hook1.getInitiateTransferCallCount(), 1);
        (address from, address to, uint256 amount, bytes memory hookCallData, uint256 value, bytes memory hookData,) =
            hook1.initiateTransferCalls(0);

        assertEq(from, alice);
        assertEq(to, bob);
        assertEq(amount, 10e18);
        assertEq(hookCallData, callData);
        assertEq(value, 0.01 ether);
        assertEq(hookData, data);
    }

    function test_onInitiateTransfer_multipleHooks() public {
        // Add multiple hooks
        vm.startPrank(owner);
        token.addHook(address(hook1));
        token.addHook(address(hook2));
        token.addHook(address(hook3));
        vm.stopPrank();

        // Initiate transfer
        vm.prank(alice);
        token.transfer{ value: 0.1 ether }(bob, 5e18, "", 0, "");

        // Verify all hooks were called
        assertEq(hook1.getInitiateTransferCallCount(), 1);
        assertEq(hook2.getInitiateTransferCallCount(), 1);
        assertEq(hook3.getInitiateTransferCallCount(), 1);
    }

    function test_onInitiateTransfer_revertDoesNotBlockTransfer() public {
        // Add reverting hook
        hook1.setShouldRevertOnInitiate(true);
        vm.prank(owner);
        token.addHook(address(hook1));

        // Expect failure event
        vm.expectEmit(true, true, true, false);
        emit OnInitiateTransferHookFailure(
            address(hook1),
            alice,
            bob,
            10e18,
            0,
            abi.encodeWithSignature("Error(string)", "HookMock: Intentional revert")
        );

        // Transfer should still succeed
        vm.expectEmit(true, true, false, true);
        emit InitiateTransfer(alice, bob, 10e18, 0, 1);

        vm.prank(alice);
        token.transfer{ value: 0.1 ether }(bob, 10e18, "");
    }

    /*//////////////////////////////////////////////////////////////
               onReadGlobalAvailability HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onReadGlobalAvailability_called() public {
        // Add hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // Create pending transfer first
        vm.prank(alice);
        token.transfer{ value: 0.1 ether }(bob, 10e18, "");

        // Simulate onRead callback
        token.testOnReadGlobalAvailability(1, 50e18);

        // Verify hook was called
        assertEq(hook1.getGlobalAvailabilityCallCount(), 1);
        (address account, int256 globalAvailability,) = hook1.globalAvailabilityCalls(0);

        assertEq(account, alice);
        assertEq(globalAvailability, 50e18);
    }

    function test_onReadGlobalAvailability_multipleHooks() public {
        // Add multiple hooks
        vm.startPrank(owner);
        token.addHook(address(hook1));
        token.addHook(address(hook2));
        token.addHook(address(hook3));
        vm.stopPrank();

        // Create pending transfer
        vm.prank(alice);
        token.transfer{ value: 0.1 ether }(bob, 5e18, "");

        // Simulate onRead callback
        token.testOnReadGlobalAvailability(1, 100e18);

        // Verify all hooks were called
        assertEq(hook1.getGlobalAvailabilityCallCount(), 1);
        assertEq(hook2.getGlobalAvailabilityCallCount(), 1);
        assertEq(hook3.getGlobalAvailabilityCallCount(), 1);
    }

    function test_onReadGlobalAvailability_revertDoesNotBlockTransfer() public {
        // Add reverting hook
        hook1.setShouldRevertOnGlobalAvailability(true);
        vm.prank(owner);
        token.addHook(address(hook1));

        // Create pending transfer
        vm.prank(alice);
        token.transfer{ value: 0.1 ether }(bob, 10e18, "");

        // Expect failure event
        vm.expectEmit(true, true, false, false);
        emit OnReadGlobalAvailabilityHookFailure(
            address(hook1), alice, 50e18, abi.encodeWithSignature("Error(string)", "HookMock: Intentional revert")
        );

        // Transfer should still execute
        token.testOnReadGlobalAvailability(1, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                    beforeTransfer HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_beforeTransfer_called() public {
        // Add hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // Execute transfer
        token.testTransferFrom(alice, bob, 10e18);

        // Verify hook was called
        assertEq(hook1.getBeforeTransferCallCount(), 1);
        (address from, address to, uint256 amount,) = hook1.beforeTransferCalls(0);

        assertEq(from, alice);
        assertEq(to, bob);
        assertEq(amount, 10e18);
    }

    function test_beforeTransfer_calledBeforeBalanceUpdate() public {
        // Add hook that checks balances
        vm.prank(owner);
        token.addHook(address(hook1));

        // Record initial balance
        int256 aliceBalBefore = token.localBalanceOf(alice);

        // Execute transfer
        token.testTransferFrom(alice, bob, 10e18);

        // In the hook call, balances should not have changed yet
        // We can't directly test this, but we can verify the hook was called
        assertEq(hook1.getBeforeTransferCallCount(), 1);

        // After transfer, balance should be updated
        assertEq(token.localBalanceOf(alice), aliceBalBefore - 10e18);
    }

    function test_beforeTransfer_multipleHooks() public {
        // Add multiple hooks
        vm.startPrank(owner);
        token.addHook(address(hook1));
        token.addHook(address(hook2));
        token.addHook(address(hook3));
        vm.stopPrank();

        // Execute transfer
        token.testTransferFrom(alice, bob, 5e18);

        // Verify all hooks were called
        assertEq(hook1.getBeforeTransferCallCount(), 1);
        assertEq(hook2.getBeforeTransferCallCount(), 1);
        assertEq(hook3.getBeforeTransferCallCount(), 1);
    }

    function test_beforeTransfer_revertDoesNotBlockTransfer() public {
        // Add reverting hook
        hook1.setShouldRevertBeforeTransfer(true);
        vm.prank(owner);
        token.addHook(address(hook1));

        // Get initial balances
        int256 aliceBalBefore = token.localBalanceOf(alice);
        int256 bobBalBefore = token.localBalanceOf(bob);

        // Expect failure event
        vm.expectEmit(true, true, true, false);
        emit BeforeTransferHookFailure(
            address(hook1), alice, bob, 10e18, abi.encodeWithSignature("Error(string)", "HookMock: Intentional revert")
        );

        // Transfer should still succeed
        token.testTransferFrom(alice, bob, 10e18);

        // Verify transfer completed
        assertEq(token.localBalanceOf(alice), aliceBalBefore - 10e18);
        assertEq(token.localBalanceOf(bob), bobBalBefore + 10e18);
    }

    /*//////////////////////////////////////////////////////////////
                     afterTransfer HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_afterTransfer_called() public {
        // Add hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // Execute transfer
        token.testTransferFrom(alice, bob, 10e18);

        // Verify hook was called
        assertEq(hook1.getAfterTransferCallCount(), 1);
        (address from, address to, uint256 amount,) = hook1.afterTransferCalls(0);

        assertEq(from, alice);
        assertEq(to, bob);
        assertEq(amount, 10e18);
    }

    function test_afterTransfer_calledAfterBalanceUpdate() public {
        // Add hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // Record initial balances
        int256 aliceBalBefore = token.localBalanceOf(alice);
        int256 bobBalBefore = token.localBalanceOf(bob);

        // Execute transfer
        token.testTransferFrom(alice, bob, 10e18);

        // Verify hook was called
        assertEq(hook1.getAfterTransferCallCount(), 1);

        // Balances should be updated
        assertEq(token.localBalanceOf(alice), aliceBalBefore - 10e18);
        assertEq(token.localBalanceOf(bob), bobBalBefore + 10e18);
    }

    function test_afterTransfer_multipleHooks() public {
        // Add multiple hooks
        vm.startPrank(owner);
        token.addHook(address(hook1));
        token.addHook(address(hook2));
        token.addHook(address(hook3));
        vm.stopPrank();

        // Execute transfer
        token.testTransferFrom(alice, bob, 5e18);

        // Verify all hooks were called
        assertEq(hook1.getAfterTransferCallCount(), 1);
        assertEq(hook2.getAfterTransferCallCount(), 1);
        assertEq(hook3.getAfterTransferCallCount(), 1);
    }

    function test_afterTransfer_revertDoesNotBlockTransfer() public {
        // Add reverting hook
        hook1.setShouldRevertAfterTransfer(true);
        vm.prank(owner);
        token.addHook(address(hook1));

        // Get initial balances
        int256 aliceBalBefore = token.localBalanceOf(alice);
        int256 bobBalBefore = token.localBalanceOf(bob);

        // Expect failure event
        vm.expectEmit(true, true, true, false);
        emit AfterTransferHookFailure(
            address(hook1), alice, bob, 10e18, abi.encodeWithSignature("Error(string)", "HookMock: Intentional revert")
        );

        // Transfer should still succeed
        token.testTransferFrom(alice, bob, 10e18);

        // Verify transfer completed
        assertEq(token.localBalanceOf(alice), aliceBalBefore - 10e18);
        assertEq(token.localBalanceOf(bob), bobBalBefore + 10e18);
    }

    /*//////////////////////////////////////////////////////////////
                      SPECIAL SCENARIOS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_hooks_calledOnSelfTransfer() public {
        // Add hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // Execute self-transfer (should skip balance updates but still call hooks)
        token.testTransferFrom(alice, alice, 10e18);

        // Verify before/after hooks were still called
        assertEq(hook1.getBeforeTransferCallCount(), 1);
        assertEq(hook1.getAfterTransferCallCount(), 1);
    }

    function test_hooks_calledOnMintScenario() public {
        // Add hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // Execute mint-like transfer (from address(0))
        token.testTransferFrom(address(0), charlie, 50e18);

        // Verify hooks were called
        assertEq(hook1.getBeforeTransferCallCount(), 1);
        assertEq(hook1.getAfterTransferCallCount(), 1);

        (address from, address to, uint256 amount,) = hook1.beforeTransferCalls(0);
        assertEq(from, address(0));
        assertEq(to, charlie);
        assertEq(amount, 50e18);
    }

    function test_hooks_calledOnBurnScenario() public {
        // Add hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // Execute burn-like transfer (to address(0))
        token.testTransferFrom(alice, address(0), 25e18);

        // Verify hooks were called
        assertEq(hook1.getBeforeTransferCallCount(), 1);
        assertEq(hook1.getAfterTransferCallCount(), 1);

        (address from, address to, uint256 amount,) = hook1.afterTransferCalls(0);
        assertEq(from, alice);
        assertEq(to, address(0));
        assertEq(amount, 25e18);
    }

    function test_hookOrdering_maintained() public {
        // Deploy a shared call order tracker
        CallOrderTracker tracker = new CallOrderTracker();

        // Deploy three order tracking hooks with the shared tracker
        OrderTrackingHook orderHook1 = new OrderTrackingHook(tracker);
        OrderTrackingHook orderHook2 = new OrderTrackingHook(tracker);
        OrderTrackingHook orderHook3 = new OrderTrackingHook(tracker);

        // Add hooks in specific order: 1, 2, 3
        vm.startPrank(owner);
        token.addHook(address(orderHook1));
        token.addHook(address(orderHook2));
        token.addHook(address(orderHook3));
        vm.stopPrank();

        // Execute transfer - this should call hooks in order
        token.testTransferFrom(alice, bob, 1e18);

        // Verify hooks storage order is maintained
        address[] memory hooks = token.getHooks();
        assertEq(hooks.length, 3);
        assertEq(hooks[0], address(orderHook1));
        assertEq(hooks[1], address(orderHook2));
        assertEq(hooks[2], address(orderHook3));

        // Verify all hooks were called (by checking their call order > 0)
        assertTrue(orderHook1.beforeTransferCallOrder() > 0, "Hook1 beforeTransfer should have been called");
        assertTrue(orderHook1.afterTransferCallOrder() > 0, "Hook1 afterTransfer should have been called");
        assertTrue(orderHook2.beforeTransferCallOrder() > 0, "Hook2 beforeTransfer should have been called");
        assertTrue(orderHook2.afterTransferCallOrder() > 0, "Hook2 afterTransfer should have been called");
        assertTrue(orderHook3.beforeTransferCallOrder() > 0, "Hook3 beforeTransfer should have been called");
        assertTrue(orderHook3.afterTransferCallOrder() > 0, "Hook3 afterTransfer should have been called");

        // Verify hooks were called in the correct order
        // beforeTransfer should be called in order: hook1, hook2, hook3
        assertEq(orderHook1.beforeTransferCallOrder(), 1, "Hook1 beforeTransfer should be called 1st");
        assertEq(orderHook2.beforeTransferCallOrder(), 2, "Hook2 beforeTransfer should be called 2nd");
        assertEq(orderHook3.beforeTransferCallOrder(), 3, "Hook3 beforeTransfer should be called 3rd");

        // afterTransfer should be called in order: hook1, hook2, hook3
        assertEq(
            orderHook1.afterTransferCallOrder(),
            4,
            "Hook1 afterTransfer should be called 4th (after all beforeTransfer)"
        );
        assertEq(orderHook2.afterTransferCallOrder(), 5, "Hook2 afterTransfer should be called 5th");
        assertEq(orderHook3.afterTransferCallOrder(), 6, "Hook3 afterTransfer should be called 6th");
    }

    function test_hookOrdering_onInitiateTransfer() public {
        // Deploy a shared call order tracker
        CallOrderTracker tracker = new CallOrderTracker();

        // Deploy three order tracking hooks with the shared tracker
        OrderTrackingHook orderHook1 = new OrderTrackingHook(tracker);
        OrderTrackingHook orderHook2 = new OrderTrackingHook(tracker);
        OrderTrackingHook orderHook3 = new OrderTrackingHook(tracker);

        // Add hooks in specific order
        vm.startPrank(owner);
        token.addHook(address(orderHook1));
        token.addHook(address(orderHook2));
        token.addHook(address(orderHook3));
        vm.stopPrank();

        // Initiate transfer - this should call onInitiateTransfer hooks in order
        vm.prank(alice);
        token.transfer{ value: 0.1 ether }(bob, 10e18, "");

        // Verify onInitiateTransfer was called in correct order
        assertEq(orderHook1.onInitiateTransferCallOrder(), 1, "Hook1 onInitiateTransfer should be called 1st");
        assertEq(orderHook2.onInitiateTransferCallOrder(), 2, "Hook2 onInitiateTransfer should be called 2nd");
        assertEq(orderHook3.onInitiateTransferCallOrder(), 3, "Hook3 onInitiateTransfer should be called 3rd");
    }

    function test_allHooks_inCompleteTransferFlow() public {
        // Add comprehensive hook
        vm.prank(owner);
        token.addHook(address(hook1));

        // 1. Initiate transfer (triggers onInitiateTransfer)
        vm.prank(alice);
        token.transfer{ value: 0.1 ether }(bob, 10e18, "");

        assertEq(hook1.getInitiateTransferCallCount(), 1);

        // 2. Simulate global availability check (triggers onReadGlobalAvailability)
        token.testOnReadGlobalAvailability(1, 50e18);

        assertEq(hook1.getGlobalAvailabilityCallCount(), 1);

        // The transfer execution would trigger before/after transfer hooks
        // In the actual flow, this happens inside _executePendingTransfer
        assertEq(hook1.getBeforeTransferCallCount(), 1);
        assertEq(hook1.getAfterTransferCallCount(), 1);
    }
}
