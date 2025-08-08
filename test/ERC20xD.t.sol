// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
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
import { IGatewayApp } from "src/interfaces/IGatewayApp.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract Composable {
    event Compose(address indexed token, uint256 amount);

    function compose(address token, uint256 amount) external payable {
        BaseERC20xD(token).transferFrom(msg.sender, address(this), amount);

        emit Compose(token, amount);
    }
}

contract ERC20xDTest is BaseERC20xDTestHelper {
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

        for (uint256 i; i < CHAINS; ++i) {
            ERC20xD erc20 = ERC20xD(payable(address(erc20s[i])));
            for (uint256 j; j < users.length; ++j) {
                erc20.mint(users[j], 100e18);
            }
        }

        // Stop any ongoing prank from parent setUp
        vm.stopPrank();
    }

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        return new ERC20xD("xD", "xD", 18, address(liquidityMatrices[i]), address(gateways[i]), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_mint_basic() public {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));

        uint256 initialSupply = token.totalSupply();

        vm.expectEmit(true, true, true, false);
        emit Transfer(address(0), alice, 50e18);

        vm.prank(owner);
        token.mint(alice, 50e18);

        assertEq(token.localBalanceOf(alice), int256(150e18));
        assertEq(token.localTotalSupply(), int256(initialSupply + 50e18));
    }

    function test_mint_revertNonOwner() public {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.mint(bob, 50e18);
    }

    function test_mint_multipleChains() public {
        uint256 totalMinted;
        for (uint256 i = 0; i < CHAINS; ++i) {
            ERC20xD token = ERC20xD(payable(address(erc20s[i])));
            uint256 amount = (i + 1) * 10e18;

            vm.prank(owner);
            token.mint(alice, amount);

            totalMinted += amount;
            assertEq(token.localBalanceOf(alice), int256(100e18 + amount));
        }

        _syncAndSettleLiquidity();

        // Check global balance includes all minted tokens
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 + totalMinted);
    }

    function test_mint_toZeroAddress() public {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));

        // Check initial state
        uint256 initialTotalSupply = token.totalSupply();
        int256 initialLocalTotalSupply = token.localTotalSupply();

        vm.prank(owner);
        token.mint(address(0), 50e18);

        // Minting to zero address is a no-op (transfer from address(0) to address(0))
        // Total supply should remain unchanged
        assertEq(token.totalSupply(), initialTotalSupply);
        assertEq(token.localTotalSupply(), initialLocalTotalSupply);
    }

    function test_mint_randomAmounts(bytes32 seed) public {
        uint256 total;
        for (uint256 i = 1; i < CHAINS; ++i) {
            uint256 amount = (uint256(seed) % 100) * 1e18;
            vm.prank(owner);
            ERC20xD(payable(address(erc20s[i]))).mint(alice, amount);
            total += amount;
            seed = keccak256(abi.encodePacked(seed, i));
        }
        _syncAndSettleLiquidity();

        assertEq(erc20s[0].localBalanceOf(alice), int256(100e18));
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 + total);
    }

    /*//////////////////////////////////////////////////////////////
                            BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_burn_basic() public {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));

        uint256 initialSupply = token.totalSupply();

        changePrank(alice, alice);
        uint256 fee = token.quoteBurn(alice, GAS_LIMIT);

        vm.expectEmit(true, true, true, false);
        emit InitiateTransfer(alice, address(0), 50e18, 0, 1);

        token.burn{ value: fee }(50e18, abi.encode(GAS_LIMIT, alice));

        // Burn creates a pending transfer
        assertEq(token.pendingNonce(alice), 1);

        // Execute the burn
        _executeTransfer(token, alice, "");

        assertEq(token.localBalanceOf(alice), int256(50e18));
        assertEq(token.localTotalSupply(), int256(initialSupply - 50e18));
    }

    function test_burn_fullBalance() public {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));
        assertEq(token.localBalanceOf(alice), int256(100e18));

        changePrank(alice, alice);
        uint256 fee = token.quoteBurn(alice, GAS_LIMIT);
        token.burn{ value: fee }(100e18, abi.encode(GAS_LIMIT, alice));
        _executeTransfer(token, alice, "");

        assertEq(token.localBalanceOf(alice), int256(0));
        assertEq(token.balanceOf(alice), 0);
    }

    function test_burn_revertInsufficientBalance() public {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));

        changePrank(alice, alice);
        uint256 fee = token.quoteBurn(alice, GAS_LIMIT);

        vm.expectRevert(BaseERC20xD.InsufficientBalance.selector);
        token.burn{ value: fee }(101e18, abi.encode(GAS_LIMIT, alice));
    }

    function test_burn_crossChain() public {
        _syncAndSettleLiquidity();

        ERC20xD token = ERC20xD(payable(address(erc20s[0])));
        assertEq(token.balanceOf(alice), CHAINS * 100e18);

        changePrank(alice, alice);
        uint256 burnAmount = 150e18; // More than local balance
        uint256 fee = token.quoteBurn(alice, GAS_LIMIT);
        token.burn{ value: fee }(burnAmount, abi.encode(GAS_LIMIT, alice));
        _executeTransfer(token, alice, "");

        assertEq(token.localBalanceOf(alice), -50e18); // Goes negative
        assertEq(token.balanceOf(alice), CHAINS * 100e18 - burnAmount);
    }

    function test_burn_multipleChains() public {
        _syncAndSettleLiquidity();

        // Burn from multiple chains
        changePrank(alice, alice);

        uint256 totalBurned;
        for (uint256 i = 0; i < 3; ++i) {
            ERC20xD token = ERC20xD(payable(address(erc20s[i])));
            uint256 burnAmount = (i + 1) * 20e18;

            uint256 fee = token.quoteBurn(alice, GAS_LIMIT);
            token.burn{ value: fee }(burnAmount, abi.encode(GAS_LIMIT, alice));
            _executeTransfer(token, alice, "");

            totalBurned += burnAmount;
        }

        _syncAndSettleLiquidity();
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 - totalBurned);
    }

    function test_burn_revertPendingTransfer() public {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));

        changePrank(alice, alice);
        uint256 fee = token.quoteBurn(alice, GAS_LIMIT);

        // First burn
        token.burn{ value: fee }(50e18, abi.encode(GAS_LIMIT, alice));

        // Second burn should fail
        vm.expectRevert(BaseERC20xD.TransferPending.selector);
        token.burn{ value: fee }(30e18, abi.encode(GAS_LIMIT, alice));
    }

    function test_quoteBurn() public view {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));
        uint256 fee = token.quoteBurn(alice, GAS_LIMIT);
        assertTrue(fee > 0);

        // Should be same as quoteTransfer
        assertEq(fee, token.quoteTransfer(alice, GAS_LIMIT));
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
        BaseERC20xD.PendingTransfer memory pending = token.pendingTransfer(alice);
        assertEq(pending.pending, true);
        assertEq(pending.from, alice);
        assertEq(pending.to, bob);
        assertEq(pending.amount, 50e18);

        // Execute transfer
        _executeTransfer(token, alice, "");

        // Verify transfer completed
        assertEq(token.pendingNonce(alice), 0);
        assertEq(token.localBalanceOf(alice), int256(50e18));
        assertEq(token.localBalanceOf(bob), int256(150e18));
    }

    function test_transfer_crossChain_revertInvalidAddress() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        token.transfer{ value: fee }(address(0), 50e18, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_revertZeroAmount() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAmount.selector);
        token.transfer{ value: fee }(bob, 0, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_revertOverflow() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        uint256 maxAmount = uint256(type(int256).max) + 1;
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.Overflow.selector);
        token.transfer{ value: fee }(bob, maxAmount, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_revertInsufficientBalance() public {
        BaseERC20xD token = erc20s[0];

        vm.prank(alice);
        uint256 fee = token.quoteTransfer(alice, GAS_LIMIT);
        vm.deal(alice, fee);

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InsufficientBalance.selector);
        token.transfer{ value: fee }(bob, 101e18, abi.encode(GAS_LIMIT, alice));
    }

    function test_transfer_crossChain_revertInsufficientValue() public {
        BaseERC20xD token = erc20s[0];

        _syncAndSettleLiquidity();

        uint256 nativeValue = 1e18;

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InsufficientValue.selector);
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
        vm.expectRevert(BaseERC20xD.TransferPending.selector);
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
        vm.expectRevert(abi.encodeWithSelector(BaseERC20xD.TransferNotPending.selector, 0));
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
        vm.expectRevert(BaseERC20xD.NotComposing.selector);
        token.transferFrom(alice, charlie, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                      LZ REDUCE/READ TESTS
    //////////////////////////////////////////////////////////////*/

    function test_reduce() public view {
        BaseERC20xD token = erc20s[0];

        // Create mock requests
        IGatewayApp.Request[] memory requests = new IGatewayApp.Request[](CHAINS - 1);
        for (uint256 i = 0; i < requests.length; i++) {
            requests[i] = IGatewayApp.Request({
                chainIdentifier: bytes32(uint256(i + 2)),
                timestamp: uint64(block.timestamp),
                target: address(erc20s[i + 1])
            });
        }

        // Mock responses - each chain reports 100e18 available
        bytes[] memory responses = new bytes[](CHAINS - 1);
        for (uint256 i = 0; i < responses.length; i++) {
            responses[i] = abi.encode(int256(100e18));
        }

        bytes memory callData = abi.encodeWithSelector(token.availableLocalBalanceOf.selector, alice);
        bytes memory result = token.reduce(requests, callData, responses);

        int256 availability = abi.decode(result, (int256));
        assertEq(availability, int256(uint256(CHAINS - 1) * 100e18));
    }

    function test_reduce_revertInvalidRequests() public {
        BaseERC20xD token = erc20s[0];

        IGatewayApp.Request[] memory requests = new IGatewayApp.Request[](0);
        bytes[] memory responses = new bytes[](0);
        bytes memory callData = abi.encodeWithSelector(token.availableLocalBalanceOf.selector, alice);

        vm.expectRevert(BaseERC20xD.InvalidRequests.selector);
        token.reduce(requests, callData, responses);
    }

    function test_onRead_revertForbidden() public {
        BaseERC20xD token = erc20s[0];

        bytes memory message = abi.encode(uint16(1), uint256(1), int256(100e18));

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.Forbidden.selector);
        token.onRead(message, abi.encode(uint256(1)));
    }

    /*//////////////////////////////////////////////////////////////
                      MINT AND BURN INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_integration_mintBurnCycle() public {
        ERC20xD token = ERC20xD(payable(address(erc20s[0])));

        // Mint some tokens
        vm.prank(owner);
        token.mint(alice, 200e18);

        assertEq(token.localBalanceOf(alice), int256(300e18));

        // Burn half of them
        changePrank(alice, alice);
        uint256 fee = token.quoteBurn(alice, GAS_LIMIT);
        token.burn{ value: fee }(150e18, abi.encode(GAS_LIMIT, alice));
        _executeTransfer(token, alice, "");

        assertEq(token.localBalanceOf(alice), int256(150e18));

        // Sync and verify global state
        _syncAndSettleLiquidity();
        assertEq(token.balanceOf(alice), CHAINS * 100e18 + 50e18); // Original 100 * CHAINS + 200 minted - 150 burned
    }

    function test_integration_crossChainMintBurn() public {
        _syncAndSettleLiquidity();

        // Mint on different chains
        for (uint256 i = 0; i < 3; ++i) {
            ERC20xD token = ERC20xD(payable(address(erc20s[i])));
            vm.prank(owner);
            token.mint(alice, (i + 1) * 50e18);
        }

        _syncAndSettleLiquidity();

        // Total minted: 50 + 100 + 150 = 300
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 + 300e18);

        // Burn from chain 1
        changePrank(alice, alice);
        uint256 fee = ERC20xD(payable(address(erc20s[1]))).quoteBurn(alice, GAS_LIMIT);
        ERC20xD(payable(address(erc20s[1]))).burn{ value: fee }(200e18, abi.encode(GAS_LIMIT, alice));
        _executeTransfer(erc20s[1], alice, "");

        _syncAndSettleLiquidity();
        assertEq(erc20s[0].balanceOf(alice), CHAINS * 100e18 + 100e18);
    }
}
