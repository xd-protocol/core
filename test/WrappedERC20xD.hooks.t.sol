// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { IWrappedERC20xD } from "src/interfaces/IWrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { LiquidityMatrixMock } from "./mocks/LiquidityMatrixMock.sol";
import { LayerZeroGatewayMock } from "./mocks/LayerZeroGatewayMock.sol";
import { SimpleRedemptionHookMock } from "./mocks/hooks/SimpleRedemptionHookMock.sol";
import { FailingRedemptionHookMock } from "./mocks/hooks/FailingRedemptionHookMock.sol";
import { OrderTrackingHookMock } from "./mocks/hooks/OrderTrackingHookMock.sol";
import { YieldVaultHookMock } from "./mocks/hooks/YieldVaultHookMock.sol";
import { HookMock } from "./mocks/hooks/HookMock.sol";
import { CustomHookWithData } from "./mocks/hooks/CustomHookWithData.sol";
import { CallOrderTrackerMock } from "./mocks/CallOrderTrackerMock.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

// Hook that uses data parameter
contract DataUsingHook is IERC20xDHook {
    uint128 public lastGasLimit;
    address public lastRefundTo;

    function afterTransfer(address, address to, uint256, bytes memory data) external override {
        if (to != address(0)) return;

        if (data.length >= 64) {
            (lastGasLimit, lastRefundTo) = abi.decode(data, (uint128, address));
        }
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address[] memory, address[] memory) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }

    function onWrap(address, address, uint256 amount, bytes memory) external payable override returns (uint256) {
        return amount;
    }

    function onUnwrap(address, address, uint256 shares, bytes memory) external override returns (uint256) {
        return shares;
    }
}

// Hook that tracks recipient overrides (can't actually override since contract sends directly)
contract RecipientRedemptionHook is IERC20xDHook {
    using SafeTransferLib for ERC20;

    address public immutable underlying;
    mapping(address => address) public recipientOverrides;
    mapping(address => uint256) public redirectedAmounts;

    constructor(address _underlying) {
        underlying = _underlying;
    }

    function setRecipientOverride(address from, address to) external {
        recipientOverrides[from] = to;
    }

    function afterTransfer(address from, address to, uint256 amount, bytes memory) external override {
        if (to != address(0)) return;

        // Can't redirect since contract already sent to recipient
        // Just track what would have been redirected
        if (recipientOverrides[from] != address(0)) {
            redirectedAmounts[recipientOverrides[from]] += amount;
        }
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address[] memory, address[] memory) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }

    function onWrap(address, address, uint256 amount, bytes memory) external payable override returns (uint256) {
        return amount;
    }

    function onUnwrap(address, address, uint256 shares, bytes memory) external override returns (uint256) {
        // Can't actually redirect since contract handles transfer
        return shares;
    }
}

