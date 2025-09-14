// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";
import { IGateway } from "src/interfaces/IGateway.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ERC20xDMock } from "../mocks/ERC20xDMock.sol";
import { LiquidityMatrixMock } from "../mocks/LiquidityMatrixMock.sol";
import { LayerZeroGatewayMock } from "../mocks/LayerZeroGatewayMock.sol";
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
    uint256 public onMapAccountsCallOrder;
    uint256 public onSettleLiquidityCallOrder;
    uint256 public onSettleTotalLiquidityCallOrder;
    uint256 public onSettleDataCallOrder;

    constructor(CallOrderTracker _tracker) {
        tracker = _tracker;
    }

    function beforeTransfer(address, address, uint256, bytes memory) external override {
        beforeTransferCallOrder = tracker.incrementAndGet();
    }

    function afterTransfer(address, address, uint256, bytes memory) external override {
        afterTransferCallOrder = tracker.incrementAndGet();
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override {
        onInitiateTransferCallOrder = tracker.incrementAndGet();
    }

    function onReadGlobalAvailability(address, int256) external override {
        onReadGlobalAvailabilityCallOrder = tracker.incrementAndGet();
    }

    function onMapAccounts(bytes32, address, address) external override {
        onMapAccountsCallOrder = tracker.incrementAndGet();
    }

    function onSettleLiquidity(bytes32, uint256, address, int256) external override {
        onSettleLiquidityCallOrder = tracker.incrementAndGet();
    }

    function onSettleTotalLiquidity(bytes32, uint256, int256) external override {
        onSettleTotalLiquidityCallOrder = tracker.incrementAndGet();
    }

    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override {
        onSettleDataCallOrder = tracker.incrementAndGet();
    }
}

