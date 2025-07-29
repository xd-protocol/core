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
import { ERC20xD } from "src/ERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";

contract Composable {
    event Compose(address indexed token, uint256 amount);

    function compose(address token, uint256 amount) external payable {
        BaseERC20xD(token).transferFrom(msg.sender, address(this), amount);

        emit Compose(token, amount);
    }
}

contract BaseERC20xDTest is BaseERC20xDTestHelper {
    Composable composable = new Composable();

    function setUp() public virtual override {
        super.setUp();

        for (uint256 i; i < CHAINS; ++i) {
            ERC20xD erc20 = ERC20xD(address(erc20s[i]));
            for (uint256 j; j < users.length; ++j) {
                erc20.mint(users[j], 100e18);
            }
        }
    }

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        return new ERC20xD("xD", "xD", 18, address(liquidityMatrices[i]), address(gateways[i]), owner);
    }

    function test_crossChainTransfer_basic() public {
        BaseERC20xD local = erc20s[0];
        assertEq(local.localTotalSupply(), 300e18);
        assertEq(local.localBalanceOf(alice), 100e18);
        assertEq(local.localBalanceOf(bob), 100e18);

        _syncAndSettleLiquidity();
        assertEq(local.totalSupply(), CHAINS * 300e18);
        assertEq(local.balanceOf(alice), CHAINS * 100e18);
        assertEq(local.balanceOf(bob), CHAINS * 100e18);

        changePrank(alice, alice);
        uint256 amount = 101e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        uint256 nonce = 1;
        BaseERC20xD.PendingTransfer memory pending = local.pendingTransfer(alice);
        assertEq(pending.pending, true);
        assertEq(pending.from, alice);
        assertEq(pending.to, bob);
        assertEq(pending.amount, amount);
        assertEq(pending.callData, "");
        assertEq(pending.value, 0);
        assertEq(local.pendingNonce(alice), nonce);
        assertEq(local.availableLocalBalanceOf(alice, 0), -1e18);

        _executeTransfer(local, alice, nonce, "");

        assertEq(local.localTotalSupply(), 300e18);
        assertEq(local.localBalanceOf(alice), -1e18);
        assertEq(local.localBalanceOf(bob), 201e18);

        assertEq(local.totalSupply(), CHAINS * 300e18);
        assertEq(local.balanceOf(alice), CHAINS * 100e18 - 101e18);
        assertEq(local.balanceOf(bob), CHAINS * 100e18 + 101e18);
    }

    function test_crossChainTransfer_composable() public {
        BaseERC20xD local = erc20s[0];

        changePrank(alice, alice);
        uint256 amount = 100e18;
        bytes memory callData = abi.encodeWithSelector(Composable.compose.selector, local, amount);
        uint256 native = 1e18;
        uint96 gasLimit = 1_000_000;
        uint256 fee = local.quoteTransfer(bob, gasLimit);
        local.transfer{ value: fee + native }(
            address(composable), amount, callData, native, abi.encode(gasLimit, address(composable))
        );

        vm.expectEmit();
        emit Composable.Compose(address(local), amount);
        _executeTransfer(local, alice, 1, "");

        assertEq(local.balanceOf(address(composable)), amount);
        assertEq(address(composable).balance, native);
    }

    function test_crossChainTransfer_revertInsufficientBalance() public {
        BaseERC20xD local = erc20s[0];

        assertEq(local.balanceOf(alice), 100e18);

        changePrank(alice, alice);
        uint256 amount = 101e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        vm.expectRevert(BaseERC20xD.InsufficientBalance.selector);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        _syncAndSettleLiquidity();
        assertEq(local.balanceOf(alice), 100e18 * CHAINS);

        changePrank(alice, alice);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));
    }

    function test_crossChainTransfer_revertTransferPending() public {
        BaseERC20xD local = erc20s[0];

        assertEq(local.balanceOf(alice), 100e18);

        changePrank(alice, alice);
        uint256 amount = 1e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        vm.expectRevert(BaseERC20xD.TransferPending.selector);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));
    }

    function test_crossChainTransfer_revertInsufficientAvailability() public {
        BaseERC20xD local = erc20s[0];
        BaseERC20xD remote = erc20s[1];

        _syncAndSettleLiquidity();
        assertEq(local.localBalanceOf(alice), 100e18);
        assertEq(local.balanceOf(alice), CHAINS * 100e18);

        changePrank(alice, alice);
        uint256 amount = CHAINS * 100e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        _executeTransfer(local, alice, 1, "");
        assertEq(local.localBalanceOf(alice), -(int256(int8(CHAINS) - 1)) * 100e18);
        assertEq(local.balanceOf(alice), 0);

        // on the remote chain, sync didn't happen yet
        assertEq(remote.localBalanceOf(alice), 100e18);
        assertEq(remote.balanceOf(alice), 100e18);

        amount = 100e18;
        fee = remote.quoteTransfer(bob, GAS_LIMIT);
        remote.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));
        assertEq(remote.availableLocalBalanceOf(alice, 0), 0);

        uint256 nonce = 1;
        int256 availability = 0;
        bytes memory error =
            abi.encodeWithSelector(BaseERC20xD.InsufficientAvailability.selector, nonce, amount, availability);
        _executeTransfer(remote, alice, nonce, error);
    }

    function test_crossChainTransfer_multipleChainsConcurrent() public {
        _syncAndSettleLiquidity();

        uint256 initialBalance = CHAINS * 100e18;
        assertEq(erc20s[0].balanceOf(alice), initialBalance);
        assertEq(erc20s[0].balanceOf(bob), initialBalance);
        assertEq(erc20s[0].balanceOf(charlie), initialBalance);

        // Alice transfers from chain 0
        changePrank(alice, alice);
        uint256 amount1 = 50e18;
        uint256 fee1 = erc20s[0].quoteTransfer(bob, GAS_LIMIT);
        erc20s[0].transfer{ value: fee1 }(bob, amount1, abi.encode(GAS_LIMIT, bob));

        // Bob transfers from chain 1
        changePrank(bob, bob);
        uint256 amount2 = 60e18;
        uint256 fee2 = erc20s[1].quoteTransfer(charlie, GAS_LIMIT);
        erc20s[1].transfer{ value: fee2 }(charlie, amount2, abi.encode(GAS_LIMIT, charlie));

        // Charlie transfers from chain 2
        changePrank(charlie, charlie);
        uint256 amount3 = 40e18;
        uint256 fee3 = erc20s[2].quoteTransfer(alice, GAS_LIMIT);
        erc20s[2].transfer{ value: fee3 }(alice, amount3, abi.encode(GAS_LIMIT, alice));

        // Execute all transfers
        _executeTransfer(erc20s[0], alice, 1, "");
        _executeTransfer(erc20s[1], bob, 1, "");
        _executeTransfer(erc20s[2], charlie, 1, "");

        // Check local balances on each chain
        assertEq(erc20s[0].localBalanceOf(alice), int256(100e18 - amount1));
        assertEq(erc20s[0].localBalanceOf(bob), int256(100e18 + amount1));
        assertEq(erc20s[0].localBalanceOf(charlie), int256(100e18));

        assertEq(erc20s[1].localBalanceOf(alice), int256(100e18));
        assertEq(erc20s[1].localBalanceOf(bob), int256(100e18 - amount2));
        assertEq(erc20s[1].localBalanceOf(charlie), int256(100e18 + amount2));

        assertEq(erc20s[2].localBalanceOf(alice), int256(100e18 + amount3));
        assertEq(erc20s[2].localBalanceOf(bob), int256(100e18));
        assertEq(erc20s[2].localBalanceOf(charlie), int256(100e18 - amount3));

        // Sync and check global balances
        _syncAndSettleLiquidity();

        // After all transfers:
        // Alice: initialBalance - amount1 + amount3
        // Bob: initialBalance + amount1 - amount2
        // Charlie: initialBalance + amount2 - amount3
        assertEq(erc20s[0].balanceOf(alice), initialBalance - amount1 + amount3);
        assertEq(erc20s[0].balanceOf(bob), CHAINS * 100e18 + amount1 - amount2);
        assertEq(erc20s[0].balanceOf(charlie), CHAINS * 100e18 + amount2 - amount3);
    }

    function test_crossChainTransfer_preventDoubleSpending() public {
        _syncAndSettleLiquidity();

        uint256 initialBalance = CHAINS * 100e18;
        assertEq(erc20s[0].balanceOf(alice), initialBalance);

        // First transfer: almost all of Alice's balance
        changePrank(alice, alice);
        uint256 amount = initialBalance - 10e18;
        uint256 fee = erc20s[0].quoteTransfer(bob, GAS_LIMIT);
        erc20s[0].transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        // Execute first transfer
        _executeTransfer(erc20s[0], alice, 1, "");

        // Sync liquidity to update all chains
        _syncAndSettleLiquidity();

        // Now try to transfer more than remaining balance from another chain
        changePrank(alice, alice);
        uint256 amount2 = 50e18;
        fee = erc20s[1].quoteTransfer(charlie, GAS_LIMIT);
        erc20s[1].transfer{ value: fee }(charlie, amount2, abi.encode(GAS_LIMIT, charlie));

        // This should fail with insufficient availability
        uint256 nonce = 1;
        int256 availability = 10e18;
        bytes memory error =
            abi.encodeWithSelector(BaseERC20xD.InsufficientAvailability.selector, nonce, amount2, availability);
        _executeTransfer(erc20s[1], alice, nonce, error);

        assertEq(erc20s[0].balanceOf(alice), 10e18);
        assertEq(erc20s[0].balanceOf(bob), CHAINS * 100e18 + amount);
        assertEq(erc20s[0].balanceOf(charlie), CHAINS * 100e18);
    }

    function test_crossChainTransfer_multipleAccountsSimultaneous() public {
        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 aliceAmount = 75e18;
        uint256 aliceFee = erc20s[0].quoteTransfer(charlie, GAS_LIMIT);
        erc20s[0].transfer{ value: aliceFee }(charlie, aliceAmount, abi.encode(GAS_LIMIT, charlie));

        changePrank(bob, bob);
        uint256 bobAmount = 80e18;
        uint256 bobFee = erc20s[1].quoteTransfer(charlie, GAS_LIMIT);
        erc20s[1].transfer{ value: bobFee }(charlie, bobAmount, abi.encode(GAS_LIMIT, charlie));

        changePrank(charlie, charlie);
        uint256 charlieAmount = 50e18;
        uint256 charlieFee = erc20s[2].quoteTransfer(alice, GAS_LIMIT);
        erc20s[2].transfer{ value: charlieFee }(alice, charlieAmount, abi.encode(GAS_LIMIT, alice));

        _executeTransfer(erc20s[0], alice, 1, "");
        _executeTransfer(erc20s[1], bob, 1, "");
        _executeTransfer(erc20s[2], charlie, 1, "");

        // Sync to update global balances
        _syncAndSettleLiquidity();

        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 - aliceAmount + charlieAmount);
        assertEq(erc20s[0].balanceOf(bob), CHAINS * 100e18 - bobAmount);
        assertEq(erc20s[0].balanceOf(charlie), CHAINS * 100e18 + aliceAmount + bobAmount - charlieAmount);
    }

    function test_crossChainTransfer_exceedsGlobalBalance() public {
        _syncAndSettleLiquidity();

        uint256 totalSupply = erc20s[0].totalSupply();
        assertEq(totalSupply, CHAINS * 300e18);

        changePrank(alice, alice);
        uint256 amount = CHAINS * 100e18 + 1e18;
        uint256 fee = erc20s[0].quoteTransfer(bob, GAS_LIMIT);
        vm.expectRevert(BaseERC20xD.InsufficientBalance.selector);
        erc20s[0].transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));
    }

    function test_crossChainTransfer_raceConditionSameAccountSameChain() public {
        _syncAndSettleLiquidity();

        // First transfer from chain 0
        changePrank(alice, alice);
        uint256 amount1 = 60e18;
        uint256 fee1 = erc20s[0].quoteTransfer(bob, GAS_LIMIT);
        erc20s[0].transfer{ value: fee1 }(bob, amount1, abi.encode(GAS_LIMIT, bob));

        // Cannot initiate another transfer from same chain while one is pending
        uint256 amount2 = 50e18;
        uint256 fee2 = erc20s[0].quoteTransfer(charlie, GAS_LIMIT);
        vm.expectRevert(BaseERC20xD.TransferPending.selector);
        erc20s[0].transfer{ value: fee2 }(charlie, amount2, abi.encode(GAS_LIMIT, charlie));

        // Execute the pending transfer
        _executeTransfer(erc20s[0], alice, 1, "");

        // Now can initiate new transfer
        erc20s[0].transfer{ value: fee2 }(charlie, amount2, abi.encode(GAS_LIMIT, charlie));
        _executeTransfer(erc20s[0], alice, 2, "");

        // Sync and verify final balances
        _syncAndSettleLiquidity();

        assertEq(erc20s[0].pendingNonce(alice), 0);
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 - amount1 - amount2);
        assertEq(erc20s[0].balanceOf(bob), CHAINS * 100e18 + amount1);
        assertEq(erc20s[0].balanceOf(charlie), CHAINS * 100e18 + amount2);
    }

    function test_crossChainTransfer_multipleChainsSameAccount() public {
        _syncAndSettleLiquidity();

        changePrank(alice, alice);

        // Initiate transfers from multiple chains simultaneously
        uint256 amount1 = 60e18;
        uint256 fee1 = erc20s[0].quoteTransfer(bob, GAS_LIMIT);
        erc20s[0].transfer{ value: fee1 }(bob, amount1, abi.encode(GAS_LIMIT, bob));

        uint256 amount2 = 50e18;
        uint256 fee2 = erc20s[1].quoteTransfer(charlie, GAS_LIMIT);
        erc20s[1].transfer{ value: fee2 }(charlie, amount2, abi.encode(GAS_LIMIT, charlie));

        uint256 amount3 = 40e18;
        uint256 fee3 = erc20s[2].quoteTransfer(bob, GAS_LIMIT);
        erc20s[2].transfer{ value: fee3 }(bob, amount3, abi.encode(GAS_LIMIT, bob));

        // All should have pending transfers
        assertEq(erc20s[0].pendingNonce(alice), 1);
        assertEq(erc20s[1].pendingNonce(alice), 1);
        assertEq(erc20s[2].pendingNonce(alice), 1);

        // Execute all transfers
        _executeTransfer(erc20s[0], alice, 1, "");
        _executeTransfer(erc20s[1], alice, 1, "");
        _executeTransfer(erc20s[2], alice, 1, "");

        // Sync and verify final balances
        _syncAndSettleLiquidity();

        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 - amount1 - amount2 - amount3);
        assertEq(erc20s[0].balanceOf(bob), CHAINS * 100e18 + amount1 + amount3);
        assertEq(erc20s[0].balanceOf(charlie), CHAINS * 100e18 + amount2);
    }

    function test_crossChainTransfer_maxAmountTransfer() public {
        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 maxAmount = uint256(type(int256).max);
        uint256 fee = erc20s[0].quoteTransfer(bob, GAS_LIMIT);
        vm.expectRevert(BaseERC20xD.Overflow.selector);
        erc20s[0].transfer{ value: fee }(bob, maxAmount + 1, abi.encode(GAS_LIMIT, bob));

        vm.expectRevert(BaseERC20xD.InsufficientBalance.selector);
        erc20s[0].transfer{ value: fee }(bob, maxAmount, abi.encode(GAS_LIMIT, bob));
    }

    function test_crossChainTransfer_withCallDataAndValue() public {
        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 amount = 100e18;
        bytes memory callData = abi.encodeWithSelector(Composable.compose.selector, address(erc20s[0]), amount);
        uint256 nativeValue = 2e18;
        uint96 gasLimit = 1_000_000;
        uint256 fee = erc20s[0].quoteTransfer(alice, gasLimit);

        erc20s[0].transfer{ value: fee + nativeValue }(
            address(composable), amount, callData, nativeValue, abi.encode(gasLimit, address(composable))
        );

        vm.expectEmit();
        emit Composable.Compose(address(erc20s[0]), amount);
        _executeTransfer(erc20s[0], alice, 1, "");

        assertEq(erc20s[0].balanceOf(address(composable)), amount);
        assertEq(address(composable).balance, nativeValue);
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 - amount);
    }

    function test_crossChainTransfer_insufficientValueForNative() public {
        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 amount = 50e18;
        bytes memory callData = abi.encodeWithSelector(Composable.compose.selector, address(erc20s[0]), amount);
        uint256 nativeValue = 2e18;
        uint256 fee = erc20s[0].quoteTransfer(alice, GAS_LIMIT);

        vm.expectRevert(BaseERC20xD.InsufficientValue.selector);
        erc20s[0].transfer{ value: fee }(
            address(composable), amount, callData, nativeValue, abi.encode(GAS_LIMIT, address(composable))
        );
    }

    function test_crossChainTransfer_localBalanceGoesNegative() public {
        _syncAndSettleLiquidity();

        assertEq(erc20s[0].localBalanceOf(alice), 100e18);
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18);

        changePrank(alice, alice);
        uint256 amount = 200e18;
        uint256 fee = erc20s[0].quoteTransfer(bob, GAS_LIMIT);
        erc20s[0].transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        _executeTransfer(erc20s[0], alice, 1, "");

        assertEq(erc20s[0].localBalanceOf(alice), -100e18);
        assertEq(erc20s[0].localBalanceOf(bob), 300e18);
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 - 200e18);
        assertEq(erc20s[0].balanceOf(bob), CHAINS * 100e18 + 200e18);
    }

    function test_cancelPendingTransfer() public {
        BaseERC20xD local = erc20s[0];

        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 amount = 101e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        uint256 nonce = 1;
        assertEq(local.pendingNonce(alice), nonce);
        assertEq(local.availableLocalBalanceOf(alice, 0), -1e18);

        local.cancelPendingTransfer();
        assertEq(local.pendingNonce(alice), 0);
        assertEq(local.availableLocalBalanceOf(alice, 0), 100e18);
    }

    function test_cancelPendingTransfer_revertTransferNotPending() public {
        BaseERC20xD local = erc20s[0];

        changePrank(alice, alice);
        vm.expectRevert(abi.encodeWithSelector(BaseERC20xD.TransferNotPending.selector, 0));
        local.cancelPendingTransfer();

        uint256 amount = 1e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        local.cancelPendingTransfer();
        assertEq(local.pendingNonce(alice), 0);
    }

    function test_localTransfer() public {
        BaseERC20xD local = erc20s[0];

        assertEq(local.localBalanceOf(alice), 100e18);
        assertEq(local.localBalanceOf(bob), 100e18);

        changePrank(alice, alice);
        uint256 amount = 50e18;
        bool success = local.transfer(bob, amount);

        assertTrue(success);
        assertEq(local.localBalanceOf(alice), 50e18);
        assertEq(local.localBalanceOf(bob), 150e18);
        assertEq(local.localTotalSupply(), 300e18);
    }

    function test_localTransfer_fullBalance() public {
        BaseERC20xD local = erc20s[0];

        changePrank(alice, alice);
        uint256 amount = 100e18;
        bool success = local.transfer(bob, amount);

        assertTrue(success);
        assertEq(local.localBalanceOf(alice), 0);
        assertEq(local.localBalanceOf(bob), 200e18);
    }

    function test_localTransfer_multipleTransfers() public {
        BaseERC20xD local = erc20s[0];

        changePrank(alice, alice);
        local.transfer(bob, 25e18);
        local.transfer(charlie, 25e18);
        local.transfer(bob, 25e18);

        assertEq(local.localBalanceOf(alice), 25e18);
        assertEq(local.localBalanceOf(bob), 150e18);
        assertEq(local.localBalanceOf(charlie), 125e18);
    }

    function test_localTransfer_revertInvalidAddress() public {
        BaseERC20xD local = erc20s[0];

        changePrank(alice, alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        local.transfer(address(0), 50e18);
    }

    function test_localTransfer_revertInvalidAmount() public {
        BaseERC20xD local = erc20s[0];

        changePrank(alice, alice);
        vm.expectRevert(BaseERC20xD.InvalidAmount.selector);
        local.transfer(bob, 0);
    }

    function test_localTransfer_revertInsufficientBalance() public {
        BaseERC20xD local = erc20s[0];

        changePrank(alice, alice);
        vm.expectRevert(BaseERC20xD.InsufficientBalance.selector);
        local.transfer(bob, 101e18);
    }

    function test_localTransfer_withPendingCrossChainTransfer() public {
        BaseERC20xD local = erc20s[0];

        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 crossChainAmount = 60e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, crossChainAmount, abi.encode(GAS_LIMIT, bob));

        assertEq(local.availableLocalBalanceOf(alice, 0), 40e18);

        uint256 localAmount = 30e18;
        bool success = local.transfer(charlie, localAmount);

        assertTrue(success);
        assertEq(local.localBalanceOf(alice), 70e18);
        assertEq(local.localBalanceOf(charlie), 130e18);
        assertEq(local.availableLocalBalanceOf(alice, 0), 10e18);
    }

    function test_localTransfer_revertInsufficientAvailableBalance() public {
        BaseERC20xD local = erc20s[0];

        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 crossChainAmount = 60e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, crossChainAmount, abi.encode(GAS_LIMIT, bob));

        assertEq(local.availableLocalBalanceOf(alice, 0), 40e18);

        uint256 localAmount = 50e18;
        vm.expectRevert(BaseERC20xD.InsufficientBalance.selector);
        local.transfer(charlie, localAmount);
    }

    function test_localTransfer_toSelf() public {
        BaseERC20xD local = erc20s[0];

        changePrank(alice, alice);
        uint256 amount = 50e18;
        bool success = local.transfer(alice, amount);

        assertTrue(success);
        assertEq(local.localBalanceOf(alice), 100e18);
        assertEq(local.localTotalSupply(), 300e18);
    }

    function test_localTransfer_afterCrossChainTransferCompletes() public {
        BaseERC20xD local = erc20s[0];

        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 crossChainAmount = 50e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, crossChainAmount, abi.encode(GAS_LIMIT, bob));

        _executeTransfer(local, alice, 1, "");

        assertEq(local.localBalanceOf(alice), 50e18);
        assertEq(local.pendingNonce(alice), 0);

        uint256 localAmount = 30e18;
        bool success = local.transfer(charlie, localAmount);

        assertTrue(success);
        assertEq(local.localBalanceOf(alice), 20e18);
        assertEq(local.localBalanceOf(charlie), 130e18);
    }
}
