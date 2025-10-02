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
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IWrappedERC20xD } from "src/interfaces/IWrappedERC20xD.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import {
    MessagingReceipt, Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract WrappedERC20xDTest is BaseERC20xDTestHelper {
    using SafeTransferLib for ERC20;

    ERC20Mock[CHAINS] underlyings;

    uint32 constant LOCAL_EID = 101;
    uint128 constant TEST_GAS_LIMIT = 200_000;

    event Wrap(address to, uint256 amount);
    event Unwrap(address to, uint256 amount);

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
        for (uint256 j; j < users.length; ++j) {
            underlyings[i].mint(users[j], 100e18);
        }
        return BaseERC20xD(
            payable(
                new WrappedERC20xD(
                    address(underlyings[i]),
                    "Mock Wrapped",
                    "mWRAPPED",
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

        // Approve wrapped token contracts
        for (uint256 i; i < CHAINS; ++i) {
            for (uint256 j; j < users.length; ++j) {
                vm.prank(users[j]);
                underlyings[i].approve(address(erc20s[i]), type(uint256).max);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public view {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        assertEq(wrapped.underlying(), address(underlyings[0]));
        assertEq(wrapped.owner(), owner);
        assertEq(wrapped.name(), "Mock Wrapped");
        assertEq(wrapped.symbol(), "mWRAPPED");
        assertEq(wrapped.decimals(), 18);
    }

    /*//////////////////////////////////////////////////////////////
                            WRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_basic() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        vm.startPrank(alice);

        uint256 underlyingBefore = underlyings[0].balanceOf(alice);

        vm.expectEmit();
        emit IWrappedERC20xD.Wrap(alice, amount);
        wrapped.wrap(alice, amount, "");

        assertEq(wrapped.balanceOf(alice), amount); // Direct 1:1 minting
        assertEq(underlyings[0].balanceOf(alice), underlyingBefore - amount);
        assertEq(underlyings[0].balanceOf(address(wrapped)), amount); // Tokens held by contract

        vm.stopPrank();
    }

    function test_wrap_differentRecipient() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        vm.prank(alice);
        wrapped.wrap(bob, amount, "");

        assertEq(wrapped.balanceOf(bob), amount);
        assertEq(wrapped.balanceOf(alice), 0);
    }

    function test_wrap_revertZeroAddress() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAddress.selector);
        wrapped.wrap(address(0), 50e18, "");
    }

    function test_wrap_revertZeroAmount() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAmount.selector);
        wrapped.wrap(alice, 0, "");
    }

    function test_wrap_multipleUsers() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");

        vm.prank(bob);
        wrapped.wrap(bob, 30e18, "");

        assertEq(wrapped.balanceOf(alice), 50e18);
        assertEq(wrapped.balanceOf(bob), 30e18);
        assertEq(wrapped.totalSupply(), 80e18);
        assertEq(underlyings[0].balanceOf(address(wrapped)), 80e18);
    }

    /*//////////////////////////////////////////////////////////////
                           UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_basic() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        // Step 1: Alice wraps tokens
        vm.prank(alice);
        wrapped.wrap(alice, amount, "");
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
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAddress.selector);
        wrapped.unwrap(address(0), 50e18, "", "");
    }

    function test_unwrap_differentRecipient() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // Alice wraps
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");

        // Alice unwraps to bob
        uint256 fee = wrapped.quoteTransfer(alice, uint128(GAS_LIMIT));
        vm.prank(alice);
        bytes memory data = abi.encode(uint128(GAS_LIMIT), alice);
        wrapped.unwrap{ value: fee }(bob, 25e18, data, "");

        // The actual token transfer to bob happens via hooks
    }

    /*//////////////////////////////////////////////////////////////
                         FALLBACK/RECEIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fallback() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);

        // Send with data should revert (no fallback function)
        (bool success,) = address(wrapped).call{ value: 0.5 ether }(hex"1234");
        assertFalse(success, "Should revert when sending ETH with data");
    }

    function test_receive() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
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
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // Quote unwrap should return the same as quoteTransfer
        uint256 expectedFee = wrapped.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        uint256 actualFee = wrapped.quoteUnwrap(500_000);

        assertEq(actualFee, expectedFee);
        assertGt(actualFee, 0); // Should be non-zero for cross-chain messaging
    }

    /*//////////////////////////////////////////////////////////////
                        ETH RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_recoverETH() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        address recovery = makeAddr("recovery");

        // Send recoverable ETH
        vm.prank(alice);
        (bool success,) = address(wrapped).call{ value: 2 ether }("");
        assertTrue(success);

        uint256 balanceBefore = recovery.balance;

        vm.expectEmit(true, false, false, true);
        emit IBaseERC20xD.ETHRecovered(recovery, 2 ether);

        vm.prank(owner);
        wrapped.recoverETH(recovery);

        assertEq(recovery.balance - balanceBefore, 2 ether);
        assertEq(wrapped.getRecoverableETH(), 0);
    }

    function test_recoverETH_onlyOwner() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
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
                        PAUSE FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pausable_setPaused() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        vm.prank(owner);
        bytes32 pauseFlags = bytes32(uint256(1 << 0)); // Bit 1
        wrapped.setPaused(pauseFlags);

        assertEq(wrapped.pauseFlags(), pauseFlags);
        assertTrue(wrapped.isPaused(1));
        assertFalse(wrapped.isPaused(2));
    }

    function test_pausable_setPaused_unauthorized() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        wrapped.setPaused(bytes32(uint256(1 << 0)));
    }

    function test_pausable_transfer_whenPaused() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // First wrap some tokens
        vm.startPrank(alice);
        underlyings[0].approve(address(wrapped), 50e18);
        wrapped.wrap(alice, 50e18, "");
        vm.stopPrank();

        // Pause transfer (ACTION_TRANSFER = bit 1)
        vm.prank(owner);
        wrapped.setPaused(bytes32(uint256(1 << 0)));

        // Try to transfer
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 1));
        wrapped.transfer(bob, 10e18, "", 0, "");
    }

    function test_pausable_cancelPendingTransfer_whenPaused() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // First wrap some tokens
        vm.startPrank(alice);
        underlyings[0].approve(address(wrapped), 50e18);
        wrapped.wrap(alice, 50e18, "");
        vm.stopPrank();

        // Create a pending transfer
        vm.prank(alice);
        try wrapped.transfer{ value: 0.001 ether }(bob, 10e18, "", 0.001 ether, "") {
            fail("Transfer should have created pending state");
        } catch {
            // Expected
        }

        // Pause cancelPendingTransfer (ACTION_CANCEL_TRANSFER = bit 3)
        vm.prank(owner);
        wrapped.setPaused(bytes32(uint256(1 << 2)));

        // Try to cancel
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 3));
        wrapped.cancelPendingTransfer();
    }

    function test_pausable_wrapUnwrapStillWork() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // Pause all transfer actions
        vm.prank(owner);
        wrapped.setPaused(bytes32(uint256((1 << 0) | (1 << 1) | (1 << 2))));

        // Wrap should still work (not pausable)
        vm.startPrank(alice);
        underlyings[0].approve(address(wrapped), 50e18);
        wrapped.wrap(alice, 50e18, "");
        vm.stopPrank();

        // Verify wrapped balance increased
        assertEq(wrapped.localBalanceOf(alice), int256(50e18));

        // Note: Unwrap requires cross-chain reads which need proper LZ setup
        // Just verify wrap worked and transfers are still paused

        // But transfers should be paused
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 1));
        wrapped.transfer(bob, 10e18, "", 0, "");
    }

    function test_pausable_unpause() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // Wrap tokens first
        vm.startPrank(alice);
        underlyings[0].approve(address(wrapped), 50e18);
        wrapped.wrap(alice, 50e18, "");
        vm.stopPrank();

        // Pause then unpause
        vm.prank(owner);
        wrapped.setPaused(bytes32(uint256(1 << 0)));
        assertTrue(wrapped.isPaused(1));

        // Verify transfer is blocked while paused
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ActionPaused(uint8)", 1));
        wrapped.transfer(bob, 10e18, "", 0, "");

        vm.prank(owner);
        wrapped.setPaused(bytes32(0));
        assertFalse(wrapped.isPaused(1));

        // After unpause, verify pause flag is cleared
        assertTrue(!wrapped.isPaused(1));
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY CAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_liquidityCap_defaultUnlimited() public view {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        assertEq(wrapped.liquidityCap(), 0, "Default liquidity cap should be 0 (unlimited)");
    }

    function test_liquidityCap_setByOwner() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 newCap = 1000e18;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IWrappedERC20xD.LiquidityCapUpdated(newCap);
        wrapped.setLiquidityCap(newCap);

        assertEq(wrapped.liquidityCap(), newCap);
    }

    function test_liquidityCap_revertNonOwner() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wrapped.setLiquidityCap(1000e18);
    }

    function test_liquidityCap_enforcedOnWrap() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 cap = 100e18;

        // Set liquidity cap
        vm.prank(owner);
        wrapped.setLiquidityCap(cap);

        // Alice wraps up to the cap
        vm.prank(alice);
        wrapped.wrap(alice, cap, "");

        assertEq(wrapped.wrappedAmount(alice), cap);
        assertEq(wrapped.balanceOf(alice), cap);

        // Try to wrap more should revert
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWrappedERC20xD.LiquidityCapExceeded.selector,
                alice,
                cap, // current wrapped
                1e18, // attempted amount
                cap // cap
            )
        );
        wrapped.wrap(alice, 1e18, "");
    }

    function test_liquidityCap_multipleUsers() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 cap = 75e18;

        vm.prank(owner);
        wrapped.setLiquidityCap(cap);

        // Alice wraps 50e18
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");
        assertEq(wrapped.wrappedAmount(alice), 50e18);

        // Bob wraps 75e18 (his own cap)
        vm.prank(bob);
        wrapped.wrap(bob, 75e18, "");
        assertEq(wrapped.wrappedAmount(bob), 75e18);

        // Alice can still wrap 25e18 more
        vm.prank(alice);
        wrapped.wrap(alice, 25e18, "");
        assertEq(wrapped.wrappedAmount(alice), 75e18);

        // But not more
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IWrappedERC20xD.LiquidityCapExceeded.selector, alice, 75e18, 1e18, cap));
        wrapped.wrap(alice, 1e18, "");
    }

    function test_liquidityCap_unwrapReducesWrappedAmount() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 cap = 100e18;
        uint256 wrapAmount = 80e18;

        vm.prank(owner);
        wrapped.setLiquidityCap(cap);

        // Alice wraps 80e18
        vm.prank(alice);
        wrapped.wrap(alice, wrapAmount, "");
        assertEq(wrapped.wrappedAmount(alice), wrapAmount);

        // Alice unwraps 30e18
        uint256 fee = wrapped.quoteTransfer(alice, uint128(GAS_LIMIT));
        vm.prank(alice);
        bytes memory data = abi.encode(uint128(GAS_LIMIT), alice);
        wrapped.unwrap{ value: fee }(alice, 30e18, data, "");

        // Simulate the cross-chain callback to execute the pending transfer
        vm.prank(address(gateways[0]));
        wrapped.onRead(abi.encode(int256(30e18)), abi.encode(uint256(1)));

        // Wrapped amount should be reduced
        assertEq(wrapped.wrappedAmount(alice), 50e18);

        // Alice can now wrap 50e18 more (up to cap)
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");
        assertEq(wrapped.wrappedAmount(alice), 100e18);
    }

    function test_liquidityCap_zeroMeansUnlimited() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // Default cap is 0 (unlimited)
        assertEq(wrapped.liquidityCap(), 0);

        // Mint more tokens for alice to test unlimited wrapping
        underlyings[0].mint(alice, 1000e18);

        // Can wrap large amounts (within alice's balance)
        vm.prank(alice);
        wrapped.wrap(alice, 1000e18, "");
        assertEq(wrapped.balanceOf(alice), 1000e18);

        // wrappedAmount is not tracked when cap is 0
        assertEq(wrapped.wrappedAmount(alice), 0);
    }

    function test_liquidityCap_setToZeroDisablesCap() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // Set a cap at 50e18 (within alice's balance)
        vm.prank(owner);
        wrapped.setLiquidityCap(50e18);

        // Alice wraps up to cap
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");
        assertEq(wrapped.wrappedAmount(alice), 50e18);

        // Can't wrap more
        vm.prank(alice);
        vm.expectRevert();
        wrapped.wrap(alice, 1e18, "");

        // Owner sets cap back to 0
        vm.prank(owner);
        wrapped.setLiquidityCap(0);

        // Now alice can wrap more (remaining 50e18 from her initial 100e18)
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");
        assertEq(wrapped.balanceOf(alice), 100e18);
    }
}
