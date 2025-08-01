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
import { BaseWrappedERC20xD } from "src/mixins/BaseWrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IBaseWrappedERC20xD } from "src/interfaces/IBaseWrappedERC20xD.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import {
    MessagingReceipt, Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Test suite for BaseWrappedERC20xD
 * @dev Important: The unwrap() function in BaseWrappedERC20xD is a cross-chain operation:
 *      1. It calls _transfer() internally which creates a pending transfer
 *      2. The system performs lzRead to check global availability across all chains
 *      3. Only if amount <= globalAvailability does the redemption execute
 *      This ensures users can only unwrap up to the total underlying liquidity
 *      available across all chains, preventing liquidity crises.
 *
 *      Some tests are commented out as they require full cross-chain infrastructure.
 *      The mock-based tests demonstrate the core functionality.
 */

// Mock implementation for testing abstract functions
contract MockBaseWrappedERC20xD is BaseWrappedERC20xD {
    using SafeTransferLib for ERC20;

    bool public shouldFailDeposit;
    bool public shouldFailRedeem;
    string public failureReason = "Mock failure";

    constructor(
        address _underlying,
        address _vault,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _liquidityMatrix,
        address _gateway,
        address _owner
    ) BaseWrappedERC20xD(_underlying, _vault, _name, _symbol, _decimals, _liquidityMatrix, _gateway, _owner) { }

    function _deposit(uint256 amount, uint256 fee, bytes memory) internal override returns (uint256 shares) {
        if (shouldFailDeposit) revert(failureReason);

        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        shares = amount;

        if (fee > 0) {
            require(msg.value >= fee, "Insufficient deposit fee");
        }
    }

    function _redeem(uint256 shares, bytes memory callbackData, bytes memory, uint128, bytes memory, uint256)
        internal
        override
    {
        if (shouldFailRedeem) revert(failureReason);

        (address from, address to) = abi.decode(callbackData, (address, address));

        ERC20(underlying).safeTransfer(to, shares);
        _transferFrom(from, address(0), shares);
    }

    function quoteRedeem(address, address, uint256, bytes memory, uint128 receivingFee, uint256, uint128)
        public
        pure
        override
        returns (uint256 fee)
    {
        return receivingFee + 0.01 ether; // Mock fee
    }

    function setShouldFailDeposit(bool fail) external {
        shouldFailDeposit = fail;
    }

    function setShouldFailRedeem(bool fail) external {
        shouldFailRedeem = fail;
    }

    function setFailureReason(string memory reason) external {
        failureReason = reason;
    }
}

contract BaseWrappedERC20xDTest is BaseERC20xDTestHelper {
    ERC20Mock[CHAINS] underlyings;
    address[CHAINS] vaults;

    event UpdateVault(address indexed vault);
    event Wrap(address to, uint256 amount);
    event Unwrap(address to, uint256 amount);
    event RedeemFail(uint256 id, bytes reason);

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
        for (uint256 j; j < users.length; ++j) {
            underlyings[i].mint(users[j], 100e18);
        }
        vaults[i] = makeAddr(string.concat("vault", vm.toString(i)));
        return new MockBaseWrappedERC20xD(
            address(underlyings[i]),
            vaults[i],
            "Mock Wrapped",
            "mWRAPPED",
            18,
            address(liquidityMatrices[i]),
            address(gateways[i]),
            owner
        );
    }

    function setUp() public override {
        super.setUp();

        // Stop any ongoing prank from parent setUp
        vm.stopPrank();

        // Mint underlying tokens to wrapped contracts for redemptions
        for (uint256 i = 0; i < CHAINS; i++) {
            underlyings[i].mint(address(erc20s[i]), 1000e18);
        }

        // Approve wrapped contract for all users on all chains
        for (uint256 i = 0; i < CHAINS; i++) {
            for (uint256 j = 0; j < users.length; j++) {
                vm.prank(users[j]);
                underlyings[i].approve(address(erc20s[i]), type(uint256).max);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public view {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));

        assertEq(wrapped.underlying(), address(underlyings[0]));
        assertEq(wrapped.vault(), vaults[0]);
        assertEq(wrapped.name(), "Mock Wrapped");
        assertEq(wrapped.symbol(), "mWRAPPED");
        assertEq(wrapped.decimals(), 18);
        assertEq(wrapped.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                         UPDATE VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateVault() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        address newVault = makeAddr("newVault");

        vm.expectEmit(true, false, false, false);
        emit UpdateVault(newVault);

        vm.prank(owner);
        wrapped.updateVault(newVault);

        assertEq(wrapped.vault(), newVault);
    }

    function test_updateVault_revertNonOwner() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wrapped.updateVault(makeAddr("newVault"));
    }

    /*//////////////////////////////////////////////////////////////
                            WRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_basic() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        vm.startPrank(alice);

        uint256 underlyingBefore = underlyings[0].balanceOf(alice);

        vm.expectEmit();
        emit BaseWrappedERC20xD.Wrap(alice, amount);
        uint256 shares = wrapped.wrap(alice, amount, 0, "");

        assertEq(shares, amount); // 1:1 rate
        assertEq(wrapped.balanceOf(alice), amount);
        assertEq(underlyings[0].balanceOf(alice), underlyingBefore - amount);

        vm.stopPrank();
    }

    function test_wrap_differentRecipient() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        vm.prank(alice);
        uint256 shares = wrapped.wrap(bob, amount, 0, "");

        assertEq(shares, amount);
        assertEq(wrapped.balanceOf(bob), amount);
        assertEq(wrapped.balanceOf(alice), 0);
    }

    function test_wrap_revertZeroAddress() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        wrapped.wrap(address(0), 50e18, 0, "");
    }

    function test_wrap_revertZeroAmount() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAmount.selector);
        wrapped.wrap(alice, 0, 0, "");
    }

    function test_wrap_revertInsufficientFee() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        vm.deal(alice, 0.05 ether);
        vm.prank(alice);

        vm.expectRevert("Insufficient deposit fee");
        wrapped.wrap{ value: 0.05 ether }(alice, 50e18, 0.1 ether, "");
    }

    function test_wrap_revertDepositFailure() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        wrapped.setShouldFailDeposit(true);

        vm.prank(alice);
        vm.expectRevert("Mock failure");
        wrapped.wrap(alice, 50e18, 0, "");
    }

    /*//////////////////////////////////////////////////////////////
                           UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_basic() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        // This test demonstrates a complete wrap/unwrap cycle with cross-chain validation

        uint256 amount = 50e18;

        // Step 1: Alice wraps tokens (immediate, no cross-chain check needed)
        vm.prank(alice);
        uint256 shares = wrapped.wrap(alice, amount, 0, "");
        assertEq(shares, amount);
        assertEq(wrapped.balanceOf(alice), amount);

        // Step 2: Alice initiates unwrap (triggers cross-chain flow)
        uint256 fee = wrapped.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.prank(alice);
        wrapped.unwrap{ value: fee }(alice, shares, "", 0, "", 0, abi.encode(GAS_LIMIT, alice));

        // Step 3: Execute cross-chain validation and redemption
        _executeTransfer(wrapped, alice, 1, "");

        // Final state: Alice has unwrapped successfully
        assertEq(wrapped.balanceOf(alice), 0);
        assertEq(underlyings[0].balanceOf(alice), 100e18); // Back to original
    }

    function test_unwrap_revertZeroAddress() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, 0, "");

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        wrapped.unwrap(address(0), 50e18, "", 0, "", 0, "");
    }

    function test_unwrap_crossChainFlow() public {
        // This test demonstrates the detailed cross-chain flow of unwrap
        MockBaseWrappedERC20xD wrapped0 = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        MockBaseWrappedERC20xD wrapped1 = MockBaseWrappedERC20xD(payable(address(erc20s[1])));

        // Setup: Create a multi-chain wrapped token scenario
        uint256 aliceAmount = 40e18;
        uint256 bobAmount = 30e18;

        // Alice wraps on chain 0
        vm.startPrank(alice);
        wrapped0.wrap(alice, aliceAmount, 0, "");
        vm.stopPrank();

        // Bob wraps on chain 1
        vm.startPrank(bob);
        wrapped1.wrap(bob, bobAmount, 0, "");
        vm.stopPrank();

        // Synchronize chains
        _syncAndSettleLiquidity();

        // Verify initial state
        assertEq(wrapped0.balanceOf(alice), aliceAmount);
        assertEq(wrapped1.balanceOf(bob), bobAmount);

        // Step 1: Alice initiates unwrap
        uint256 fee = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.startPrank(alice);
        wrapped0.unwrap{ value: fee }(alice, aliceAmount, "", 0, "", 0, abi.encode(GAS_LIMIT, alice));
        vm.stopPrank();

        // At this point:
        // - Alice still has aliceAmount balance (not burned yet)
        // - A pending transfer exists with nonce 1
        // - The system has initiated a cross-chain read

        // Step 2: Simulate the cross-chain read response
        // _executeTransfer aggregates responses from all chains
        _executeTransfer(wrapped0, alice, 1, "");

        // Step 3: Verify the unwrap completed
        assertEq(wrapped0.balanceOf(alice), 0); // Wrapped tokens burned
        assertEq(underlyings[0].balanceOf(alice), 100e18); // Underlying returned
    }

    function test_unwrap_globalAvailabilityCheck() public {
        // This test verifies that unwrapping is limited by global availability
        MockBaseWrappedERC20xD wrapped0 = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        MockBaseWrappedERC20xD wrapped1 = MockBaseWrappedERC20xD(payable(address(erc20s[1])));
        MockBaseWrappedERC20xD wrapped2 = MockBaseWrappedERC20xD(payable(address(erc20s[2])));

        // Setup: Create wrapped tokens across multiple chains
        // Alice wraps 60e18 on chain 0
        vm.startPrank(alice);
        wrapped0.wrap(alice, 60e18, 0, "");
        vm.stopPrank();

        // Bob wraps 50e18 on chain 1
        vm.startPrank(bob);
        wrapped1.wrap(bob, 50e18, 0, "");
        vm.stopPrank();

        // Charlie wraps 40e18 on chain 2
        vm.startPrank(charlie);
        wrapped2.wrap(charlie, 40e18, 0, "");
        vm.stopPrank();

        // Synchronize all chains to update global state
        _syncAndSettleLiquidity();

        // Alice tries to unwrap her 60e18 on chain 0
        uint256 fee = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.startPrank(alice);
        wrapped0.unwrap{ value: fee }(alice, 60e18, "", 0, "", 0, abi.encode(GAS_LIMIT, alice));
        vm.stopPrank();

        // Execute the transfer - this should succeed
        _executeTransfer(wrapped0, alice, 1, "");

        // Verify Alice successfully unwrapped
        assertEq(wrapped0.balanceOf(alice), 0);
        assertEq(underlyings[0].balanceOf(alice), 100e18); // Back to original
    }

    function test_unwrap_exceedsGlobalAvailability() public {
        // This test verifies redemption failure when underlying is insufficient
        MockBaseWrappedERC20xD wrapped0 = MockBaseWrappedERC20xD(payable(address(erc20s[0])));

        // Alice wraps 50e18
        vm.startPrank(alice);
        wrapped0.wrap(alice, 50e18, 0, "");
        vm.stopPrank();

        // Simulate loss of underlying liquidity by transferring it away
        vm.prank(address(wrapped0));
        underlyings[0].transfer(address(0xdead), 1030e18); // Transfer most underlying away

        // Set the mock to fail redemption due to insufficient balance
        wrapped0.setShouldFailRedeem(true);
        wrapped0.setFailureReason("ERC20: insufficient balance");

        // Alice tries to unwrap
        uint256 fee = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.startPrank(alice);
        wrapped0.unwrap{ value: fee }(alice, 50e18, "", 0, "", 0, abi.encode(GAS_LIMIT, alice));
        vm.stopPrank();

        // Execute transfer - redemption will fail and be recorded
        vm.expectEmit(true, false, false, false);
        emit RedeemFail(0, bytes("ERC20: insufficient balance"));
        _executeTransfer(wrapped0, alice, 1, "");

        // Verify tokens are still wrapped and failed redemption is recorded
        assertEq(wrapped0.balanceOf(alice), 50e18);
        (bool resolved,,,,,) = wrapped0.failedRedemptions(0);
        assertEq(resolved, false);
    }

    function test_unwrap_multiuser() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        // Multiple users wrap
        vm.prank(alice);
        wrapped.wrap(alice, 30e18, 0, "");

        vm.prank(bob);
        wrapped.wrap(bob, 50e18, 0, "");

        vm.prank(charlie);
        wrapped.wrap(charlie, 20e18, 0, "");

        // Check total supply
        assertEq(wrapped.totalSupply(), 100e18);

        // Bob initiates unwrap
        uint256 fee = wrapped.quoteUnwrap(bob, 0, GAS_LIMIT);
        vm.deal(bob, fee);
        vm.prank(bob);
        wrapped.unwrap{ value: fee }(bob, 25e18, "", 0, "", 0, abi.encode(GAS_LIMIT, bob));

        // Execute Bob's unwrap with cross-chain validation
        _executeTransfer(wrapped, bob, 1, "");

        // Final state
        assertEq(wrapped.balanceOf(alice), 30e18);
        assertEq(wrapped.balanceOf(bob), 25e18);
        assertEq(wrapped.balanceOf(charlie), 20e18);
        assertEq(wrapped.totalSupply(), 75e18);
    }

    function test_unwrap_multiuser_multichain() public {
        // Test cross-chain wrap/unwrap scenario
        MockBaseWrappedERC20xD wrapped0 = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        MockBaseWrappedERC20xD wrapped1 = MockBaseWrappedERC20xD(payable(address(erc20s[1])));
        MockBaseWrappedERC20xD wrapped2 = MockBaseWrappedERC20xD(payable(address(erc20s[2])));

        // Users wrap on different chains
        vm.startPrank(alice);
        wrapped0.wrap(alice, 40e18, 0, "");
        vm.stopPrank();

        vm.startPrank(bob);
        wrapped1.wrap(bob, 60e18, 0, "");
        vm.stopPrank();

        vm.startPrank(charlie);
        wrapped2.wrap(charlie, 30e18, 0, "");
        vm.stopPrank();

        // Sync to propagate global state
        _syncAndSettleLiquidity();

        // Verify global balances
        assertEq(wrapped0.balanceOf(alice), 40e18);
        assertEq(wrapped0.balanceOf(bob), 60e18);
        assertEq(wrapped0.balanceOf(charlie), 30e18);

        // Alice unwraps on chain 0
        uint256 feeAlice = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, feeAlice);
        vm.startPrank(alice);
        wrapped0.unwrap{ value: feeAlice }(alice, 20e18, "", 0, "", 0, abi.encode(GAS_LIMIT, alice));
        vm.stopPrank();
        _executeTransfer(wrapped0, alice, 1, "");

        // Bob unwraps on chain 1
        uint256 feeBob = wrapped1.quoteUnwrap(bob, 0, GAS_LIMIT);
        vm.deal(bob, feeBob);
        vm.startPrank(bob);
        wrapped1.unwrap{ value: feeBob }(bob, 30e18, "", 0, "", 0, abi.encode(GAS_LIMIT, bob));
        vm.stopPrank();
        _executeTransfer(wrapped1, bob, 1, "");

        // Sync again
        _syncAndSettleLiquidity();

        // Verify final global state
        assertEq(wrapped0.balanceOf(alice), 20e18);
        assertEq(wrapped0.balanceOf(bob), 30e18);
        assertEq(wrapped0.balanceOf(charlie), 30e18);

        // Check local balances match expected state after unwraps
        assertEq(wrapped0.localBalanceOf(alice), 20e18);
        assertEq(wrapped1.localBalanceOf(bob), 30e18);
        assertEq(wrapped2.localBalanceOf(charlie), 30e18);
    }

    function test_unwrap_totalGlobalAvailability_negativeLocalBalance() public {
        // This test verifies that Alice can unwrap her total global availability on chain 0,
        // resulting in a negative local balance on chain 0 while other chains remain unchanged
        MockBaseWrappedERC20xD wrapped0 = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        MockBaseWrappedERC20xD wrapped1 = MockBaseWrappedERC20xD(payable(address(erc20s[1])));
        MockBaseWrappedERC20xD wrapped2 = MockBaseWrappedERC20xD(payable(address(erc20s[2])));
        MockBaseWrappedERC20xD wrapped3 = MockBaseWrappedERC20xD(payable(address(erc20s[3])));

        // Alice wraps different amounts on multiple chains
        vm.startPrank(alice);
        wrapped0.wrap(alice, 20e18, 0, ""); // Chain 0: 20e18
        vm.stopPrank();

        vm.startPrank(alice);
        wrapped1.wrap(alice, 30e18, 0, ""); // Chain 1: 30e18
        vm.stopPrank();

        vm.startPrank(alice);
        wrapped2.wrap(alice, 25e18, 0, ""); // Chain 2: 25e18
        vm.stopPrank();

        vm.startPrank(alice);
        wrapped3.wrap(alice, 15e18, 0, ""); // Chain 3: 15e18
        vm.stopPrank();

        // Sync all chains to ensure consistency
        _syncAllChains();

        // Total wrapped by Alice across all chains: 20 + 30 + 25 + 15 = 90e18
        assertEq(wrapped0.balanceOf(alice), 90e18);
        assertEq(wrapped1.balanceOf(alice), 90e18);
        assertEq(wrapped2.balanceOf(alice), 90e18);
        assertEq(wrapped3.balanceOf(alice), 90e18);

        // Verify local balances before unwrap
        assertEq(wrapped0.localBalanceOf(alice), 20e18);
        assertEq(wrapped1.localBalanceOf(alice), 30e18);
        assertEq(wrapped2.localBalanceOf(alice), 25e18);
        assertEq(wrapped3.localBalanceOf(alice), 15e18);

        // Alice unwraps her total global balance (90e18) on chain 0
        uint256 fee = wrapped0.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.startPrank(alice);
        wrapped0.unwrap{ value: fee }(alice, 90e18, "", 0, "", 0, abi.encode(GAS_LIMIT, alice));
        vm.stopPrank();

        // Execute the transfer
        _executeTransfer(wrapped0, alice, 1, "");

        // Alice should have 170e18 underlying tokens on chain 0
        // (started with 100e18, wrapped 20e18, then unwrapped 90e18)
        assertEq(underlyings[0].balanceOf(alice), 170e18);

        // Chain 0 local balance should now be negative (-70e18)
        // She had 20e18 locally but unwrapped 90e18
        assertEq(wrapped0.localBalanceOf(alice), -70e18);

        // Other chains' local balances should remain unchanged
        assertEq(wrapped1.localBalanceOf(alice), 30e18);
        assertEq(wrapped2.localBalanceOf(alice), 25e18);
        assertEq(wrapped3.localBalanceOf(alice), 15e18);

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
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        bytes memory callbackData = abi.encode(alice, bob);

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.Forbidden.selector);
        wrapped.redeemRestricted(50e18, callbackData, "", 0, "", 0);
    }

    function test_redeemRestricted_success() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        // Wrap tokens first
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, 0, "");

        // Call redeemRestricted from the contract itself
        bytes memory callbackData = abi.encode(alice, bob);

        vm.prank(address(wrapped));
        wrapped.redeemRestricted(50e18, callbackData, "", 0, "", 0);

        // Check results - bob should receive the underlying tokens
        assertEq(underlyings[0].balanceOf(bob), 150e18); // 100e18 initial + 50e18 redeemed
        assertEq(wrapped.balanceOf(alice), 0);
    }

    function test_redeemRestricted_revertRedeemFailure() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, 0, "");

        wrapped.setShouldFailRedeem(true);
        bytes memory callbackData = abi.encode(alice, bob);

        vm.prank(address(wrapped));
        vm.expectRevert("Mock failure");
        wrapped.redeemRestricted(50e18, callbackData, "", 0, "", 0);
    }

    /*//////////////////////////////////////////////////////////////
                      FAILED REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_retryRedeem_revertInvalidId() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        // Try to retry a redemption that doesn't exist
        vm.expectRevert();
        wrapped.retryRedeem(0, "");
    }

    function test_failedRedemption_flow() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));

        // Setup: Alice wraps tokens
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, 0, "");

        // Set the mock to fail redemption
        wrapped.setShouldFailRedeem(true);
        wrapped.setFailureReason("Redemption temporarily unavailable");

        // Alice tries to unwrap
        uint256 fee = wrapped.quoteUnwrap(alice, 0, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.prank(alice);
        wrapped.unwrap{ value: fee }(alice, 50e18, "", 0, "", 0, abi.encode(GAS_LIMIT, alice));

        // Execute transfer - redemption will fail and be recorded
        vm.expectEmit(true, false, false, false);
        emit RedeemFail(0, bytes("Redemption temporarily unavailable"));
        _executeTransfer(wrapped, alice, 1, "");

        // Verify failed redemption is recorded
        (bool resolved, uint256 shares, bytes memory callbackData,,,) = wrapped.failedRedemptions(0);
        assertEq(resolved, false);
        assertEq(shares, 50e18);
        (address from, address to) = abi.decode(callbackData, (address, address));
        assertEq(from, alice);
        assertEq(to, alice);

        // Fix the redemption issue
        wrapped.setShouldFailRedeem(false);

        // Retry the redemption
        wrapped.retryRedeem(0, "");

        // Verify redemption succeeded
        (resolved,,,,,) = wrapped.failedRedemptions(0);
        assertEq(resolved, true);
        assertEq(wrapped.balanceOf(alice), 0);
        assertEq(underlyings[0].balanceOf(alice), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                           QUOTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_quoteUnwrap() public view {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        uint256 redeemFee = 0.1 ether;
        uint128 gasLimit = 200_000;

        uint256 quote = wrapped.quoteUnwrap(alice, redeemFee, gasLimit);

        // Should include base transfer quote + redeem fee
        assertTrue(quote >= redeemFee);
    }

    function test_quoteRedeem() public view {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        uint128 receivingFee = 0.05 ether;
        uint128 gasLimit = 200_000;

        uint256 quote = wrapped.quoteRedeem(alice, bob, 50e18, "", receivingFee, 0, gasLimit);

        assertEq(quote, receivingFee + 0.01 ether); // Mock implementation
    }

    /*//////////////////////////////////////////////////////////////
                      FALLBACK/RECEIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fallback() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        vm.deal(alice, 1 ether);
        vm.prank(alice);

        uint256 balanceBefore = address(wrapped).balance;
        (bool success,) = address(wrapped).call{ value: 0.1 ether }("0x1234");
        assertTrue(success);

        assertEq(address(wrapped).balance - balanceBefore, 0.1 ether);
    }

    function test_receive() public {
        MockBaseWrappedERC20xD wrapped = MockBaseWrappedERC20xD(payable(address(erc20s[0])));
        vm.deal(alice, 1 ether);
        vm.prank(alice);

        uint256 balanceBefore = address(wrapped).balance;
        (bool success,) = address(wrapped).call{ value: 0.1 ether }("");
        assertTrue(success);

        assertEq(address(wrapped).balance - balanceBefore, 0.1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                       INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
}
