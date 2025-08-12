// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { LiquidityMatrixMock } from "./mocks/LiquidityMatrixMock.sol";
import { LayerZeroGatewayMock } from "./mocks/LayerZeroGatewayMock.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

// Hook that releases underlying tokens on burn
contract SimpleRedemptionHook is IERC20xDHook {
    using SafeTransferLib for ERC20;

    address public immutable wrappedToken;
    address public immutable underlying;

    event Redeemed(address indexed recipient, uint256 amount);

    constructor(address _wrappedToken, address _underlying) {
        wrappedToken = _wrappedToken;
        underlying = _underlying;
    }

    function afterTransfer(address from, address to, uint256 amount, bytes memory) external override {
        if (msg.sender != wrappedToken) return;
        if (to != address(0)) return; // Only process burns

        // Release underlying to the burner
        ERC20(underlying).safeTransfer(from, amount);
        emit Redeemed(from, amount);
    }

    // Empty implementations for other hooks
    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address, address) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }
}

// Hook that fails during redemption
contract FailingRedemptionHook is IERC20xDHook {
    error RedemptionFailed();

    function afterTransfer(address, address to, uint256, bytes memory) external pure override {
        if (to == address(0)) revert RedemptionFailed();
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address, address) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }
}

// Hook that tracks call order
contract OrderTrackingHook is IERC20xDHook {
    uint256 public callOrder;
    uint256 public lastCallTimestamp;
    address public lastFrom;
    address public lastTo;
    uint256 public lastAmount;

    constructor(uint256 _order) {
        callOrder = _order;
    }

    function afterTransfer(address from, address to, uint256 amount, bytes memory) external override {
        lastCallTimestamp = block.timestamp;
        lastFrom = from;
        lastTo = to;
        lastAmount = amount;
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address, address) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }
}

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
    function onMapAccounts(bytes32, address, address) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }
}

// Hook that redeems to a different recipient
contract RecipientRedemptionHook is IERC20xDHook {
    using SafeTransferLib for ERC20;

    address public immutable underlying;
    mapping(address => address) public recipientOverrides;

    constructor(address _underlying) {
        underlying = _underlying;
    }

    function setRecipientOverride(address from, address to) external {
        recipientOverrides[from] = to;
    }

    function afterTransfer(address from, address to, uint256 amount, bytes memory) external override {
        if (to != address(0)) return;

        address recipient = recipientOverrides[from] != address(0) ? recipientOverrides[from] : from;
        ERC20(underlying).safeTransfer(recipient, amount);
    }

    function onInitiateTransfer(address, address, uint256, bytes memory, uint256, bytes memory) external override { }
    function onReadGlobalAvailability(address, int256) external override { }
    function beforeTransfer(address, address, uint256, bytes memory) external override { }
    function onMapAccounts(bytes32, address, address) external override { }
    function onSettleLiquidity(bytes32, uint256, address, int256) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, int256) external override { }
    function onSettleData(bytes32, uint256, bytes32, bytes memory) external override { }
}