contract BaseERC20xDHooksTest is Test {
    ERC20xDMock token;
    LiquidityMatrixMock liquidityMatrix;
    LayerZeroGatewayMock gateway;
    HookMock hook1;
    HookMock hook2;
    HookMock hook3;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address settler = makeAddr("settler");

    event SetHook(address indexed oldHook, address indexed newHook);
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
    event OnMapAccountsHookFailure(
        address indexed hook, bytes32 indexed chainUID, address remoteAccount, address localAccount, bytes reason
    );
    event OnSettleLiquidityHookFailure(
        address indexed hook,
        bytes32 indexed chainUID,
        uint64 timestamp,
        address indexed account,
        int256 liquidity,
        bytes reason
    );
    event OnSettleTotalLiquidityHookFailure(
        address indexed hook, bytes32 indexed chainUID, uint64 timestamp, int256 totalLiquidity, bytes reason
    );
    event OnSettleDataHookFailure(
        address indexed hook, bytes32 indexed chainUID, uint64 timestamp, bytes32 indexed key, bytes value, bytes reason
    );
    event InitiateTransfer(
        address indexed from, address indexed to, uint256 amount, uint256 value, uint256 indexed nonce
    );

    function setUp() public {
        // Deploy mock liquidity matrix
        liquidityMatrix = new LiquidityMatrixMock();

        // Whitelist settler
        liquidityMatrix.updateSettlerWhitelisted(settler, true);

        // Deploy mock gateway
        gateway = new LayerZeroGatewayMock();

        // Deploy token
        token = new ERC20xDMock("Test", "TEST", 18, address(liquidityMatrix), address(gateway), owner, settler);

        // Set read target for cross-chain
        vm.prank(owner);
        token.updateReadTarget(bytes32(uint256(1)), bytes32(uint256(uint160(address(token)))));

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
                            setHook TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setHook() public {
        // Set first hook
        vm.expectEmit(true, true, false, false);
        emit SetHook(address(0), address(hook1));

        vm.prank(owner);
        token.setHook(address(hook1));

        // Verify hook was set
        assertEq(token.getHook(), address(hook1));
    }

    function test_setHook_replaceExisting() public {
        // Set first hook
        vm.prank(owner);
        token.setHook(address(hook1));

        // Replace with second hook
        vm.expectEmit(true, true, false, false);
        emit SetHook(address(hook1), address(hook2));

        vm.prank(owner);
        token.setHook(address(hook2));

        // Verify hook was replaced
        assertEq(token.getHook(), address(hook2));
    }

    function test_setHook_clearHook() public {
        // Set hook first
        vm.prank(owner);
        token.setHook(address(hook1));

        // Clear hook
        vm.expectEmit(true, true, false, false);
        emit SetHook(address(hook1), address(0));

        vm.prank(owner);
        token.setHook(address(0));

        // Verify hook was cleared
        assertEq(token.getHook(), address(0));
    }

    function test_setHook_revertNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.setHook(address(hook1));
    }

    /*//////////////////////////////////////////////////////////////
                            getHook TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getHook() public {
        // Initially no hook
        assertEq(token.getHook(), address(0));

        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

        // Verify hook is set
        assertEq(token.getHook(), address(hook1));
    }

    /*//////////////////////////////////////////////////////////////
                   onInitiateTransfer HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onInitiateTransfer_called() public {
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

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

    // Note: Multiple hooks test removed since we now support only single hook

    function test_onInitiateTransfer_revertDoesNotBlockTransfer() public {
        // Set reverting hook
        hook1.setShouldRevertOnInitiate(true);
        vm.prank(owner);
        token.setHook(address(hook1));

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
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

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

    // Note: Multiple hooks test removed since we now support only single hook

    function test_onReadGlobalAvailability_revertDoesNotBlockTransfer() public {
        // Set reverting hook
        hook1.setShouldRevertOnGlobalAvailability(true);
        vm.prank(owner);
        token.setHook(address(hook1));

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
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

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
        // Set hook that checks balances
        vm.prank(owner);
        token.setHook(address(hook1));

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

    // Note: Multiple hooks test removed since we now support only single hook

    function test_beforeTransfer_revertDoesNotBlockTransfer() public {
        // Set reverting hook
        hook1.setShouldRevertBeforeTransfer(true);
        vm.prank(owner);
        token.setHook(address(hook1));

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
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

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
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

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

    // Note: Multiple hooks test removed since we now support only single hook

    function test_afterTransfer_revertDoesNotBlockTransfer() public {
        // Set reverting hook
        hook1.setShouldRevertAfterTransfer(true);
        vm.prank(owner);
        token.setHook(address(hook1));

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
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

        // Execute self-transfer (should skip balance updates but still call hooks)
        token.testTransferFrom(alice, alice, 10e18);

        // Verify before/after hooks were still called
        assertEq(hook1.getBeforeTransferCallCount(), 1);
        assertEq(hook1.getAfterTransferCallCount(), 1);
    }

    function test_hooks_calledOnMintScenario() public {
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

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
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

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

    // Note: Hook ordering test removed since we now support only single hook

    // Note: Hook ordering test removed since we now support only single hook

    function test_allHooks_inCompleteTransferFlow() public {
        // Set comprehensive hook
        vm.prank(owner);
        token.setHook(address(hook1));

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

    /*//////////////////////////////////////////////////////////////
                      onMapAccounts HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onMapAccounts_called() public {
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

        // Call onMapAccounts as LiquidityMatrix
        bytes32 chainUID = bytes32(uint256(1));
        address remoteAccount = makeAddr("remote");
        address localAccount = alice;

        vm.prank(address(liquidityMatrix));
        token.onMapAccounts(chainUID, remoteAccount, localAccount);

        // Verify hook was called
        assertEq(hook1.getMapAccountsCallCount(), 1);
        (bytes32 hookChainUID, address hookRemote, address hookLocal,) = hook1.mapAccountsCalls(0);

        assertEq(hookChainUID, chainUID);
        assertEq(hookRemote, remoteAccount);
        assertEq(hookLocal, localAccount);
    }

    // Note: Multiple hooks test removed since we now support only single hook

    function test_onMapAccounts_revertDoesNotBlock() public {
        // Set reverting hook
        hook1.setShouldRevertOnMapAccounts(true);
        vm.prank(owner);
        token.setHook(address(hook1));

        // Expect failure event
        vm.expectEmit(true, true, false, false);
        emit OnMapAccountsHookFailure(
            address(hook1),
            bytes32(uint256(1)),
            makeAddr("remote"),
            alice,
            abi.encodeWithSignature("Error(string)", "HookMock: Intentional revert")
        );

        // Call should still succeed
        vm.prank(address(liquidityMatrix));
        token.onMapAccounts(bytes32(uint256(1)), makeAddr("remote"), alice);
    }

    function test_onMapAccounts_revertNonLiquidityMatrix() public {
        // Try to call from non-LiquidityMatrix address
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.Forbidden.selector);
        token.onMapAccounts(bytes32(uint256(1)), makeAddr("remote"), alice);
    }

    /*//////////////////////////////////////////////////////////////
                    onSettleLiquidity HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onSettleLiquidity_called() public {
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

        // Call onSettleLiquidity as LiquidityMatrix
        bytes32 chainUID = bytes32(uint256(30_000));
        uint256 version = 1;
        uint64 timestamp = uint64(block.timestamp);

        vm.prank(address(liquidityMatrix));
        token.onSettleLiquidity(chainUID, version, timestamp, alice);

        // Verify hook was called
        assertEq(hook1.getSettleLiquidityCallCount(), 1);
        (bytes32 hookChainUID, uint256 hookTimestamp, address hookAccount, int256 hookLiquidity) =
            hook1.settleLiquidityCalls(0);

        assertEq(hookChainUID, chainUID);
        assertEq(hookTimestamp, timestamp);
        assertEq(hookAccount, alice);
        assertEq(hookLiquidity, 100e18); // alice has 100e18 liquidity from setup
    }

    // Note: Multiple hooks test removed since we now support only single hook

    function test_onSettleLiquidity_revertDoesNotBlock() public {
        // Set reverting hook
        hook1.setShouldRevertOnSettleLiquidity(true);
        vm.prank(owner);
        token.setHook(address(hook1));

        // Expect failure event
        vm.expectEmit(true, true, false, true);
        emit OnSettleLiquidityHookFailure(
            address(hook1),
            bytes32(uint256(30_000)),
            uint64(block.timestamp),
            alice,
            100e18,
            abi.encodeWithSignature("Error(string)", "HookMock: Intentional revert")
        );

        // Call should still succeed
        vm.prank(address(liquidityMatrix));
        token.onSettleLiquidity(bytes32(uint256(30_000)), 1, uint64(block.timestamp), alice);
    }

    function test_onSettleLiquidity_revertNonLiquidityMatrix() public {
        // Try to call from non-LiquidityMatrix address
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.Forbidden.selector);
        token.onSettleLiquidity(bytes32(uint256(1)), 1, uint64(block.timestamp), alice);
    }

    /*//////////////////////////////////////////////////////////////
                 onSettleTotalLiquidity HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onSettleTotalLiquidity_called() public {
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

        // Call onSettleTotalLiquidity as LiquidityMatrix
        bytes32 chainUID = bytes32(uint256(30_001));
        uint256 version = 1;
        uint64 timestamp = uint64(block.timestamp + 1000);

        vm.prank(address(liquidityMatrix));
        token.onSettleTotalLiquidity(chainUID, version, timestamp);

        // Verify hook was called
        assertEq(hook1.getSettleTotalLiquidityCallCount(), 1);
        (bytes32 hookChainUID, uint256 hookTimestamp, int256 hookTotalLiquidity) = hook1.settleTotalLiquidityCalls(0);

        assertEq(hookChainUID, chainUID);
        assertEq(hookTimestamp, timestamp);
        assertEq(hookTotalLiquidity, 1200e18); // total liquidity from setup
    }

    // Note: Multiple hooks test removed since we now support only single hook

    function test_onSettleTotalLiquidity_revertDoesNotBlock() public {
        // Set reverting hook
        hook1.setShouldRevertOnSettleTotalLiquidity(true);
        vm.prank(owner);
        token.setHook(address(hook1));

        // Expect failure event
        vm.expectEmit(true, true, false, false);
        emit OnSettleTotalLiquidityHookFailure(
            address(hook1),
            bytes32(uint256(30_000)),
            uint64(block.timestamp),
            1200e18,
            abi.encodeWithSignature("Error(string)", "HookMock: Intentional revert")
        );

        // Call should still succeed
        vm.prank(address(liquidityMatrix));
        token.onSettleTotalLiquidity(bytes32(uint256(30_000)), 1, uint64(block.timestamp));
    }

    function test_onSettleTotalLiquidity_revertNonLiquidityMatrix() public {
        // Try to call from non-LiquidityMatrix address
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.Forbidden.selector);
        token.onSettleTotalLiquidity(bytes32(uint256(1)), 1, uint64(block.timestamp));
    }

    /*//////////////////////////////////////////////////////////////
                      onSettleData HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onSettleData_called() public {
        // Set hook
        vm.prank(owner);
        token.setHook(address(hook1));

        // Call onSettleData as LiquidityMatrix
        bytes32 chainUID = bytes32(uint256(30_002));
        uint256 version = 1;
        uint64 timestamp = uint64(block.timestamp + 2000);
        bytes32 key = keccak256("test.key");
        // bytes memory value = abi.encode("test value", 12_345);

        vm.prank(address(liquidityMatrix));
        token.onSettleData(chainUID, version, timestamp, key);

        // Verify hook was called
        assertEq(hook1.getSettleDataCallCount(), 1);
        (bytes32 hookChainUID, uint256 hookTimestamp, bytes32 hookKey, bytes memory hookValue) =
            hook1.settleDataCalls(0);

        assertEq(hookChainUID, chainUID);
        assertEq(hookTimestamp, timestamp);
        assertEq(hookKey, key);
        assertEq(hookValue, abi.encode("test value", 12_345)); // Value is now fetched from LiquidityMatrix
    }

    // Note: Multiple hooks test removed since we now support only single hook

    function test_onSettleData_revertDoesNotBlock() public {
        // Set reverting hook
        hook1.setShouldRevertOnSettleData(true);
        vm.prank(owner);
        token.setHook(address(hook1));

        // Expect failure event (value is now fetched from LiquidityMatrix)
        vm.expectEmit(true, true, false, true);
        emit OnSettleDataHookFailure(
            address(hook1),
            bytes32(uint256(30_000)),
            uint64(block.timestamp),
            keccak256("key"),
            abi.encode("test value", 12_345),
            abi.encodeWithSignature("Error(string)", "HookMock: Intentional revert")
        );

        // Call should still succeed
        vm.prank(address(liquidityMatrix));
        token.onSettleData(bytes32(uint256(30_000)), 1, uint64(block.timestamp), keccak256("key"));
    }

    function test_onSettleData_revertNonLiquidityMatrix() public {
        // Try to call from non-LiquidityMatrix address
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.Forbidden.selector);
        token.onSettleData(bytes32(uint256(1)), 1, uint64(block.timestamp), bytes32(0));
    }

    // Note: Hook ordering tests removed since we now support only single hook

    function test_allCallbackHooks_inSettlementFlow() public {
        // Set comprehensive hook
        vm.prank(owner);
        token.setHook(address(hook1));

        // Simulate a complete settlement flow
        vm.startPrank(address(liquidityMatrix));

        // 1. Map accounts (might be called when accounts are mapped)
        token.onMapAccounts(bytes32(uint256(30_000)), makeAddr("remote1"), alice);
        assertEq(hook1.getMapAccountsCallCount(), 1);

        // 2. Settle individual liquidity
        token.onSettleLiquidity(bytes32(uint256(30_000)), 1, uint64(block.timestamp), alice);
        assertEq(hook1.getSettleLiquidityCallCount(), 1);

        // 3. Settle total liquidity
        token.onSettleTotalLiquidity(bytes32(uint256(30_000)), 1, uint64(block.timestamp));
        assertEq(hook1.getSettleTotalLiquidityCallCount(), 1);

        // 4. Settle data
        token.onSettleData(bytes32(uint256(30_000)), 1, uint64(block.timestamp), keccak256("config"));
        assertEq(hook1.getSettleDataCallCount(), 1);

        vm.stopPrank();
    }
}
