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
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IGatewayApp } from "src/interfaces/IGatewayApp.sol";
import { BaseERC20xDTestHelper } from "../helpers/BaseERC20xDTestHelper.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract Composable {
    event Compose(address indexed token, uint256 amount);

    function compose(address token, uint256 amount) external payable {
        BaseERC20xD(token).transferFrom(msg.sender, address(this), amount);

        emit Compose(token, amount);
    }
}

contract BaseERC20xDTest is BaseERC20xDTestHelper {
    using OptionsBuilder for bytes;

    Composable composable = new Composable();

    event UpdateLiquidityMatrix(address indexed liquidityMatrix);
    event UpdateGateway(address indexed gateway);
    event InitiateTransfer(
        address indexed from, address indexed to, uint256 amount, uint256 value, uint256 indexed nonce
    );
    event CancelPendingTransfer(uint256 indexed nonce);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function setUp() public virtual override {
        super.setUp();

        // Stop any ongoing prank from parent setUp
        vm.stopPrank();

        for (uint256 i; i < CHAINS; ++i) {
            ERC20xD erc20 = ERC20xD(payable(address(erc20s[i])));
            vm.startPrank(owner);
            for (uint256 j; j < users.length; ++j) {
                erc20.mint(users[j], 100e18);
            }
            vm.stopPrank();
        }
    }

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        return new ERC20xD("xD", "xD", 18, address(liquidityMatrices[i]), address(gateways[i]), owner, settlers[i]);
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public view {
        BaseERC20xD token = erc20s[0];

        assertEq(token.name(), "xD");
        assertEq(token.symbol(), "xD");
        assertEq(token.decimals(), 18);
        assertEq(token.liquidityMatrix(), address(liquidityMatrices[0]));
        assertEq(token.gateway(), address(gateways[0]));
        assertEq(token.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                         OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateLiquidityMatrix() public {
        BaseERC20xD token = erc20s[0];
        address newMatrix = makeAddr("newMatrix");

        vm.expectEmit(true, false, false, false);
        emit UpdateLiquidityMatrix(newMatrix);

        vm.prank(owner);
        token.updateLiquidityMatrix(newMatrix);

        assertEq(token.liquidityMatrix(), newMatrix);
    }

    function test_updateLiquidityMatrix_revertNonOwner() public {
        BaseERC20xD token = erc20s[0];

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.updateLiquidityMatrix(makeAddr("newMatrix"));
    }

    function test_updateGateway() public {
        BaseERC20xD token = erc20s[0];
        address newGateway = makeAddr("newGateway");

        vm.expectEmit(true, false, false, false);
        emit UpdateGateway(newGateway);

        vm.prank(owner);
        token.updateGateway(newGateway);

        assertEq(token.gateway(), newGateway);
    }

    function test_updateGateway_revertNonOwner() public {
        BaseERC20xD token = erc20s[0];

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.updateGateway(makeAddr("newGateway"));
    }

    function test_updateReadTarget() public {
        BaseERC20xD token = erc20s[0];
        bytes32 chainIdentifier = bytes32(uint256(999));
        bytes32 target = bytes32(uint256(uint160(makeAddr("target"))));

        vm.prank(owner);
        token.updateReadTarget(chainIdentifier, target);
        // Test passes if no revert
    }

    function test_updateReadTarget_revertNonOwner() public {
        BaseERC20xD token = erc20s[0];

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.updateReadTarget(bytes32(uint256(999)), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_totalSupply() public {
        BaseERC20xD token = erc20s[0];

        // Before sync, only local total supply
        assertEq(token.totalSupply(), 300e18);

        // After sync, global total supply
        _syncAndSettleLiquidity();
        assertEq(token.totalSupply(), CHAINS * 300e18);
    }

    function test_balanceOf() public {
        BaseERC20xD token = erc20s[0];

        // Before sync, only local balance
        assertEq(token.balanceOf(alice), 100e18);

        // After sync, global balance
        _syncAndSettleLiquidity();
        assertEq(token.balanceOf(alice), CHAINS * 100e18);
    }

    function test_localTotalSupply() public view {
        BaseERC20xD token = erc20s[0];
        assertEq(token.localTotalSupply(), 300e18);
    }

    function test_localBalanceOf() public view {
        BaseERC20xD token = erc20s[0];
        assertEq(token.localBalanceOf(alice), 100e18);
        assertEq(token.localBalanceOf(bob), 100e18);
        assertEq(token.localBalanceOf(charlie), 100e18);
    }

    function test_availableLocalBalanceOf() public {
        BaseERC20xD token = erc20s[0];

        // No pending transfer
        assertEq(token.availableLocalBalanceOf(alice), 100e18);

        // With pending transfer
        _syncAndSettleLiquidity();
        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.prank(alice);
        token.transfer{ value: fee }(bob, 60e18, abi.encode(GAS_LIMIT, alice));

        assertEq(token.availableLocalBalanceOf(alice), 40e18);
    }

    function test_pendingNonce() public {
        BaseERC20xD token = erc20s[0];

        assertEq(token.pendingNonce(alice), 0);

        _syncAndSettleLiquidity();
        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.prank(alice);
        token.transfer{ value: fee }(bob, 60e18, abi.encode(GAS_LIMIT, alice));

        assertEq(token.pendingNonce(alice), 1);
    }

    function test_pendingTransfer() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();
        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.prank(alice);
        token.transfer{ value: fee }(bob, 60e18, abi.encode(GAS_LIMIT, alice));

        IBaseERC20xD.PendingTransfer memory pending = token.pendingTransfer(alice);
        assertEq(pending.pending, true);
        assertEq(pending.from, alice);
        assertEq(pending.to, bob);
        assertEq(pending.amount, 60e18);
        assertEq(pending.value, 0);
    }

    function test_quoteTransfer() public view {
        BaseERC20xD token = erc20s[0];
        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        assertTrue(fee > 0);
    }

    function test_reduce() public view {
        BaseERC20xD token = erc20s[0];

        // Create mock requests
        IGatewayApp.Request[] memory requests = new IGatewayApp.Request[](2);
        requests[0] = IGatewayApp.Request({
            chainUID: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp),
            target: address(erc20s[1])
        });
        requests[1] = IGatewayApp.Request({
            chainUID: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp),
            target: address(erc20s[2])
        });

        // Create mock responses
        bytes[] memory responses = new bytes[](2);
        responses[0] = abi.encode(int256(100e18));
        responses[1] = abi.encode(int256(200e18));

        // Call reduce
        bytes memory callData = abi.encodeWithSelector(token.availableLocalBalanceOf.selector, alice);
        bytes memory result = token.reduce(requests, callData, responses);

        // Verify result
        int256 totalAvailability = abi.decode(result, (int256));
        assertEq(totalAvailability, 300e18);
    }

    /*//////////////////////////////////////////////////////////////
                       STANDARD TRANSFER TEST
    //////////////////////////////////////////////////////////////*/

    function test_transfer_reverts_unsupported() public {
        BaseERC20xD token = erc20s[0];

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.Unsupported.selector);
        token.transfer(bob, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                     CROSS-CHAIN TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transfer_crossChain_basic() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        vm.expectEmit(true, true, true, false);
        emit InitiateTransfer(alice, bob, 50e18, 0, 1);

        vm.prank(alice);
        token.transfer{ value: fee }(bob, 50e18, abi.encode(GAS_LIMIT, alice));

        // Verify pending transfer created
        assertEq(token.pendingNonce(alice), 1);
        IBaseERC20xD.PendingTransfer memory pending = token.pendingTransfer(alice);
        assertEq(pending.pending, true);
        assertEq(pending.from, alice);
        assertEq(pending.to, bob);
        assertEq(pending.amount, 50e18);

        // Execute transfer
        _executeTransfer(token, alice, "");

        // Verify transfer completed
        assertEq(token.pendingNonce(alice), 0);
        assertEq(token.localBalanceOf(alice), 50e18);
        assertEq(token.localBalanceOf(bob), 150e18);
    }

    function test_transfer_crossChain_revertInvalidAddress() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAddress.selector);
        token.transfer{ value: fee }(address(0), 50e18, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_revertZeroAmount() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAmount.selector);
        token.transfer{ value: fee }(bob, 0, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_revertOverflow() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        uint256 maxAmount = uint256(type(int256).max) + 1;
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.Overflow.selector);
        token.transfer{ value: fee }(bob, maxAmount, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_revertInsufficientBalance() public {
        BaseERC20xD token = erc20s[0];

        vm.prank(alice);
        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InsufficientBalance.selector);
        token.transfer{ value: fee }(bob, 101e18, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_revertInsufficientValue() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 nativeValue = 1e18;

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InsufficientValue.selector);
        token.transfer{ value: 0 }(bob, 50e18, "", nativeValue, "");
    }

    function test_transfer_crossChain_revertTransferPending() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, 2 * fee);

        // First transfer
        vm.prank(alice);
        token.transfer{ value: fee }(bob, 50e18, abi.encode(GAS_LIMIT, alice));

        // Second transfer should fail
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.TransferPending.selector);
        token.transfer{ value: fee }(bob, 30e18, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_withCallData() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        bytes memory callData = abi.encodeWithSelector(Composable.compose.selector, address(token), 50e18);
        uint256 nativeValue = 1e18;

        uint256 fee = token.quoteTransfer(alice, 1_000_000);
        vm.deal(alice, fee + nativeValue);

        vm.prank(alice);
        token.transfer{ value: fee + nativeValue }(
            address(composable), 50e18, callData, nativeValue, abi.encode(1_000_000, alice)
        );

        // Execute with compose
        vm.expectEmit();
        emit Composable.Compose(address(token), 50e18);
        _executeTransfer(token, alice, "");

        assertEq(token.balanceOf(address(composable)), 50e18);
        assertEq(address(composable).balance, nativeValue);
    }

    /*//////////////////////////////////////////////////////////////
                       CANCEL TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_cancelPendingTransfer() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        // Create pending transfer with native value
        uint256 nativeValue = 0.5e18;
        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee + nativeValue);
        vm.prank(alice);
        token.transfer{ value: fee + nativeValue }(bob, 50e18, "", nativeValue, abi.encode(GAS_LIMIT, alice));

        assertEq(token.pendingNonce(alice), 1);

        uint256 aliceBalanceBefore = alice.balance;

        vm.expectEmit(true, false, false, false);
        emit CancelPendingTransfer(1);

        vm.prank(alice);
        token.cancelPendingTransfer();

        assertEq(token.pendingNonce(alice), 0);
        assertEq(alice.balance, aliceBalanceBefore + nativeValue);
    }

    function test_cancelPendingTransfer_revertNotPending() public {
        BaseERC20xD token = erc20s[0];

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IBaseERC20xD.TransferNotPending.selector, 0));
        token.cancelPendingTransfer();
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFERFROM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transferFrom_revertNotComposing() public {
        BaseERC20xD token = erc20s[0];

        vm.prank(alice);
        token.approve(bob, 50e18);

        vm.prank(bob);
        vm.expectRevert(IBaseERC20xD.NotComposing.selector);
        token.transferFrom(alice, charlie, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                      LZ REDUCE/READ TESTS
    //////////////////////////////////////////////////////////////*/

    function test_onRead_revertForbidden() public {
        BaseERC20xD token = erc20s[0];

        bytes memory message = abi.encode(uint16(1), uint256(1), int256(100e18));

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.Forbidden.selector);
        token.onRead(message, "");
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

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
        IBaseERC20xD.PendingTransfer memory pending = local.pendingTransfer(alice);
        assertEq(pending.pending, true);
        assertEq(pending.from, alice);
        assertEq(pending.to, bob);
        assertEq(pending.amount, amount);
        assertEq(pending.callData, "");
        assertEq(pending.value, 0);
        assertEq(local.pendingNonce(alice), nonce);
        assertEq(local.availableLocalBalanceOf(alice), -1e18);

        _executeTransfer(local, alice, "");

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
        _executeTransfer(local, alice, "");

        assertEq(local.balanceOf(address(composable)), amount);
        assertEq(address(composable).balance, native);
    }

    function test_crossChainTransfer_revertInsufficientBalance() public {
        BaseERC20xD local = erc20s[0];

        assertEq(local.balanceOf(alice), 100e18);

        changePrank(alice, alice);
        uint256 amount = 101e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        vm.expectRevert(IBaseERC20xD.InsufficientBalance.selector);
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

        vm.expectRevert(IBaseERC20xD.TransferPending.selector);
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

        _executeTransfer(local, alice, "");
        assertEq(local.localBalanceOf(alice), -(int256(int8(CHAINS) - 1)) * 100e18);
        assertEq(local.balanceOf(alice), 0);

        // on the remote chain, sync didn't happen yet
        assertEq(remote.localBalanceOf(alice), 100e18);
        assertEq(remote.balanceOf(alice), 100e18);

        amount = 100e18;
        fee = remote.quoteTransfer(bob, GAS_LIMIT);
        remote.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));
        assertEq(remote.availableLocalBalanceOf(alice), 0);

        uint256 nonce = 1;
        int256 availability = 0;
        bytes memory error =
            abi.encodeWithSelector(IBaseERC20xD.InsufficientAvailability.selector, nonce, amount, availability);
        _executeTransfer(remote, alice, error);
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
        _executeTransfer(erc20s[0], alice, "");
        _executeTransfer(erc20s[1], bob, "");
        _executeTransfer(erc20s[2], charlie, "");

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
        skip(1);
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
        _executeTransfer(erc20s[0], alice, "");

        // Sync liquidity to update all chains
        skip(1);
        _syncAndSettleLiquidity();

        // Now try to transfer more than remaining balance from another chain
        changePrank(alice, alice);
        uint256 amount2 = 50e18;
        fee = erc20s[1].quoteTransfer(charlie, GAS_LIMIT);
        erc20s[1].transfer{ value: fee }(charlie, amount2, abi.encode(GAS_LIMIT, charlie));

        // This should fail with insufficient availability
        uint256 nonce = erc20s[1].pendingNonce(alice);
        int256 availability = 10e18;
        bytes memory error =
            abi.encodeWithSelector(IBaseERC20xD.InsufficientAvailability.selector, nonce, amount2, availability);
        _executeTransfer(erc20s[1], alice, error);

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

        _executeTransfer(erc20s[0], alice, "");
        _executeTransfer(erc20s[1], bob, "");
        _executeTransfer(erc20s[2], charlie, "");

        // Sync to update global balances
        skip(1);
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
        vm.expectRevert(IBaseERC20xD.InsufficientBalance.selector);
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
        vm.expectRevert(IBaseERC20xD.TransferPending.selector);
        erc20s[0].transfer{ value: fee2 }(charlie, amount2, abi.encode(GAS_LIMIT, charlie));

        // Execute the pending transfer
        _executeTransfer(erc20s[0], alice, "");

        // After first transfer, alice should have enough balance
        assertEq(erc20s[0].pendingNonce(alice), 0, "Alice should have no pending transfer");
        assertTrue(erc20s[0].balanceOf(alice) >= amount2, "Alice should have enough balance for second transfer");

        // Now can initiate new transfer
        erc20s[0].transfer{ value: fee2 }(charlie, amount2, abi.encode(GAS_LIMIT, charlie));
        _executeTransfer(erc20s[0], alice, "");

        // Sync and verify final balances
        skip(1);
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
        _executeTransfer(erc20s[0], alice, "");
        _executeTransfer(erc20s[1], alice, "");
        _executeTransfer(erc20s[2], alice, "");

        // Sync and verify final balances
        skip(1);
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
        vm.expectRevert(IBaseERC20xD.Overflow.selector);
        erc20s[0].transfer{ value: fee }(bob, maxAmount + 1, abi.encode(GAS_LIMIT, bob));

        vm.expectRevert(IBaseERC20xD.InsufficientBalance.selector);
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
        _executeTransfer(erc20s[0], alice, "");

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

        vm.expectRevert(IBaseERC20xD.InsufficientValue.selector);
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

        _executeTransfer(erc20s[0], alice, "");

        assertEq(erc20s[0].localBalanceOf(alice), -100e18);
        assertEq(erc20s[0].localBalanceOf(bob), 300e18);
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 - 200e18);
        assertEq(erc20s[0].balanceOf(bob), CHAINS * 100e18 + 200e18);
    }
}