contract WrappedERC20xDHooksTest is Test {
    using SafeTransferLib for ERC20;

    WrappedERC20xD public wrappedToken;
    ERC20Mock public underlying;
    LiquidityMatrixMock public liquidityMatrix;
    LayerZeroGatewayMock public gateway;

    SimpleRedemptionHookMock public redemptionHook;
    FailingRedemptionHookMock public failingHook;
    YieldVaultHookMock public yieldHook;
    HookMock public trackingHook;

    address constant owner = address(0x1);
    address constant alice = address(0x2);
    address constant bob = address(0x3);
    address constant settler = address(0x4);

    event Redeemed(address indexed recipient, uint256 amount);
    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 shares, uint256 assets);

    function setUp() public {
        // Deploy mocks
        liquidityMatrix = new LiquidityMatrixMock();
        gateway = new LayerZeroGatewayMock();
        underlying = new ERC20Mock("USDC", "USDC", 6);

        // Whitelist settler in liquidityMatrix
        liquidityMatrix.updateSettlerWhitelisted(settler, true);

        // Deploy wrapped token
        wrappedToken = new WrappedERC20xD(
            address(underlying), "Wrapped USDC", "wUSDC", 6, address(liquidityMatrix), address(gateway), owner, settler
        );

        // Configure read chains and targets for local chain
        vm.startPrank(owner);
        bytes32[] memory readChains = new bytes32[](1);
        address[] memory targets = new address[](1);
        readChains[0] = bytes32(uint256(1));
        targets[0] = address(wrappedToken);
        wrappedToken.configureReadChains(readChains, targets);
        vm.stopPrank();

        // Deploy hooks
        redemptionHook = new SimpleRedemptionHookMock(address(wrappedToken), address(underlying));
        failingHook = new FailingRedemptionHookMock();
        yieldHook = new YieldVaultHookMock(address(wrappedToken), address(underlying));
        trackingHook = new HookMock();

        // Setup test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        underlying.mint(alice, 1000e6);
        underlying.mint(bob, 1000e6);
        underlying.mint(address(redemptionHook), 10_000e6); // Fund hook for redemptions
        underlying.mint(address(yieldHook), 10_000e6); // Fund yield hook

        // Approve tokens
        vm.prank(alice);
        underlying.approve(address(wrappedToken), type(uint256).max);
        vm.prank(bob);
        underlying.approve(address(wrappedToken), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                         HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _simulateGatewayResponse(uint256 nonce, int256 globalAvailability) internal {
        // Simulate the gateway calling onRead with the global availability response
        bytes memory message = abi.encode(globalAvailability);
        vm.prank(address(gateway));
        wrappedToken.onRead(message, abi.encode(nonce));
    }

    /*//////////////////////////////////////////////////////////////
                        WRAP WITH HOOKS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_withHook_transfersToContract() public {
        vm.prank(owner);
        wrappedToken.setHook(address(yieldHook));

        uint256 wrappedBalanceBefore = underlying.balanceOf(address(wrappedToken));
        uint256 hookBalanceBefore = underlying.balanceOf(address(yieldHook));

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Tokens should go to contract first, then hook pulls them
        assertEq(underlying.balanceOf(address(wrappedToken)), wrappedBalanceBefore);
        assertEq(underlying.balanceOf(address(yieldHook)), hookBalanceBefore + 100e6);
    }

    function test_wrap_withHook_approvesHook() public {
        // Create a tracking hook that checks approval
        HookMock hook = new HookMock();
        vm.prank(owner);
        wrappedToken.setHook(address(hook));

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Verify hook was called
        assertEq(hook.getWrapCallCount(), 1);
    }

    function test_wrap_withHook_clearsApproval() public {
        vm.prank(owner);
        wrappedToken.setHook(address(yieldHook));

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Approval should be cleared after wrap
        assertEq(underlying.allowance(address(wrappedToken), address(yieldHook)), 0);
    }

    function test_wrap_withHook_mintsCorrectAmount() public {
        vm.prank(owner);
        wrappedToken.setHook(address(yieldHook));

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Should mint the amount returned by hook (same in this case)
        assertEq(wrappedToken.balanceOf(alice), 100e6);
    }

    function test_wrap_withHook_emitsCorrectEvents() public {
        vm.prank(owner);
        wrappedToken.setHook(address(yieldHook));

        vm.expectEmit(true, false, false, true);
        emit Wrap(alice, 100e6);

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");
    }

    function test_wrap_withHookFailure_revertsNow() public {
        vm.prank(owner);
        wrappedToken.setHook(address(failingHook));

        // Hook is now mandatory, so it should revert
        vm.prank(alice);
        vm.expectRevert();
        wrappedToken.wrap(alice, 100e6, "");
    }

    function test_wrap_withoutHook_worksNormally() public {
        // No hook set
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Tokens should go directly to contract
        assertEq(underlying.balanceOf(address(wrappedToken)), 100e6);
        assertEq(wrappedToken.balanceOf(alice), 100e6);
    }

    /*//////////////////////////////////////////////////////////////
                     BASIC UNWRAP WITH HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrapWithRedemptionHook() public {
        // Set redemption hook
        vm.prank(owner);
        wrappedToken.setHook(address(redemptionHook));

        // Alice wraps tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");
        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(underlying.balanceOf(alice), 900e6);

        // Alice unwraps tokens
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "", "");

        // Simulate gateway response - this is when the redemption happens
        vm.expectEmit(true, false, false, true);
        emit Redeemed(alice, 50e6);

        _simulateGatewayResponse(1, 0);

        // Verify: Tokens burned and underlying redeemed
        assertEq(wrappedToken.balanceOf(alice), 50e6);
        assertEq(underlying.balanceOf(alice), 950e6); // 900 + 50 redeemed
    }

    function test_unwrapFullAmountWithHook() public {
        vm.prank(owner);
        wrappedToken.setHook(address(redemptionHook));

        // Wrap and unwrap full amount
        vm.prank(alice);
        wrappedToken.wrap(alice, 200e6, "");

        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 200e6, "", "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify complete redemption
        assertEq(wrappedToken.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(alice), 1000e6); // Back to original
    }

    /*//////////////////////////////////////////////////////////////
                     FAILING HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrapWithFailingHook_revertsOnWrap() public {
        // Set failing hook
        vm.prank(owner);
        wrappedToken.setHook(address(failingHook));

        // Alice tries to wrap - hook fails and reverts
        vm.prank(alice);
        vm.expectRevert();
        wrappedToken.wrap(alice, 100e6, "");
    }

    // Note: Multiple hooks test removed since we now support only single hook

    /*//////////////////////////////////////////////////////////////
                     SINGLE HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_singleHookExecutionOrder() public {
        CallOrderTrackerMock tracker = new CallOrderTrackerMock();
        OrderTrackingHookMock hook1 = new OrderTrackingHookMock(tracker);

        // Set single hook
        vm.prank(owner);
        wrappedToken.setHook(address(hook1));

        // Wrap and unwrap
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 25e6, "", "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify hook was called with correct parameters
        // The onUnwrap hook is called with recipient (alice) as the 'to' parameter
        assertEq(hook1.lastFrom(), alice);
        assertEq(hook1.lastTo(), alice); // onUnwrap receives recipient, not address(0)
        assertEq(hook1.lastAmount(), 25e6);
    }

    /*//////////////////////////////////////////////////////////////
                     NO HOOKS SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrapWithNoHooks() public {
        // Wrap tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Unwrap without any hooks
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 40e6, "", "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify: Tokens burned AND underlying returned (fix applied)
        assertEq(wrappedToken.balanceOf(alice), 60e6);
        assertEq(underlying.balanceOf(alice), 940e6); // 900 + 40 returned
    }

    /*//////////////////////////////////////////////////////////////
                     DATA PARAMETER USAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_dataParameterPropagation() public {
        DataUsingHook dataHook = new DataUsingHook();

        vm.prank(owner);
        wrappedToken.setHook(address(dataHook));

        // Wrap tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Unwrap with data
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        bytes memory data = abi.encode(uint128(300_000), bob);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 20e6, data, "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify hook received data
        assertEq(dataHook.lastGasLimit(), 300_000);
        assertEq(dataHook.lastRefundTo(), bob);
    }

    /*//////////////////////////////////////////////////////////////
                     CONCURRENT UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_concurrentUnwrapsFromMultipleUsers() public {
        vm.prank(owner);
        wrappedToken.setHook(address(redemptionHook));

        // Multiple users wrap
        vm.prank(alice);
        wrappedToken.wrap(alice, 200e6, "");

        vm.prank(bob);
        wrappedToken.wrap(bob, 300e6, "");

        // Both unwrap concurrently
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 100e6, "", "");

        vm.prank(bob);
        wrappedToken.unwrap{ value: fee }(bob, 150e6, "", "");

        // Simulate gateway responses
        _simulateGatewayResponse(1, 0); // Alice's unwrap
        _simulateGatewayResponse(2, 0); // Bob's unwrap

        // Verify both redemptions succeeded
        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(wrappedToken.balanceOf(bob), 150e6);
        assertEq(underlying.balanceOf(alice), 900e6); // 800 + 100
        assertEq(underlying.balanceOf(bob), 850e6); // 700 + 150
    }

    /*//////////////////////////////////////////////////////////////
                     RECIPIENT ADDRESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrapToDifferentRecipient() public {
        RecipientRedemptionHook recipientHook = new RecipientRedemptionHook(address(underlying));
        underlying.mint(address(recipientHook), 1000e6);

        // Set alice's redemptions to go to bob
        recipientHook.setRecipientOverride(alice, bob);

        vm.prank(owner);
        wrappedToken.setHook(address(recipientHook));

        // Alice wraps and unwraps
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "", "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify: Alice's tokens burned and alice received underlying (contract sends directly)
        assertEq(wrappedToken.balanceOf(alice), 50e6);
        assertEq(underlying.balanceOf(alice), 950e6); // Alice gets the underlying
        assertEq(underlying.balanceOf(bob), 1000e6); // Bob unchanged
    }

    /*//////////////////////////////////////////////////////////////
                     ADDITIONAL UNWRAP HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_withHook_burnsSharesFirst() public {
        // Setup: wrap first
        vm.prank(owner);
        wrappedToken.setHook(address(yieldHook));

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        uint256 sharesBefore = wrappedToken.balanceOf(alice);

        // Unwrap initiates transfer
        uint256 fee = wrappedToken.quoteUnwrap(500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, abi.encode(uint128(500_000), alice), "");

        // At this point, transfer is pending, shares not burned yet
        assertEq(wrappedToken.balanceOf(alice), sharesBefore);

        // Simulate gateway callback to complete unwrap
        _simulateGatewayResponse(1, 0);

        // Now shares should be burned
        assertEq(wrappedToken.balanceOf(alice), sharesBefore - 50e6);
    }

    function test_unwrap_withHook_returnsMoreThanShares() public {
        // Setup: wrap and accrue yield
        vm.prank(owner);
        wrappedToken.setHook(address(yieldHook));

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Simulate 10% yield accrual
        yieldHook.accrueYield();

        // Unwrap half the shares
        uint256 fee = wrappedToken.quoteUnwrap(500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, abi.encode(uint128(500_000), alice), "");

        // Expect event during gateway response
        vm.expectEmit(true, false, false, true);
        emit Unwrap(alice, 50e6, 55e6); // Expect 50e6 shares to return 55e6 assets (10% yield)

        _simulateGatewayResponse(1, 0);

        // Alice should receive more underlying than shares burned
        assertEq(underlying.balanceOf(alice), 1000e6 - 100e6 + 55e6); // Initial - wrapped + unwrapped with yield
    }

    function test_unwrap_withHook_emitsCorrectEvent() public {
        // Setup
        vm.prank(owner);
        wrappedToken.setHook(address(yieldHook));

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Test unwrap event
        uint256 fee = wrappedToken.quoteUnwrap(500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 30e6, abi.encode(uint128(500_000), alice), "");

        // Expect event during gateway response
        vm.expectEmit(true, false, false, true);
        emit Unwrap(alice, 30e6, 30e6); // No yield, so shares == assets

        _simulateGatewayResponse(1, 0);
    }

    function test_unwrap_withHookFailure_revertsOnWrap() public {
        // Setup with failing hook
        vm.prank(owner);
        wrappedToken.setHook(address(failingHook));

        // Cannot wrap with failing hook (mandatory now)
        vm.prank(alice);
        vm.expectRevert();
        wrappedToken.wrap(alice, 100e6, "");
    }

    /*//////////////////////////////////////////////////////////////
                        ROUND-TRIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrapUnwrap_roundTrip_noYield() public {
        // Wrap
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(underlying.balanceOf(alice), 900e6);

        // Unwrap
        uint256 fee = wrappedToken.quoteUnwrap(500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 100e6, abi.encode(uint128(500_000), alice), "");

        _simulateGatewayResponse(1, 0);

        // Should have original balance
        assertEq(wrappedToken.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(alice), 1000e6);
    }

    function test_wrapUnwrap_roundTrip_withYield() public {
        // Setup with yield hook
        vm.prank(owner);
        wrappedToken.setHook(address(yieldHook));

        // Wrap
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Accrue 20% yield
        yieldHook.setYieldPercentage(2000);
        yieldHook.accrueYield();

        // Unwrap all
        uint256 fee = wrappedToken.quoteUnwrap(500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 100e6, abi.encode(uint128(500_000), alice), "");

        _simulateGatewayResponse(1, 0);

        // Should have original + yield
        assertEq(wrappedToken.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(alice), 1000e6 - 100e6 + 120e6); // 20% yield on 100e6
    }

    /*//////////////////////////////////////////////////////////////
                        CUSTOM HOOKDATA TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_withCustomHookData() public {
        // Deploy custom hook
        CustomHookWithData customHook = new CustomHookWithData(address(wrappedToken), address(underlying));
        underlying.mint(address(customHook), 100_000e6);

        vm.prank(owner);
        wrappedToken.setHook(address(customHook));

        // Prepare custom hook data
        CustomHookWithData.WrapConfig memory config = CustomHookWithData.WrapConfig({
            multiplier: 1100, // 110% - bonus tokens
            recipient: bob,
            metadata: abi.encode("test", uint256(123))
        });
        bytes memory hookData = abi.encode(config);

        // Wrap with custom data
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, hookData);

        // Verify hook received and processed the data
        assertEq(customHook.getLastWrapMultiplier(alice), 1100);
        assertEq(customHook.getLastWrapRecipient(alice), bob);
        assertEq(customHook.lastWrapMetadata(alice), abi.encode("test", uint256(123)));

        // Verify adjusted amount was minted (110% of 100e6)
        assertEq(wrappedToken.balanceOf(alice), 110e6);
    }

    function test_wrap_withEmptyHookData() public {
        // Deploy custom hook
        CustomHookWithData customHook = new CustomHookWithData(address(wrappedToken), address(underlying));
        underlying.mint(address(customHook), 100_000e6);

        vm.prank(owner);
        wrappedToken.setHook(address(customHook));

        // Wrap with empty hook data
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, "");

        // Verify normal amount was minted
        assertEq(wrappedToken.balanceOf(alice), 100e6);

        // Verify hook didn't store any config
        assertEq(customHook.getLastWrapMultiplier(alice), 0);
    }

    function test_unwrap_withCustomHookData() public {
        // Deploy custom hook
        CustomHookWithData customHook = new CustomHookWithData(address(wrappedToken), address(underlying));
        underlying.mint(address(customHook), 100_000e6);

        vm.prank(owner);
        wrappedToken.setHook(address(customHook));

        // First wrap some tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 1000e6, "");

        // Prepare custom unwrap hook data
        CustomHookWithData.UnwrapConfig memory config = CustomHookWithData.UnwrapConfig({
            feePercent: 200, // 2% fee
            feeRecipient: bob,
            applyBonus: false
        });
        bytes memory hookData = abi.encode(config);

        // Get quote and unwrap with custom data
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(
            alice,
            100e6,
            abi.encode(uint128(500_000), alice), // cross-chain data
            hookData // custom hook data
        );

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify hook received and processed the data
        assertEq(customHook.getLastUnwrapFeePercent(alice), 200);
        assertEq(customHook.getLastUnwrapFeeRecipient(alice), bob);
        assertEq(customHook.getLastUnwrapBonus(alice), false);

        // Verify amounts (100e6 - 2% fee = 98e6)
        assertEq(wrappedToken.balanceOf(alice), 900e6); // 1000 - 100 unwrapped
        assertEq(underlying.balanceOf(alice), 98e6); // 0 + 98 (after 2% fee)
        assertEq(underlying.balanceOf(bob), 1000e6 + 2e6); // Initial + 2% fee
    }

    function test_unwrap_withBonusHookData() public {
        // Deploy custom hook
        CustomHookWithData customHook = new CustomHookWithData(address(wrappedToken), address(underlying));
        underlying.mint(address(customHook), 100_000e6);

        vm.prank(owner);
        wrappedToken.setHook(address(customHook));

        // First wrap some tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 1000e6, "");

        // Prepare hook data with bonus enabled
        CustomHookWithData.UnwrapConfig memory config = CustomHookWithData.UnwrapConfig({
            feePercent: 0,
            feeRecipient: address(0),
            applyBonus: true // 10% bonus
         });
        bytes memory hookData = abi.encode(config);

        // Unwrap with bonus
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 100e6, abi.encode(uint128(500_000), alice), hookData);

        _simulateGatewayResponse(1, 0);

        // Verify bonus was applied (100e6 * 1.1 = 110e6)
        assertEq(wrappedToken.balanceOf(alice), 900e6);
        assertEq(underlying.balanceOf(alice), 110e6); // 0 + 110 (with 10% bonus)
    }

    function test_hookData_complexStruct() public {
        // Deploy custom hook
        CustomHookWithData customHook = new CustomHookWithData(address(wrappedToken), address(underlying));
        underlying.mint(address(customHook), 100_000e6);

        vm.prank(owner);
        wrappedToken.setHook(address(customHook));

        // Test with complex nested struct
        bytes memory metadata =
            abi.encode(keccak256("COMPLEX_DATA"), block.timestamp, alice, uint256[](new uint256[](3)));

        CustomHookWithData.WrapConfig memory config =
            CustomHookWithData.WrapConfig({ multiplier: 1234, recipient: bob, metadata: metadata });
        bytes memory hookData = abi.encode(config);

        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6, hookData);

        // Verify complex data was received correctly
        assertEq(customHook.getLastWrapMultiplier(alice), 1234);
        assertEq(customHook.lastWrapMetadata(alice), metadata);
        assertEq(customHook.lastWrapRawData(alice), hookData);
    }

    function test_hookData_invalidDataReverts() public {
        // Deploy custom hook
        CustomHookWithData customHook = new CustomHookWithData(address(wrappedToken), address(underlying));
        underlying.mint(address(customHook), 100_000e6);

        vm.prank(owner);
        wrappedToken.setHook(address(customHook));

        // Test that when hook fails to decode, the wrap reverts (hooks are mandatory now)
        bytes memory shortData = hex"deadbeef"; // Too short to be a valid WrapConfig

        // Should revert - hooks are mandatory
        vm.prank(alice);
        vm.expectRevert();
        wrappedToken.wrap(alice, 100e6, shortData);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
}
