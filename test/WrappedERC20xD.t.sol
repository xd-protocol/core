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
import { StakingVaultMock } from "./mocks/StakingVaultMock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import {
    MessagingReceipt, Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Test suite for WrappedERC20xD
 * @dev Important: The unwrap() function in WrappedERC20xD is a cross-chain operation:
 *      1. It calls _transfer() internally which creates a pending transfer
 *      2. The system performs lzRead to check global availability across all chains
 *      3. Only if amount <= globalAvailability does the redemption execute
 *      This ensures users can only unwrap up to the total underlying liquidity
 *      available across all chains, preventing liquidity crises.
 */
contract WrappedERC20xDTest is BaseERC20xDTestHelper {
    ERC20Mock[CHAINS] underlyings;
    StakingVaultMock vault;

    event UpdateVault(address indexed vault);
    event Wrap(address to, uint256 amount);
    event Unwrap(address to, uint256 amount);
    event RedeemFail(uint256 id, bytes reason);

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
        for (uint256 j; j < users.length; ++j) {
            underlyings[i].mint(users[j], 100e18);
        }
        return new WrappedERC20xD(
            address(underlyings[i]),
            address(vault),
            "xD",
            "xD",
            18,
            address(liquidityMatrices[i]),
            address(gateways[i]),
            owner
        );
    }

    function setUp() public override {
        vault = new StakingVaultMock();
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
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        assertEq(wrapped.underlying(), address(underlyings[0]));
        assertEq(wrapped.vault(), address(vault));
        assertEq(wrapped.name(), "xD");
        assertEq(wrapped.symbol(), "xD");
        assertEq(wrapped.decimals(), 18);
        assertEq(wrapped.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                         UPDATE VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateVault() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        address newVault = makeAddr("newVault");

        vm.expectEmit(true, false, false, false);
        emit UpdateVault(newVault);

        vm.prank(owner);
        wrapped.updateVault(newVault);

        assertEq(wrapped.vault(), newVault);
    }

    function test_updateVault_revertNonOwner() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        wrapped.updateVault(makeAddr("newVault"));
    }

    /*//////////////////////////////////////////////////////////////
                            WRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_basic() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        vm.startPrank(alice);

        uint256 underlyingBefore = underlyings[0].balanceOf(alice);

        // For WrappedERC20xD, we need to provide the proper data for the vault
        (uint256 minShares, uint256 fee) = vault.quoteDeposit(address(underlyings[0]), amount, GAS_LIMIT);
        bytes memory depositData = abi.encode(minShares, GAS_LIMIT, alice);

        vm.expectEmit();
        emit BaseWrappedERC20xD.Wrap(alice, amount);
        uint256 shares = wrapped.wrap{ value: fee }(alice, amount, fee, depositData);

        assertEq(shares, minShares);
        assertEq(wrapped.balanceOf(alice), minShares);
        assertEq(underlyings[0].balanceOf(alice), underlyingBefore - amount);
        assertEq(underlyings[0].balanceOf(address(vault)), amount);

        vm.stopPrank();
    }

    function test_wrap_differentRecipient() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        (uint256 minShares, uint256 fee) = vault.quoteDeposit(address(underlyings[0]), amount, GAS_LIMIT);
        bytes memory depositData = abi.encode(minShares, GAS_LIMIT, alice);

        vm.prank(alice);
        uint256 shares = wrapped.wrap{ value: fee }(bob, amount, fee, depositData);

        assertEq(shares, minShares);
        assertEq(wrapped.balanceOf(bob), minShares);
        assertEq(wrapped.balanceOf(alice), 0);
    }

    function test_wrap_revertZeroAddress() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        wrapped.wrap(address(0), 50e18, 0, "");
    }

    function test_wrap_revertZeroAmount() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAmount.selector);
        wrapped.wrap(alice, 0, 0, "");
    }

    function test_wrap_revertInsufficientFee() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.deal(alice, 0.05 ether);
        vm.prank(alice);

        vm.expectRevert();
        wrapped.wrap{ value: 0.05 ether }(alice, 50e18, 0.1 ether, "");
    }

    /*//////////////////////////////////////////////////////////////
                           UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_basic() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        // Step 1: Alice wraps tokens
        (uint256 minShares, uint256 wrapFee) = vault.quoteDeposit(address(underlyings[0]), amount, GAS_LIMIT);
        bytes memory depositData = abi.encode(minShares, GAS_LIMIT, alice);

        vm.prank(alice);
        uint256 shares = wrapped.wrap{ value: wrapFee }(alice, amount, wrapFee, depositData);
        assertEq(shares, minShares);
        assertEq(wrapped.balanceOf(alice), minShares);

        // Step 2: Alice initiates unwrap
        bytes memory callbackData = abi.encode(alice, alice);
        (uint256 minAmount, uint256 receivingFee) =
            vault.quoteSendToken(address(underlyings[0]), shares, callbackData, GAS_LIMIT);

        bytes memory redeemData = abi.encode(minAmount, GAS_LIMIT, alice);
        bytes memory receivingData = abi.encode(GAS_LIMIT, alice);

        uint256 redeemFee =
            wrapped.quoteRedeem(alice, alice, shares, receivingData, uint128(receivingFee), minAmount, GAS_LIMIT);

        uint256 fee = wrapped.quoteUnwrap(alice, redeemFee, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.prank(alice);
        wrapped.unwrap{ value: fee }(
            alice, shares, receivingData, uint128(receivingFee), redeemData, redeemFee, abi.encode(GAS_LIMIT, alice)
        );

        // Step 3: Execute cross-chain validation and redemption
        _executeTransfer(wrapped, alice, 1, "");

        // Final state: Alice has unwrapped successfully
        assertEq(wrapped.balanceOf(alice), 0);
        // Alice gets back minAmount from the vault
        assertEq(underlyings[0].balanceOf(alice), 100e18 - amount + minAmount);
    }

    function test_unwrap_revertZeroAddress() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        (uint256 minShares, uint256 fee) = vault.quoteDeposit(address(underlyings[0]), 50e18, GAS_LIMIT);
        bytes memory depositData = abi.encode(minShares, GAS_LIMIT, alice);

        vm.prank(alice);
        wrapped.wrap{ value: fee }(alice, 50e18, fee, depositData);

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        wrapped.unwrap(address(0), 50e18, "", 0, "", 0, "");
    }

    function test_unwrap_crossChainFlow() public {
        // This test demonstrates the detailed cross-chain flow of unwrap
        WrappedERC20xD wrapped0 = WrappedERC20xD(payable(address(erc20s[0])));
        WrappedERC20xD wrapped1 = WrappedERC20xD(payable(address(erc20s[1])));

        // Setup: Create a multi-chain wrapped token scenario
        uint256 aliceAmount = 40e18;
        uint256 bobAmount = 30e18;

        // Alice wraps on chain 0
        vm.startPrank(alice);
        (uint256 minShares0, uint256 fee0) = vault.quoteDeposit(address(underlyings[0]), aliceAmount, GAS_LIMIT);
        bytes memory depositData0 = abi.encode(minShares0, GAS_LIMIT, alice);
        wrapped0.wrap{ value: fee0 }(alice, aliceAmount, fee0, depositData0);
        vm.stopPrank();

        // Bob wraps on chain 1
        vm.startPrank(bob);
        (uint256 minShares1, uint256 fee1) = vault.quoteDeposit(address(underlyings[1]), bobAmount, GAS_LIMIT);
        bytes memory depositData1 = abi.encode(minShares1, GAS_LIMIT, bob);
        wrapped1.wrap{ value: fee1 }(bob, bobAmount, fee1, depositData1);
        vm.stopPrank();

        // Synchronize chains
        _syncAndSettleLiquidity();

        // Verify initial state
        assertEq(wrapped0.balanceOf(alice), minShares0);
        assertEq(wrapped1.balanceOf(bob), minShares1);

        // Alice initiates unwrap on chain 0
        bytes memory callbackData = abi.encode(alice, alice);
        (uint256 minAmount, uint256 receivingFee) =
            vault.quoteSendToken(address(underlyings[0]), minShares0, callbackData, GAS_LIMIT);

        bytes memory redeemData = abi.encode(minAmount, GAS_LIMIT, alice);
        bytes memory receivingData = abi.encode(GAS_LIMIT, alice);

        uint256 redeemFee =
            wrapped0.quoteRedeem(alice, alice, minShares0, receivingData, uint128(receivingFee), minAmount, GAS_LIMIT);

        uint256 fee = wrapped0.quoteUnwrap(alice, redeemFee, GAS_LIMIT);
        vm.deal(alice, fee);
        vm.startPrank(alice);
        wrapped0.unwrap{ value: fee }(
            alice, minShares0, receivingData, uint128(receivingFee), redeemData, redeemFee, abi.encode(GAS_LIMIT, alice)
        );
        vm.stopPrank();

        // Execute the transfer
        _executeTransfer(wrapped0, alice, 1, "");

        // Verify the unwrap completed
        assertEq(wrapped0.balanceOf(alice), 0);
        // The vault mock returns 99% of the amount when redeeming
        assertEq(underlyings[0].balanceOf(alice), 100e18 - aliceAmount + minAmount);
    }

    // Additional helper function for multi-chain sync
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
                        QUOTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_quoteUnwrap() public view {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 redeemFee = 0.1 ether;
        uint128 gasLimit = 200_000;

        uint256 quote = wrapped.quoteUnwrap(alice, redeemFee, gasLimit);

        // Should include base transfer quote + redeem fee
        assertTrue(quote >= redeemFee);
    }

    function test_quoteRedeem() public view {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint128 receivingFee = 0.05 ether;
        uint128 gasLimit = 200_000;
        uint256 shares = 50e18;

        bytes memory receivingData = abi.encode(gasLimit, alice);

        uint256 quote = wrapped.quoteRedeem(alice, bob, shares, receivingData, receivingFee, 0, gasLimit);

        // The quote should be greater than zero
        assertTrue(quote > 0);
    }

    /*//////////////////////////////////////////////////////////////
                      FALLBACK/RECEIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fallback() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.deal(alice, 1 ether);
        vm.prank(alice);

        uint256 balanceBefore = address(wrapped).balance;
        (bool success,) = address(wrapped).call{ value: 0.1 ether }("0x1234");
        assertTrue(success);

        assertEq(address(wrapped).balance - balanceBefore, 0.1 ether);
    }

    function test_receive() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.deal(alice, 1 ether);
        vm.prank(alice);

        uint256 balanceBefore = address(wrapped).balance;
        (bool success,) = address(wrapped).call{ value: 0.1 ether }("");
        assertTrue(success);

        assertEq(address(wrapped).balance - balanceBefore, 0.1 ether);
    }
}
