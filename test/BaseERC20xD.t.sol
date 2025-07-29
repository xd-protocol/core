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

    function test_transfer() public {
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

    function test_transfer_composable() public {
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

    function test_transfer_revertInsufficientBalance() public {
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

    function test_transfer_revertTransferPending() public {
        BaseERC20xD local = erc20s[0];

        assertEq(local.balanceOf(alice), 100e18);

        changePrank(alice, alice);
        uint256 amount = 1e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));

        vm.expectRevert(BaseERC20xD.TransferPending.selector);
        local.transfer{ value: fee }(bob, amount, abi.encode(GAS_LIMIT, bob));
    }

    function test_transfer_revertInsufficientAvailability() public {
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