contract WrappedERC20xDHooksTest is Test {
    using SafeTransferLib for ERC20;

    WrappedERC20xD public wrappedToken;
    ERC20Mock public underlying;
    LiquidityMatrixMock public liquidityMatrix;
    LayerZeroGatewayMock public gateway;

    SimpleRedemptionHook public redemptionHook;
    FailingRedemptionHook public failingHook;

    address constant owner = address(0x1);
    address constant alice = address(0x2);
    address constant bob = address(0x3);
    address constant settler = address(0x4);

    event AfterTransferHookFailure(
        address indexed hook, address indexed from, address indexed to, uint256 amount, bytes reason
    );
    event Redeemed(address indexed recipient, uint256 amount);

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

        // Set read target for local chain (chain ID 1 from gateway mock)
        vm.prank(owner);
        // gateway.registerReader(address(wrappedToken)); // Mock gateway doesn't have this
        wrappedToken.updateReadTarget(bytes32(uint256(1)), bytes32(uint256(uint160(address(wrappedToken)))));

        // Deploy hooks
        redemptionHook = new SimpleRedemptionHook(address(wrappedToken), address(underlying));
        failingHook = new FailingRedemptionHook();

        // Setup test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        underlying.mint(alice, 1000e6);
        underlying.mint(bob, 1000e6);
        underlying.mint(address(redemptionHook), 10_000e6); // Fund hook for redemptions

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
                     BASIC UNWRAP WITH HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrapWithRedemptionHook() public {
        // Add redemption hook
        vm.prank(owner);
        wrappedToken.addHook(address(redemptionHook));

        // Alice wraps tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);
        assertEq(wrappedToken.balanceOf(alice), 100e6);
        assertEq(underlying.balanceOf(alice), 900e6);

        // Alice unwraps tokens
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "");

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
        wrappedToken.addHook(address(redemptionHook));

        // Wrap and unwrap full amount
        vm.prank(alice);
        wrappedToken.wrap(alice, 200e6);

        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 200e6, "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify complete redemption
        assertEq(wrappedToken.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(alice), 1000e6); // Back to original
    }

    /*//////////////////////////////////////////////////////////////
                     FAILING HOOK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrapWithFailingHook_stillBurnsTokens() public {
        // Add failing hook
        vm.prank(owner);
        wrappedToken.addHook(address(failingHook));

        // Alice wraps tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        // Alice unwraps - hook fails but tokens still burn
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "");

        // Simulate gateway response - hook failure happens here
        vm.expectEmit(true, true, true, false);
        emit AfterTransferHookFailure(address(failingHook), alice, address(0), 50e6, "");

        _simulateGatewayResponse(1, 0);

        // Verify: Tokens burned even though hook failed
        assertEq(wrappedToken.balanceOf(alice), 50e6);
        // Underlying not redeemed because hook failed
        assertEq(underlying.balanceOf(alice), 900e6);
    }

    function test_unwrapWithMultipleHooks_oneFails() public {
        // Add both hooks
        vm.prank(owner);
        wrappedToken.addHook(address(redemptionHook));
        vm.prank(owner);
        wrappedToken.addHook(address(failingHook));

        // Wrap tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        // Unwrap - redemption succeeds, failing hook fails
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 30e6, "");

        // Simulate gateway response - both events happen here
        vm.expectEmit(true, false, false, true);
        emit Redeemed(alice, 30e6);

        _simulateGatewayResponse(1, 0);

        // Verify: Redemption still happened despite one hook failing
        assertEq(wrappedToken.balanceOf(alice), 70e6);
        assertEq(underlying.balanceOf(alice), 930e6); // Redeemed despite failure
    }

    /*//////////////////////////////////////////////////////////////
                     MULTIPLE HOOKS ORDERING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_multipleHooksExecutionOrder() public {
        OrderTrackingHook hook1 = new OrderTrackingHook(1);
        OrderTrackingHook hook2 = new OrderTrackingHook(2);
        OrderTrackingHook hook3 = new OrderTrackingHook(3);

        // Add hooks in order
        vm.startPrank(owner);
        wrappedToken.addHook(address(hook1));
        wrappedToken.addHook(address(hook2));
        wrappedToken.addHook(address(hook3));
        vm.stopPrank();

        // Wrap and unwrap
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 25e6, "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify all hooks were called with correct parameters
        assertEq(hook1.lastFrom(), alice);
        assertEq(hook1.lastTo(), address(0));
        assertEq(hook1.lastAmount(), 25e6);

        assertEq(hook2.lastFrom(), alice);
        assertEq(hook2.lastTo(), address(0));
        assertEq(hook2.lastAmount(), 25e6);

        assertEq(hook3.lastFrom(), alice);
        assertEq(hook3.lastTo(), address(0));
        assertEq(hook3.lastAmount(), 25e6);
    }

    /*//////////////////////////////////////////////////////////////
                     NO HOOKS SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrapWithNoHooks() public {
        // Wrap tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        // Unwrap without any hooks
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 40e6, "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify: Tokens burned but no redemption
        assertEq(wrappedToken.balanceOf(alice), 60e6);
        assertEq(underlying.balanceOf(alice), 900e6); // No change
    }

    /*//////////////////////////////////////////////////////////////
                     DATA PARAMETER USAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_dataParameterPropagation() public {
        DataUsingHook dataHook = new DataUsingHook();

        vm.prank(owner);
        wrappedToken.addHook(address(dataHook));

        // Wrap tokens
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        // Unwrap with data
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        bytes memory data = abi.encode(uint128(300_000), bob);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 20e6, data);

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
        wrappedToken.addHook(address(redemptionHook));

        // Multiple users wrap
        vm.prank(alice);
        wrappedToken.wrap(alice, 200e6);

        vm.prank(bob);
        wrappedToken.wrap(bob, 300e6);

        // Both unwrap concurrently
        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 100e6, "");

        vm.prank(bob);
        wrappedToken.unwrap{ value: fee }(bob, 150e6, "");

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
        wrappedToken.addHook(address(recipientHook));

        // Alice wraps and unwraps
        vm.prank(alice);
        wrappedToken.wrap(alice, 100e6);

        uint256 fee = wrappedToken.quoteTransfer(alice, 500_000);
        vm.prank(alice);
        wrappedToken.unwrap{ value: fee }(alice, 50e6, "");

        // Simulate gateway response
        _simulateGatewayResponse(1, 0);

        // Verify: Alice's tokens burned, but bob received underlying
        assertEq(wrappedToken.balanceOf(alice), 50e6);
        assertEq(underlying.balanceOf(alice), 900e6); // No change
        assertEq(underlying.balanceOf(bob), 1050e6); // Received redemption
    }
}
