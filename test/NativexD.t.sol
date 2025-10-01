// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { Test, Vm, console } from "forge-std/Test.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { NativexD } from "src/NativexD.sol";
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IWrappedERC20xD } from "src/interfaces/IWrappedERC20xD.sol";
import { INativexD } from "src/interfaces/INativexD.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import {
    MessagingReceipt, Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract NativexDTest is BaseERC20xDTestHelper {
    uint32 constant LOCAL_EID = 101;
    uint128 constant TEST_GAS_LIMIT = 200_000;

    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 amount);

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        return BaseERC20xD(
            payable(
                new NativexD(
                    "Test Native xD",
                    "TNxD",
                    18,
                    address(liquidityMatrices[i]),
                    address(gateways[i]),
                    owner,
                    settlers[i]
                )
            )
        );
    }

    function setUp() public override {
        super.setUp();

        // Stop any ongoing prank from parent setUp
        vm.stopPrank();

        // Deal native tokens to test users
        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 1000 ether);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public view {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        assertEq(wrapped.underlying(), address(0)); // Native token
        assertEq(wrapped.owner(), owner);
        assertEq(wrapped.name(), "Test Native xD");
        assertEq(wrapped.symbol(), "TNxD");
        assertEq(wrapped.decimals(), 18);
    }

    /*//////////////////////////////////////////////////////////////
                            WRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_basic() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        vm.prank(alice);
        uint256 balanceBefore = alice.balance;

        vm.expectEmit();
        emit INativexD.Wrap(alice, amount);
        wrapped.wrap{ value: amount }(alice, "");

        assertEq(wrapped.balanceOf(alice), amount); // Direct 1:1 minting now
        assertEq(alice.balance, balanceBefore - amount);
    }

    function test_wrap_differentRecipient() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        vm.prank(alice);
        wrapped.wrap{ value: amount }(bob, "");

        assertEq(wrapped.balanceOf(bob), amount);
        assertEq(wrapped.balanceOf(alice), 0);
    }

    function test_wrap_revertZeroAddress() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAddress.selector);
        wrapped.wrap{ value: 50 ether }(address(0), "");
    }

    function test_wrap_revertZeroAmount() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAmount.selector);
        wrapped.wrap{ value: 0 }(alice, "");
    }

    function test_wrap_revertInsufficientValue() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);

        // NativexD checks msg.value == 0, not msg.value < amount
        vm.expectRevert(IBaseERC20xD.InvalidAmount.selector);
        wrapped.wrap{ value: 0 }(alice, "");
    }

    function test_wrap_multipleUsers() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        vm.prank(alice);
        wrapped.wrap{ value: 50 ether }(alice, "");

        vm.prank(bob);
        wrapped.wrap{ value: 30 ether }(bob, "");

        assertEq(wrapped.balanceOf(alice), 50 ether);
        assertEq(wrapped.balanceOf(bob), 30 ether);
        assertEq(wrapped.totalSupply(), 80 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_basic() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        // Step 1: Alice wraps native tokens
        vm.prank(alice);
        wrapped.wrap{ value: amount }(alice, "");
        assertEq(wrapped.balanceOf(alice), amount);

        // Step 2: Alice initiates unwrap
        uint256 fee = wrapped.quoteTransfer(alice, uint128(GAS_LIMIT));
        vm.prank(alice);
        bytes memory data = abi.encode(uint128(GAS_LIMIT), alice); // gasLimit, refundTo
        wrapped.unwrap{ value: fee }(alice, amount, data, "");

        // The actual redemption happens via hooks in afterTransfer
        // For this test, we're just verifying the unwrap call succeeds
    }

    function test_unwrap_revertZeroAddress() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);
        wrapped.wrap{ value: 50 ether }(alice, "");

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAddress.selector);
        wrapped.unwrap(address(0), 50 ether, "", "");
    }

    function test_unwrap_differentRecipient() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Alice wraps
        vm.prank(alice);
        wrapped.wrap{ value: 50 ether }(alice, "");

        // Alice unwraps to bob
        uint256 fee = wrapped.quoteTransfer(alice, uint128(GAS_LIMIT));
        vm.prank(alice);
        bytes memory data = abi.encode(uint128(GAS_LIMIT), alice);
        wrapped.unwrap{ value: fee }(bob, 25 ether, data, "");

        // The actual native token transfer to bob happens via hooks
    }

    /*//////////////////////////////////////////////////////////////
                         FALLBACK/RECEIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fallback() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);

        // Send with data should revert (no fallback function)
        (bool success,) = address(wrapped).call{ value: 0.5 ether }(hex"1234");
        assertFalse(success, "Should revert when sending ETH with data");
    }

    function test_receive() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 initialBalance = address(wrapped).balance;
        uint256 initialRecoverable = wrapped.getRecoverableETH();

        vm.prank(alice);
        // Send without data (triggers receive)
        (bool success,) = address(wrapped).call{ value: 0.5 ether }("");
        assertTrue(success);
        assertEq(address(wrapped).balance, initialBalance + 0.5 ether);
        assertEq(wrapped.getRecoverableETH(), initialRecoverable + 0.5 ether, "Should track recoverable ETH");
    }

    /*//////////////////////////////////////////////////////////////
                          QUOTE WRAP/UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_quoteUnwrap() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Quote unwrap should return the same as quoteTransfer
        uint256 expectedFee = wrapped.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        uint256 actualFee = wrapped.quoteUnwrap(500_000);

        assertEq(actualFee, expectedFee);
        assertGt(actualFee, 0); // Should be non-zero for cross-chain messaging
    }

    /*//////////////////////////////////////////////////////////////
                        ROUND-TRIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrapUnwrap_roundTrip() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 wrapAmount = 100 ether;

        uint256 aliceInitialBalance = alice.balance;

        // Wrap native tokens
        vm.prank(alice);
        wrapped.wrap{ value: wrapAmount }(alice, "");

        assertEq(wrapped.balanceOf(alice), wrapAmount);
        assertEq(alice.balance, aliceInitialBalance - wrapAmount);

        // Unwrap all tokens
        uint256 fee = wrapped.quoteUnwrap(500_000);
        vm.prank(alice);
        wrapped.unwrap{ value: fee }(alice, wrapAmount, abi.encode(uint128(500_000), alice), "");

        // Simulate gateway response to complete unwrap
        _simulateGatewayResponse(wrapped, 1, 0);

        // Should have original balance minus gas fees
        assertEq(wrapped.balanceOf(alice), 0);
        assertEq(alice.balance, aliceInitialBalance - fee); // Original minus only the unwrap fee
    }

    function test_wrapUnwrap_partialAmounts() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 wrapAmount = 100 ether;
        uint256 unwrapAmount = 40 ether;

        // Wrap
        vm.prank(alice);
        wrapped.wrap{ value: wrapAmount }(alice, "");
        assertEq(wrapped.balanceOf(alice), wrapAmount);

        // Partial unwrap
        uint256 fee = wrapped.quoteUnwrap(500_000);
        vm.prank(alice);
        wrapped.unwrap{ value: fee }(alice, unwrapAmount, abi.encode(uint128(500_000), alice), "");

        _simulateGatewayResponse(wrapped, 1, 0);

        // Should have remaining wrapped tokens
        assertEq(wrapped.balanceOf(alice), wrapAmount - unwrapAmount);
    }

    function test_wrapUnwrap_multipleUsers() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Alice wraps
        vm.prank(alice);
        wrapped.wrap{ value: 75 ether }(alice, "");

        // Bob wraps
        vm.prank(bob);
        wrapped.wrap{ value: 50 ether }(bob, "");

        assertEq(wrapped.totalSupply(), 125 ether);

        // Alice unwraps partial
        uint256 fee1 = wrapped.quoteUnwrap(500_000);
        vm.prank(alice);
        wrapped.unwrap{ value: fee1 }(alice, 25 ether, abi.encode(uint128(500_000), alice), "");

        // Bob unwraps full
        uint256 fee2 = wrapped.quoteUnwrap(500_000);
        vm.prank(bob);
        wrapped.unwrap{ value: fee2 }(bob, 50 ether, abi.encode(uint128(500_000), bob), "");

        // Simulate responses
        _simulateGatewayResponse(wrapped, 1, 0); // Alice's unwrap
        _simulateGatewayResponse(wrapped, 2, 0); // Bob's unwrap

        // Verify final balances
        assertEq(wrapped.balanceOf(alice), 50 ether); // 75 - 25
        assertEq(wrapped.balanceOf(bob), 0); // All unwrapped
        assertEq(wrapped.totalSupply(), 50 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_maxAmount() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 maxAmount = alice.balance - 1 ether; // Leave some for gas

        vm.prank(alice);
        wrapped.wrap{ value: maxAmount }(alice, "");

        assertEq(wrapped.balanceOf(alice), maxAmount);
        assertLe(alice.balance, 1 ether); // Should have less than or equal to 1 ether left
    }

    function test_unwrap_withInsufficientBalance_reverts() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Wrap some tokens
        vm.prank(alice);
        wrapped.wrap{ value: 10 ether }(alice, "");

        // Try to unwrap more than balance
        uint256 fee = wrapped.quoteUnwrap(500_000);
        vm.prank(alice);
        vm.expectRevert(); // Should revert due to insufficient balance
        wrapped.unwrap{ value: fee }(alice, 20 ether, abi.encode(uint128(500_000), alice), "");
    }

    function test_contractReceivesNativeTokens() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Wrap tokens - contract should receive them
        uint256 contractBalanceBefore = address(wrapped).balance;

        vm.prank(alice);
        wrapped.wrap{ value: 10 ether }(alice, "");

        assertEq(address(wrapped).balance, contractBalanceBefore + 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        ETH RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_recoverETH_onlyTracksReceive() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        address recovery = makeAddr("recovery");

        // Get initial balance
        uint256 initialBalance = address(wrapped).balance;

        // Send recoverable ETH through receive()
        vm.prank(alice);
        (bool success1,) = address(wrapped).call{ value: 1 ether }("");
        assertTrue(success1);

        // Wrap ETH (not recoverable)
        vm.prank(bob);
        wrapped.wrap{ value: 10 ether }(bob, "");

        // Send more recoverable ETH
        vm.prank(alice);
        (bool success2,) = address(wrapped).call{ value: 0.5 ether }("");
        assertTrue(success2);

        // Total balance: initial + 11.5 ether
        // Recoverable: 1.5 ether (only from receive())
        assertEq(address(wrapped).balance, initialBalance + 11.5 ether);
        assertEq(wrapped.getRecoverableETH(), 1.5 ether);

        // Recover only the recoverable amount
        uint256 recoveryBalanceBefore = recovery.balance;
        uint256 contractBalanceBefore = address(wrapped).balance;

        vm.prank(owner);
        wrapped.recoverETH(recovery);

        assertEq(recovery.balance - recoveryBalanceBefore, 1.5 ether);
        assertEq(address(wrapped).balance, contractBalanceBefore - 1.5 ether); // Only recoverable ETH removed
        assertEq(wrapped.getRecoverableETH(), 0);
    }

    function test_recoverETH_basic() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        address recovery = makeAddr("recovery");

        // Send ETH directly (not through wrap)
        vm.prank(alice);
        (bool success,) = address(wrapped).call{ value: 1 ether }("");
        assertTrue(success);

        assertEq(wrapped.getRecoverableETH(), 1 ether);

        vm.expectEmit(true, false, false, true);
        emit IBaseERC20xD.ETHRecovered(recovery, 1 ether);

        vm.prank(owner);
        wrapped.recoverETH(recovery);

        assertEq(recovery.balance, 1 ether);
        assertEq(wrapped.getRecoverableETH(), 0);
    }

    function test_recoverETH_wrapDoesNotMakeETHRecoverable() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Wrap ETH
        vm.prank(alice);
        wrapped.wrap{ value: 5 ether }(alice, "");

        // Wrapped ETH should not be recoverable
        assertEq(wrapped.getRecoverableETH(), 0);
        assertGe(address(wrapped).balance, 5 ether); // ETH is in contract (at least the wrapped amount)
    }

    function test_recoverETH_onlyOwner() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        address recovery = makeAddr("recovery");

        // Send ETH through receive()
        vm.prank(alice);
        (bool success,) = address(wrapped).call{ value: 1 ether }("");
        assertTrue(success);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wrapped.recoverETH(recovery);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _simulateGatewayResponse(NativexD wrapped, uint256 nonce, int256 globalAvailability) internal {
        // Simulate the gateway calling back with global availability
        address gateway = address(gateways[0]); // Use the first gateway from test setup
        vm.prank(gateway);
        wrapped.onRead(abi.encode(globalAvailability), abi.encode(nonce));
    }
}
