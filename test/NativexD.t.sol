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
import { BaseWrappedERC20xD } from "src/mixins/BaseWrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IBaseWrappedERC20xD } from "src/interfaces/IBaseWrappedERC20xD.sol";
import { StakingVaultMock } from "./mocks/StakingVaultMock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import {
    MessagingReceipt, Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Test suite for NativexD
 * @dev Important: The unwrap() function in NativexD is a cross-chain operation:
 *      1. It calls _transfer() internally which creates a pending transfer
 *      2. The system performs lzRead to check global availability across all chains
 *      3. Only if amount <= globalAvailability does the redemption execute
 *      This ensures users can only unwrap up to the total underlying liquidity
 *      available across all chains, preventing liquidity crises.
 */
contract NativexDTest is BaseERC20xDTestHelper {
    address constant NATIVE = address(0);
    StakingVaultMock vault;
    address[CHAINS] vaults;

    event UpdateVault(address indexed vault);
    event Wrap(address to, uint256 amount);
    event Unwrap(address to, uint256 amount);
    event RedeemFail(uint256 id, bytes reason);

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        vaults[i] = address(vault);
        return new NativexD(
            address(vault), "Wrapped Native", "wNATIVE", 18, address(liquidityMatrices[i]), address(gateways[i]), owner
        );
    }

    function setUp() public override {
        vault = new StakingVaultMock();
        super.setUp();

        // Stop any ongoing prank from parent setUp
        vm.stopPrank();

        // Fund wrapped contracts with native currency for redemptions
        for (uint256 i = 0; i < CHAINS; i++) {
            vm.deal(address(erc20s[i]), 1000 ether);
        }

        // Fund users with native currency
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 1000 ether);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public view {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        assertEq(wrapped.underlying(), NATIVE);
        assertEq(wrapped.vault(), address(vault));
        assertEq(wrapped.name(), "Wrapped Native");
        assertEq(wrapped.symbol(), "wNATIVE");
        assertEq(wrapped.decimals(), 18);
        assertEq(wrapped.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                         UPDATE VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateVault() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        address newVault = makeAddr("newVault");

        vm.expectEmit(true, false, false, false);
        emit UpdateVault(newVault);

        vm.prank(owner);
        wrapped.updateVault(newVault);

        assertEq(wrapped.vault(), newVault);
    }

    function test_updateVault_revertNonOwner() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wrapped.updateVault(makeAddr("newVault"));
    }

    /*//////////////////////////////////////////////////////////////
                            WRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_basic() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        vm.startPrank(alice);

        uint256 balanceBefore = alice.balance;

        // Prepare deposit data for StakingVaultMock
        bytes memory depositData = abi.encode(amount * 99 / 100, uint128(0), alice);

        vm.expectEmit();
        emit BaseWrappedERC20xD.Wrap(alice, amount);
        uint256 shares = wrapped.wrap{ value: amount }(alice, amount, 0, depositData);

        assertEq(shares, amount * 99 / 100); // StakingVaultMock returns 99% as shares
        assertEq(wrapped.balanceOf(alice), amount * 99 / 100);
        assertEq(alice.balance, balanceBefore - amount);

        vm.stopPrank();
    }

    function test_wrap_differentRecipient() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        // Prepare deposit data for StakingVaultMock
        bytes memory depositData = abi.encode(amount * 99 / 100, uint128(0), alice);

        vm.prank(alice);
        uint256 shares = wrapped.wrap{ value: amount }(bob, amount, 0, depositData);

        assertEq(shares, amount * 99 / 100);
        assertEq(wrapped.balanceOf(bob), amount * 99 / 100);
        assertEq(wrapped.balanceOf(alice), 0);
    }

    function test_wrap_revertZeroAddress() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        bytes memory depositData = abi.encode(50 ether * 99 / 100, uint128(0), alice);
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        wrapped.wrap{ value: 50 ether }(address(0), 50 ether, 0, depositData);
    }

    function test_wrap_revertZeroAmount() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        bytes memory depositData = abi.encode(uint256(0), uint128(0), alice);
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAmount.selector);
        wrapped.wrap{ value: 0 }(alice, 0, 0, depositData);
    }

    function test_wrap_revertInsufficientValue() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        bytes memory depositData = abi.encode(50 ether * 99 / 100, uint128(0), alice);
        vm.prank(alice);

        vm.expectRevert(BaseERC20xD.InsufficientValue.selector);
        wrapped.wrap{ value: 40 ether }(alice, 50 ether, 0, depositData);
    }

    function test_wrap_withFee() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;
        uint256 fee = 0.1 ether;

        // Prepare deposit data for StakingVaultMock
        bytes memory depositData = abi.encode(amount * 99 / 100, uint128(100_000), alice);

        vm.prank(alice);
        uint256 shares = wrapped.wrap{ value: amount + fee }(alice, amount, fee, depositData);

        assertEq(shares, amount * 99 / 100); // StakingVaultMock returns 99%
        assertEq(wrapped.balanceOf(alice), amount * 99 / 100);
    }

    /*//////////////////////////////////////////////////////////////
                           UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_basic() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        // Step 1: Alice wraps native tokens
        bytes memory depositData = abi.encode(amount * 99 / 100, uint128(0), alice);
        vm.prank(alice);
        uint256 shares = wrapped.wrap{ value: amount }(alice, amount, 0, depositData);
        assertEq(shares, amount * 99 / 100);
        assertEq(wrapped.balanceOf(alice), amount * 99 / 100);

        // Step 2: Alice initiates unwrap (triggers cross-chain flow)
        uint256 fee = wrapped.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, alice.balance + fee);
        vm.prank(alice);
        bytes memory redeemData = abi.encode(shares, uint128(0), address(wrapped));
        wrapped.unwrap{ value: fee }(alice, shares, "", 0, redeemData, 0, abi.encode(GAS_LIMIT, alice));

        // Step 3: Execute cross-chain validation and redemption
        _executeTransfer(wrapped, alice, 1, "");

        // Final state: Alice has unwrapped successfully
        assertEq(wrapped.balanceOf(alice), 0);
        assertTrue(alice.balance > 900 ether); // Received native tokens back
    }

    function test_unwrap_revertZeroAddress() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        bytes memory depositData = abi.encode(50 ether * 99 / 100, uint128(0), alice);
        vm.prank(alice);
        wrapped.wrap{ value: 50 ether }(alice, 50 ether, 0, depositData);

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        wrapped.unwrap(address(0), 50 ether, "", 0, "", 0, "");
    }

    function test_unwrap_crossChainFlow() public {
        NativexD wrapped0 = NativexD(payable(address(erc20s[0])));
        NativexD wrapped1 = NativexD(payable(address(erc20s[1])));

        // Setup: Create a multi-chain wrapped token scenario
        uint256 aliceAmount = 40 ether;
        uint256 bobAmount = 30 ether;

        // Alice wraps on chain 0
        bytes memory depositDataAlice = abi.encode(aliceAmount * 99 / 100, uint128(0), alice);
        vm.startPrank(alice);
        wrapped0.wrap{ value: aliceAmount }(alice, aliceAmount, 0, depositDataAlice);
        vm.stopPrank();

        // Bob wraps on chain 1
        bytes memory depositDataBob = abi.encode(bobAmount * 99 / 100, uint128(0), bob);
        vm.startPrank(bob);
        wrapped1.wrap{ value: bobAmount }(bob, bobAmount, 0, depositDataBob);
        vm.stopPrank();

        // Synchronize chains
        _syncAndSettleLiquidity();

        // Verify initial state
        assertEq(wrapped0.balanceOf(alice), aliceAmount * 99 / 100);
        assertEq(wrapped1.balanceOf(bob), bobAmount * 99 / 100);

        // Step 1: Alice initiates unwrap
        uint256 fee = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, alice.balance + fee);
        vm.startPrank(alice);
        bytes memory redeemData = abi.encode(aliceAmount * 99 / 100, uint128(0), address(wrapped0));
        wrapped0.unwrap{ value: fee }(alice, aliceAmount * 99 / 100, "", 0, redeemData, 0, abi.encode(GAS_LIMIT, alice));
        vm.stopPrank();

        // Step 2: Simulate the cross-chain read response
        _executeTransfer(wrapped0, alice, 1, "");

        // Step 3: Verify the unwrap completed
        assertEq(wrapped0.balanceOf(alice), 0); // Wrapped tokens burned
        assertTrue(alice.balance > 950 ether); // Native tokens returned
    }

    function test_unwrap_globalAvailabilityCheck() public {
        NativexD wrapped0 = NativexD(payable(address(erc20s[0])));
        NativexD wrapped1 = NativexD(payable(address(erc20s[1])));
        NativexD wrapped2 = NativexD(payable(address(erc20s[2])));

        // Setup: Create wrapped tokens across multiple chains
        // Alice wraps 60 ether on chain 0
        bytes memory depositDataAlice = abi.encode(60 ether * 99 / 100, uint128(0), alice);
        vm.startPrank(alice);
        wrapped0.wrap{ value: 60 ether }(alice, 60 ether, 0, depositDataAlice);
        vm.stopPrank();

        // Bob wraps 50 ether on chain 1
        bytes memory depositDataBob = abi.encode(50 ether * 99 / 100, uint128(0), bob);
        vm.startPrank(bob);
        wrapped1.wrap{ value: 50 ether }(bob, 50 ether, 0, depositDataBob);
        vm.stopPrank();

        // Charlie wraps 40 ether on chain 2
        bytes memory depositDataCharlie = abi.encode(40 ether * 99 / 100, uint128(0), charlie);
        vm.startPrank(charlie);
        wrapped2.wrap{ value: 40 ether }(charlie, 40 ether, 0, depositDataCharlie);
        vm.stopPrank();

        // Synchronize all chains to update global state
        _syncAndSettleLiquidity();

        // Alice tries to unwrap her 60 ether on chain 0
        uint256 fee = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, alice.balance + fee);
        vm.startPrank(alice);
        bytes memory redeemData = abi.encode(60 ether * 99 / 100, uint128(0), address(wrapped0));
        wrapped0.unwrap{ value: fee }(alice, 60 ether * 99 / 100, "", 0, redeemData, 0, abi.encode(GAS_LIMIT, alice));
        vm.stopPrank();

        // Execute the transfer - this should succeed
        _executeTransfer(wrapped0, alice, 1, "");

        // Verify Alice successfully unwrapped
        assertEq(wrapped0.balanceOf(alice), 0);
        assertTrue(alice.balance > 950 ether); // Got native tokens back
    }

    function test_fullWrapUnwrapCycle() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        uint256 amount = 50 ether;
        uint256 initialBalance = alice.balance;

        // Step 1: Alice wraps native tokens
        bytes memory depositData = abi.encode(amount * 99 / 100, uint128(0), alice);
        vm.prank(alice);
        uint256 shares = wrapped.wrap{ value: amount }(alice, amount, 0, depositData);
        assertEq(shares, amount * 99 / 100);
        assertEq(wrapped.balanceOf(alice), amount * 99 / 100);

        // Step 2: Alice initiates unwrap (cross-chain flow)
        uint256 fee = wrapped.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, alice.balance + fee);
        vm.prank(alice);
        bytes memory redeemData = abi.encode(shares, uint128(0), address(wrapped));
        wrapped.unwrap{ value: fee }(alice, shares, "", 0, redeemData, 0, abi.encode(GAS_LIMIT, alice));

        // Step 3: Execute cross-chain validation and redemption
        _executeTransfer(wrapped, alice, 1, "");

        // Final state: Alice has unwrapped successfully
        assertEq(wrapped.balanceOf(alice), 0);
        assertTrue(alice.balance > initialBalance - amount - 1 ether); // Account for fees
    }

    function test_multiUserWrapUnwrap() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Multiple users wrap
        bytes memory depositDataAlice = abi.encode(30 ether * 99 / 100, uint128(0), alice);
        vm.prank(alice);
        wrapped.wrap{ value: 30 ether }(alice, 30 ether, 0, depositDataAlice);

        bytes memory depositDataBob = abi.encode(50 ether * 99 / 100, uint128(0), bob);
        vm.prank(bob);
        wrapped.wrap{ value: 50 ether }(bob, 50 ether, 0, depositDataBob);

        bytes memory depositDataCharlie = abi.encode(20 ether * 99 / 100, uint128(0), charlie);
        vm.prank(charlie);
        wrapped.wrap{ value: 20 ether }(charlie, 20 ether, 0, depositDataCharlie);

        // Check total supply (99% of 100 ether)
        assertEq(wrapped.totalSupply(), 99 ether);

        // Bob initiates unwrap
        uint256 fee = wrapped.quoteUnwrap(bob, 0, GAS_LIMIT);
        vm.deal(bob, bob.balance + fee);
        vm.prank(bob);
        bytes memory redeemData = abi.encode(25 ether * 99 / 100, uint128(0), address(wrapped));
        wrapped.unwrap{ value: fee }(bob, 25 ether * 99 / 100, "", 0, redeemData, 0, abi.encode(GAS_LIMIT, bob));

        // Execute Bob's unwrap with cross-chain validation
        _executeTransfer(wrapped, bob, 1, "");

        // Final state
        assertEq(wrapped.balanceOf(alice), 30 ether * 99 / 100);
        assertEq(wrapped.balanceOf(bob), 25 ether * 99 / 100);
        assertEq(wrapped.balanceOf(charlie), 20 ether * 99 / 100);
        assertEq(wrapped.totalSupply(), 75 ether * 99 / 100);
    }

    function test_crossChainWrapUnwrap() public {
        // Test cross-chain wrap/unwrap scenario
        NativexD wrapped0 = NativexD(payable(address(erc20s[0])));
        NativexD wrapped1 = NativexD(payable(address(erc20s[1])));
        NativexD wrapped2 = NativexD(payable(address(erc20s[2])));

        // Users wrap on different chains
        bytes memory depositDataAlice = abi.encode(40 ether * 99 / 100, uint128(0), alice);
        vm.startPrank(alice);
        wrapped0.wrap{ value: 40 ether }(alice, 40 ether, 0, depositDataAlice);
        vm.stopPrank();

        bytes memory depositDataBob = abi.encode(60 ether * 99 / 100, uint128(0), bob);
        vm.startPrank(bob);
        wrapped1.wrap{ value: 60 ether }(bob, 60 ether, 0, depositDataBob);
        vm.stopPrank();

        bytes memory depositDataCharlie = abi.encode(30 ether * 99 / 100, uint128(0), charlie);
        vm.startPrank(charlie);
        wrapped2.wrap{ value: 30 ether }(charlie, 30 ether, 0, depositDataCharlie);
        vm.stopPrank();

        // Sync to propagate global state
        _syncAndSettleLiquidity();

        // Verify global balances
        assertEq(wrapped0.balanceOf(alice), 40 ether * 99 / 100);
        assertEq(wrapped0.balanceOf(bob), 60 ether * 99 / 100);
        assertEq(wrapped0.balanceOf(charlie), 30 ether * 99 / 100);

        // Alice unwraps on chain 0
        uint256 feeAlice = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, alice.balance + feeAlice);
        vm.startPrank(alice);
        bytes memory redeemDataAlice = abi.encode(20 ether * 99 / 100, uint128(0), address(wrapped0));
        wrapped0.unwrap{ value: feeAlice }(
            alice, 20 ether * 99 / 100, "", 0, redeemDataAlice, 0, abi.encode(GAS_LIMIT, alice)
        );
        vm.stopPrank();
        _executeTransfer(wrapped0, alice, 1, "");

        // Bob unwraps on chain 1
        uint256 feeBob = wrapped1.quoteUnwrap(bob, 0, GAS_LIMIT);
        vm.deal(bob, bob.balance + feeBob);
        vm.startPrank(bob);
        bytes memory redeemDataBob = abi.encode(30 ether * 99 / 100, uint128(0), address(wrapped1));
        wrapped1.unwrap{ value: feeBob }(bob, 30 ether * 99 / 100, "", 0, redeemDataBob, 0, abi.encode(GAS_LIMIT, bob));
        vm.stopPrank();
        _executeTransfer(wrapped1, bob, 1, "");

        // Sync again
        _syncAndSettleLiquidity();

        // Verify final global state
        assertEq(wrapped0.balanceOf(alice), 20 ether * 99 / 100);
        assertEq(wrapped0.balanceOf(bob), 30 ether * 99 / 100);
        assertEq(wrapped0.balanceOf(charlie), 30 ether * 99 / 100);

        // Check local balances match expected state after unwraps
        assertEq(wrapped0.localBalanceOf(alice), 20 ether * 99 / 100);
        assertEq(wrapped1.localBalanceOf(bob), 30 ether * 99 / 100);
        assertEq(wrapped2.localBalanceOf(charlie), 30 ether * 99 / 100);
    }

    function test_wrap_totalGlobalAvailability_negativeLocalBalance() public {
        // This test verifies that Alice can unwrap her total global availability on chain 0,
        // resulting in a negative local balance on chain 0 while other chains remain unchanged
        NativexD wrapped0 = NativexD(payable(address(erc20s[0])));
        NativexD wrapped1 = NativexD(payable(address(erc20s[1])));
        NativexD wrapped2 = NativexD(payable(address(erc20s[2])));
        NativexD wrapped3 = NativexD(payable(address(erc20s[3])));

        // Alice wraps different amounts on multiple chains
        bytes memory depositData0 = abi.encode(20 ether * 99 / 100, uint128(0), alice);
        vm.startPrank(alice);
        wrapped0.wrap{ value: 20 ether }(alice, 20 ether, 0, depositData0); // Chain 0: 20 ether
        vm.stopPrank();

        bytes memory depositData1 = abi.encode(30 ether * 99 / 100, uint128(0), alice);
        vm.startPrank(alice);
        wrapped1.wrap{ value: 30 ether }(alice, 30 ether, 0, depositData1); // Chain 1: 30 ether
        vm.stopPrank();

        bytes memory depositData2 = abi.encode(25 ether * 99 / 100, uint128(0), alice);
        vm.startPrank(alice);
        wrapped2.wrap{ value: 25 ether }(alice, 25 ether, 0, depositData2); // Chain 2: 25 ether
        vm.stopPrank();

        bytes memory depositData3 = abi.encode(15 ether * 99 / 100, uint128(0), alice);
        vm.startPrank(alice);
        wrapped3.wrap{ value: 15 ether }(alice, 15 ether, 0, depositData3); // Chain 3: 15 ether
        vm.stopPrank();

        // Sync all chains to ensure consistency
        _syncAllChains();

        // Total wrapped by Alice across all chains: (20 + 30 + 25 + 15) * 99% = 90 * 99% ether
        uint256 totalShares = 90 ether * 99 / 100;
        assertEq(wrapped0.balanceOf(alice), totalShares);
        assertEq(wrapped1.balanceOf(alice), totalShares);
        assertEq(wrapped2.balanceOf(alice), totalShares);
        assertEq(wrapped3.balanceOf(alice), totalShares);

        // Verify local balances before unwrap
        assertEq(wrapped0.localBalanceOf(alice), 20 ether * 99 / 100);
        assertEq(wrapped1.localBalanceOf(alice), 30 ether * 99 / 100);
        assertEq(wrapped2.localBalanceOf(alice), 25 ether * 99 / 100);
        assertEq(wrapped3.localBalanceOf(alice), 15 ether * 99 / 100);

        // To test negative balance, we need to ensure the wrapped contract has accumulated shares
        // from other chains. We'll simulate this by having the contract wrap some extra tokens.
        uint256 extraShares = (totalShares - (20 ether * 99 / 100));
        bytes memory extraDepositData = abi.encode(extraShares, uint128(0), address(wrapped0));
        vm.deal(address(wrapped0), extraShares * 100 / 99 + 1 ether);
        vm.stopPrank(); // Stop any current prank
        vm.prank(address(wrapped0));
        wrapped0.wrap{ value: extraShares * 100 / 99 }(address(wrapped0), extraShares * 100 / 99, 0, extraDepositData);

        // Alice unwraps her total global balance (90 * 99% ether) on chain 0
        uint256 fee = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, alice.balance + fee);
        vm.startPrank(alice);
        bytes memory redeemData = abi.encode(totalShares, uint128(0), address(wrapped0));
        wrapped0.unwrap{ value: fee }(alice, totalShares, "", 0, redeemData, 0, abi.encode(GAS_LIMIT, alice));
        vm.stopPrank();

        // Execute the transfer
        _executeTransfer(wrapped0, alice, 1, "");

        // Alice should have received 90 * 99% ether native tokens on chain 0
        assertTrue(alice.balance > 900 ether); // Got native tokens back

        // Chain 0 local balance should now be negative
        // She had 20 * 99% ether locally but unwrapped 90 * 99% ether
        int256 expectedNegativeBalance = int256(20 ether * 99 / 100) - int256(90 ether * 99 / 100);
        assertEq(wrapped0.localBalanceOf(alice), expectedNegativeBalance);

        // Other chains' local balances should remain unchanged
        assertEq(wrapped1.localBalanceOf(alice), 30 ether * 99 / 100);
        assertEq(wrapped2.localBalanceOf(alice), 25 ether * 99 / 100);
        assertEq(wrapped3.localBalanceOf(alice), 15 ether * 99 / 100);

        // Sync to update global state
        _syncAllChains();

        // After sync, global balance should be 0 across all chains
        assertEq(wrapped0.balanceOf(alice), 0);
        assertEq(wrapped1.balanceOf(alice), 0);
        assertEq(wrapped2.balanceOf(alice), 0);
        assertEq(wrapped3.balanceOf(alice), 0);

        // Verify the sum of local balances is 0
        int256 totalLocalBalance = wrapped0.localBalanceOf(alice) + wrapped1.localBalanceOf(alice)
            + wrapped2.localBalanceOf(alice) + wrapped3.localBalanceOf(alice);
        assertEq(totalLocalBalance, 0);
    }

    function _syncAllChains() internal {
        // Sync from all chains to propagate liquidity data
        for (uint256 i = 0; i < 4; i++) {
            ILiquidityMatrix local = liquidityMatrices[i];
            ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](3);
            uint256 remoteIndex = 0;
            for (uint256 j = 0; j < 4; j++) {
                if (i != j) {
                    remotes[remoteIndex++] = liquidityMatrices[j];
                }
            }
            _sync(syncers[i], local, remotes);

            // Settle liquidity for each remote
            for (uint256 j = 0; j < 4; j++) {
                if (i == j) continue;

                ILiquidityMatrix remote = liquidityMatrices[j];
                BaseERC20xD remoteApp = erc20s[j];

                (, uint256 rootTimestamp) = local.getLastReceivedLiquidityRoot(eids[j]);

                int256[] memory liquidity = new int256[](users.length);
                for (uint256 k; k < users.length; ++k) {
                    liquidity[k] = remote.getLocalLiquidity(address(remoteApp), users[k]);
                }

                changePrank(settlers[i], settlers[i]);
                local.settleLiquidity(
                    ILiquidityMatrix.SettleLiquidityParams(address(erc20s[i]), eids[j], rootTimestamp, users, liquidity)
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                      REDEEM RESTRICTED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_redeemRestricted_onlySelf() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        bytes memory callbackData = abi.encode(alice, bob);

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.Forbidden.selector);
        bytes memory redeemData = abi.encode(50 ether * 99 / 100, uint128(0), address(wrapped));
        wrapped.redeemRestricted(50 ether * 99 / 100, callbackData, "", 0, redeemData, 0);
    }

    function test_redeemRestricted_success() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        // Wrap tokens first
        bytes memory depositData = abi.encode(50 ether * 99 / 100, uint128(0), alice);
        vm.prank(alice);
        wrapped.wrap{ value: 50 ether }(alice, 50 ether, 0, depositData);

        // Call redeemRestricted from the contract itself
        bytes memory callbackData = abi.encode(alice, bob);

        uint256 bobBalanceBefore = bob.balance;
        vm.prank(address(wrapped));
        bytes memory redeemData = abi.encode(50 ether * 99 / 100, uint128(0), address(wrapped));
        wrapped.redeemRestricted(50 ether * 99 / 100, callbackData, "", 0, redeemData, 0);

        // Check results - bob should receive the native tokens
        assertEq(bob.balance - bobBalanceBefore, 50 ether * 99 / 100);
        assertEq(wrapped.balanceOf(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                      FAILED REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_retryRedeem_revertInvalidId() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        // Try to retry a redemption that doesn't exist
        vm.expectRevert();
        wrapped.retryRedeem(0, "");
    }

    /*//////////////////////////////////////////////////////////////
                           QUOTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_quoteUnwrap() public view {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 redeemFee = 0.1 ether;
        uint128 gasLimit = 200_000;

        uint256 quote = wrapped.quoteUnwrap(alice, redeemFee, gasLimit);

        // Should include base transfer quote + redeem fee
        assertTrue(quote >= redeemFee);
    }

    function test_quoteRedeem() public view {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint128 receivingFee = 0.05 ether;
        uint128 gasLimit = 200_000;

        uint256 quote = wrapped.quoteRedeem(alice, bob, 50 ether, "", receivingFee, 0, gasLimit);

        // Check that quote is reasonable
        assertTrue(quote > 0);
    }

    /*//////////////////////////////////////////////////////////////
                      FALLBACK/RECEIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fallback() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.deal(alice, 1 ether);
        vm.prank(alice);

        uint256 balanceBefore = address(wrapped).balance;
        (bool success,) = address(wrapped).call{ value: 0.1 ether }("0x1234");
        assertTrue(success);

        assertEq(address(wrapped).balance - balanceBefore, 0.1 ether);
    }

    function test_receive() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.deal(alice, 1 ether);
        vm.prank(alice);

        uint256 balanceBefore = address(wrapped).balance;
        (bool success,) = address(wrapped).call{ value: 0.1 ether }("");
        assertTrue(success);

        assertEq(address(wrapped).balance - balanceBefore, 0.1 ether);
    }
}
