// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { DividendDistributorHook } from "src/hooks/DividendDistributorHook.sol";
import { ERC20xD } from "src/ERC20xD.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { BaseERC20xDTestHelper } from "../helpers/BaseERC20xDTestHelper.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";
import { BaseERC20xDHook } from "src/mixins/BaseERC20xDHook.sol";
import { AddressLib } from "src/libraries/AddressLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IGateway } from "src/interfaces/IGateway.sol";
import { ReadCodecV1, EVMCallRequestV1 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract MockContract {
// Empty contract for testing contract
}

contract DividendDistributorHookTest is BaseERC20xDTestHelper {
    using AddressLib for address;
    using MessageHashUtils for bytes32;

    DividendDistributorHook[CHAINS] hooks;
    ERC20xD[CHAINS] dividendTokens;

    string aliceName = "alice";
    string bobName = "bob";
    string charlieName = "charlie";
    string[] usernames = [aliceName, bobName, charlieName];
    MockContract contractAccount;

    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant INITIAL_DIVIDEND_SUPPLY = 10_000 ether;
    uint128 constant TRANSFER_GAS_LIMIT = 1_000_000;
    uint128 constant CLAIM_GAS_LIMIT = 2_000_000;

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        erc20s[i] = new ERC20xD("Test Token", "TEST", 18, address(liquidityMatrices[i]), address(gateways[i]), owner);
        vm.label(address(erc20s[i]), string.concat("MainToken", vm.toString(i)));
        dividendTokens[i] =
            new ERC20xD("Dividend Token xD", "DIVxD", 18, address(liquidityMatrices[i]), address(gateways[i]), owner);
        vm.label(address(dividendTokens[i]), string.concat("DividendToken", vm.toString(i)));
        hooks[i] =
            new DividendDistributorHook(address(erc20s[i]), address(dividendTokens[i]), address(gateways[i]), owner);
        vm.label(address(hooks[i]), string.concat("Hook", vm.toString(i)));
        return erc20s[i];
    }

    function setUp() public override {
        super.setUp();

        // Set up peers for dividend token
        vm.stopPrank();
        vm.startPrank(owner);
        for (uint256 i; i < CHAINS; ++i) {
            gateways[i].registerReader(address(dividendTokens[i]));
            gateways[i].registerReader(address(hooks[i]));
            for (uint256 j; j < CHAINS; ++j) {
                if (i == j) continue;
                dividendTokens[i].updateReadTarget(
                    bytes32(uint256(j + 1)), bytes32(uint256(uint160(address(dividendTokens[j]))))
                );
                hooks[i].updateReadTarget(bytes32(uint256(j + 1)), bytes32(uint256(uint160(address(hooks[j])))));
            }
        }
        vm.stopPrank();

        // Add hook to main token
        vm.startPrank(owner);
        for (uint256 i; i < CHAINS; ++i) {
            erc20s[i].addHook(address(hooks[i]));
        }
        vm.stopPrank();

        for (uint256 i; i < CHAINS; ++i) {
            for (uint256 j; j < usernames.length; ++j) {
                uint256 privateKey = uint256(keccak256(abi.encodePacked(usernames[j])));
                (uint8 v, bytes32 r, bytes32 s) =
                    vm.sign(privateKey, keccak256(abi.encode(users[j], address(hooks[i]))).toEthSignedMessageHash());
                bytes memory signature = abi.encodePacked(r, s, v);
                vm.prank(users[j]);
                hooks[i].registerForDividends(signature);
            }
        }

        // Create contract account
        contractAccount = new MockContract();

        // Setup initial balances
        _setupInitialBalances();
    }

    function _setupInitialBalances() internal {
        // Mint dividend tokens for distribution
        vm.stopPrank(); // Stop any ongoing prank
        vm.startPrank(owner);
        ERC20xD mainToken = ERC20xD(payable(address(erc20s[0])));
        // Give users some underlying tokens
        mainToken.mint(users[0], INITIAL_BALANCE); // users[0]
        mainToken.mint(users[1], INITIAL_BALANCE / 2); // users[1]
        mainToken.mint(users[2], INITIAL_BALANCE / 4); // users[2]
        mainToken.mint(address(contractAccount), INITIAL_BALANCE);

        dividendTokens[0].mint(owner, INITIAL_DIVIDEND_SUPPLY);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SHARE TRACKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_sharesTracking_onlyRegistered() public view {
        DividendDistributorHook hook = hooks[0];

        // Shares are already set up via wrapping in _setupInitialBalances()
        // Check shares - only Registered should have shares
        uint256 aliceShares = hook.balanceOf(users[0]);
        uint256 bobShares = hook.balanceOf(users[1]);
        uint256 charlieShares = hook.balanceOf(users[2]);
        uint256 contractShares = hook.balanceOf(address(contractAccount));

        assertEq(aliceShares, INITIAL_BALANCE);
        assertEq(bobShares, INITIAL_BALANCE / 2);
        assertEq(charlieShares, INITIAL_BALANCE / 4);
        assertEq(contractShares, 0); // Contract should have 0 shares

        // Verify total shares only includes Registered
        uint256 totalSupply = hook.totalSupply();
        assertEq(totalSupply, INITIAL_BALANCE + INITIAL_BALANCE / 2 + INITIAL_BALANCE / 4);
    }

    /*//////////////////////////////////////////////////////////////
                          DIVIDEND DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositDividend_viaTransfer() public {
        ERC20xD dividendToken = dividendTokens[0];
        DividendDistributorHook hook = hooks[0];

        // Shares are already set up via wrapping in _setupInitialBalances()

        uint256 dividendAmount = 1000 ether;

        // Owner transfers dividend tokens to hook using ERC20xD transfer with compose
        uint256 fee = dividendToken.quoteTransfer(owner, TRANSFER_GAS_LIMIT);

        vm.deal(owner, fee);
        vm.startPrank(owner);

        // Initiate the transfer with callData to trigger compose
        dividendToken.transfer{ value: fee }(
            address(hook),
            dividendAmount,
            abi.encodeWithSelector(hook.depositDividends.selector, dividendAmount),
            0,
            abi.encode(uint128(TRANSFER_GAS_LIMIT), owner)
        );

        vm.stopPrank();

        // Execute the transfer - this will trigger compose and emit DividendDeposited
        uint256 totalSupply = hook.totalSupply();
        uint256 expectedCumulativePerShare = (dividendAmount * 1e18) / totalSupply;

        vm.expectEmit(address(hook));
        emit DividendDistributorHook.DividendDeposited(dividendAmount, expectedCumulativePerShare);

        _executeTransferDividends(dividendToken, owner, "");

        // Verify dividend stats
        uint256 totalDistributed = hook.totalDividendsDistributed();
        uint256 cumulativePerShare = hook.cumulativeDividendsPerShare();
        assertEq(totalDistributed, dividendAmount);
        assertEq(cumulativePerShare, expectedCumulativePerShare);
    }

    function test_depositDividend_noSharesReverts() public {
        ERC20xD dividendToken = dividendTokens[0];

        // Create a new dividend distributor hook with no initial balances
        DividendDistributorHook emptyHook =
            new DividendDistributorHook(address(erc20s[0]), address(dividendToken), address(gateways[0]), owner);

        // Add the empty hook to main token
        vm.startPrank(owner);
        erc20s[0].addHook(address(emptyHook));
        vm.stopPrank();

        uint256 dividendAmount = 1000 ether;

        // Try to transfer dividends when no shares exist
        uint256 fee = dividendToken.quoteTransfer(owner, TRANSFER_GAS_LIMIT);
        vm.deal(owner, fee);
        vm.startPrank(owner);

        bytes memory data = abi.encode(uint128(TRANSFER_GAS_LIMIT), owner);
        bytes memory callData = abi.encodeWithSelector(emptyHook.depositDividends.selector, dividendAmount);

        // Transfer with compose - dividends won't be distributed (no shares)
        dividendToken.transfer{ value: fee }(address(emptyHook), dividendAmount, callData, 0, data);

        vm.stopPrank();

        // Execute the transfer - compose will call depositDividends
        _executeTransferDividends(dividendToken, owner, "");

        // Verify no dividends were distributed
        uint256 totalDistributed = emptyHook.totalDividendsDistributed();
        assertEq(totalDistributed, 0);
        assertEq(emptyHook.getDividendBalance(), dividendAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          DIVIDEND CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claimDividends_basic() public {
        ERC20xD dividendToken = dividendTokens[0];
        DividendDistributorHook hook = hooks[0];

        // Shares are already set up via wrapping in _setupInitialBalances()

        // Deposit dividends
        uint256 dividendAmount = 1500 ether;
        _depositDividends(dividendAmount);

        // Calculate expected dividends
        uint256 totalSupply = INITIAL_BALANCE + INITIAL_BALANCE / 2 + INITIAL_BALANCE / 4;
        uint256 expectedAlice = (INITIAL_BALANCE * dividendAmount) / totalSupply;
        uint256 expectedBob = (INITIAL_BALANCE / 2 * dividendAmount) / totalSupply;

        // Alice claims
        uint256 claimFee = hook.quoteRequestClaimDividends(alice, CLAIM_GAS_LIMIT);
        uint256 transferFee = hook.quoteTransferDividends(TRANSFER_GAS_LIMIT);
        vm.deal(alice, claimFee + transferFee);

        uint256 aliceBalanceBefore = dividendToken.balanceOf(alice);

        vm.startPrank(alice);
        // Don't check exact amount due to rounding
        hook.requestClaimDividends{ value: claimFee + transferFee }(
            abi.encode(TRANSFER_GAS_LIMIT, alice), transferFee, abi.encode(CLAIM_GAS_LIMIT, alice)
        );
        vm.stopPrank();

        // Execute Alice's claim transfer
        _executeReadPendingDividends(hook, alice, "");
        _executeTransferDividends(dividendToken, alice, "");

        assertApproxEqAbs(dividendToken.balanceOf(alice), aliceBalanceBefore + expectedAlice, 1000);

        // Bob claims
        vm.deal(bob, claimFee + transferFee);
        uint256 bobBalanceBefore = dividendToken.balanceOf(bob);

        vm.startPrank(bob);
        hook.requestClaimDividends{ value: claimFee + transferFee }(
            abi.encode(TRANSFER_GAS_LIMIT, bob), transferFee, abi.encode(CLAIM_GAS_LIMIT, bob)
        );
        vm.stopPrank();

        // Execute Bob's claim transfer
        _executeReadPendingDividends(hook, bob, "");
        _executeTransferDividends(dividendToken, bob, "");

        assertApproxEqAbs(dividendToken.balanceOf(bob), bobBalanceBefore + expectedBob, 1000);
    }

    function test_claimDividends_onlyRegistered() public {
        DividendDistributorHook hook = hooks[0];

        // Contract already has tokens but no shares (can't register)
        // Deposit dividends
        _depositDividends(1000 ether);

        // Contract has no shares, so no dividends
        uint256 contractDividends = hook.pendingDividends(address(contractAccount));
        assertEq(contractDividends, 0);

        // Contract tries to claim (should fail with NoDividends since it has 0 pending)
        uint256 claimFee = hook.quoteRequestClaimDividends(address(contractAccount), CLAIM_GAS_LIMIT);
        uint256 transferFee = hook.quoteTransferDividends(TRANSFER_GAS_LIMIT);
        vm.deal(address(contractAccount), claimFee + transferFee);

        vm.prank(address(contractAccount));
        vm.expectRevert(DividendDistributorHook.NoDividends.selector);
        hook.requestClaimDividends{ value: claimFee + transferFee }(
            abi.encode(TRANSFER_GAS_LIMIT, address(contractAccount)),
            transferFee,
            abi.encode(CLAIM_GAS_LIMIT, address(contractAccount))
        );
    }

    function test_claimDividends_insufficientFee() public {
        DividendDistributorHook hook = hooks[0];

        // Shares are already set up via wrapping in _setupInitialBalances()
        _depositDividends(1000 ether);

        // Try to claim with insufficient fee
        uint256 claimFee = hook.quoteRequestClaimDividends(users[0], CLAIM_GAS_LIMIT);
        uint256 transferFee = hook.quoteTransferDividends(TRANSFER_GAS_LIMIT);
        uint256 totalFee = claimFee + transferFee;

        // Give only half the required fee
        vm.deal(users[0], totalFee / 2);

        vm.prank(users[0]);
        vm.expectRevert(); // Will revert due to insufficient value for gateway call
        hook.requestClaimDividends{ value: totalFee / 2 }(
            abi.encode(TRANSFER_GAS_LIMIT, users[0]), transferFee, abi.encode(CLAIM_GAS_LIMIT, users[0])
        );
    }

    function test_claimDividends_noDividends() public {
        DividendDistributorHook hook = hooks[0];

        // Shares are already set up via wrapping in _setupInitialBalances()
        // Don't deposit any dividends

        uint256 claimFee = hook.quoteRequestClaimDividends(users[0], CLAIM_GAS_LIMIT);
        uint256 transferFee = hook.quoteTransferDividends(TRANSFER_GAS_LIMIT);
        vm.deal(users[0], claimFee + transferFee);

        vm.prank(users[0]);
        vm.expectRevert(DividendDistributorHook.NoDividends.selector);
        hook.requestClaimDividends{ value: claimFee + transferFee }(
            abi.encode(TRANSFER_GAS_LIMIT, users[0]), transferFee, abi.encode(CLAIM_GAS_LIMIT, users[0])
        );
    }

    /*//////////////////////////////////////////////////////////////
                         PENDING DIVIDENDS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pendingDividends_calculation() public {
        DividendDistributorHook hook = hooks[0];
        ERC20xD dividendToken = dividendTokens[0];

        // Shares are already set up via wrapping in _setupInitialBalances()

        // Deposit first round of dividends
        _depositDividends(1500 ether);

        // Total shares includes Alice, Bob, and Charlie (not the contract)
        uint256 totalSupply = INITIAL_BALANCE + INITIAL_BALANCE / 2 + INITIAL_BALANCE / 4;
        uint256 expectedAlice = (INITIAL_BALANCE * 1500 ether) / totalSupply;
        uint256 expectedBob = (INITIAL_BALANCE / 2 * 1500 ether) / totalSupply;
        uint256 expectedCharlie = (INITIAL_BALANCE / 4 * 1500 ether) / totalSupply;

        // Allow for small rounding differences (up to 1000 wei due to precision loss)
        assertApproxEqAbs(hook.pendingDividends(users[0]), expectedAlice, 1000);
        assertApproxEqAbs(hook.pendingDividends(users[1]), expectedBob, 1000);
        assertApproxEqAbs(hook.pendingDividends(users[2]), expectedCharlie, 1000);

        // Alice claims
        uint256 claimFee = hook.quoteRequestClaimDividends(users[0], CLAIM_GAS_LIMIT);
        uint256 transferFee = hook.quoteTransferDividends(TRANSFER_GAS_LIMIT);
        vm.deal(users[0], claimFee + transferFee);

        vm.startPrank(users[0]);
        hook.requestClaimDividends{ value: claimFee + transferFee }(
            abi.encode(TRANSFER_GAS_LIMIT, users[0]), transferFee, abi.encode(CLAIM_GAS_LIMIT, users[0])
        );
        vm.stopPrank();

        // Execute Alice's claim transfer
        _executeReadPendingDividends(hook, users[0], "");
        _executeTransferDividends(dividendToken, users[0], "");

        assertEq(hook.pendingDividends(users[0]), 0);
        assertApproxEqAbs(hook.pendingDividends(users[1]), expectedBob, 1000); // Bob's pending unchanged (with rounding tolerance)
        assertApproxEqAbs(hook.pendingDividends(users[2]), expectedCharlie, 1000); // Charlie's pending unchanged (with rounding tolerance)

        // Deposit second round
        _depositDividends(3000 ether);

        uint256 expectedAliceRound2 = (INITIAL_BALANCE * 3000 ether) / totalSupply;
        uint256 expectedBobTotal = expectedBob + (INITIAL_BALANCE / 2 * 3000 ether) / totalSupply;
        uint256 expectedCharlieTotal = expectedCharlie + (INITIAL_BALANCE / 4 * 3000 ether) / totalSupply;

        // Allow for larger rounding differences due to multiple calculations
        assertApproxEqAbs(hook.pendingDividends(users[0]), expectedAliceRound2, 10_000);
        assertApproxEqAbs(hook.pendingDividends(users[1]), expectedBobTotal, 10_000);
        assertApproxEqAbs(hook.pendingDividends(users[2]), expectedCharlieTotal, 10_000);
    }

    /*//////////////////////////////////////////////////////////////
                         SHARE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_shareUpdate_transfer() public {
        DividendDistributorHook hook = hooks[0];

        // Shares are already set up via wrapping in _setupInitialBalances()
        // Deposit dividends
        _depositDividends(1500 ether);

        // Calculate Alice's initial pending dividends
        uint256 aliceInitialPending = hook.pendingDividends(users[0]);
        assertGt(aliceInitialPending, 0);

        // Simulate Alice transferring half her tokens to Bob via cross-chain transfer
        ERC20xD mainToken = ERC20xD(payable(address(erc20s[0])));

        // Alice transfers half her tokens to Bob
        vm.startPrank(users[0]);
        uint256 transferFee = mainToken.quoteTransfer(users[0], TRANSFER_GAS_LIMIT);
        vm.deal(users[0], transferFee);
        mainToken.transfer{ value: transferFee }(
            users[1], INITIAL_BALANCE / 2, abi.encode(TRANSFER_GAS_LIMIT, users[0])
        );
        vm.stopPrank();

        // Execute the transfer using the base helper
        _executeTransfer(mainToken, users[0], "");

        // Check updated shares
        uint256 aliceShares = hook.balanceOf(users[0]);
        uint256 bobShares = hook.balanceOf(users[1]);

        assertEq(aliceShares, INITIAL_BALANCE / 2);
        assertEq(bobShares, INITIAL_BALANCE);

        // Check detailed dividend info for debugging
        uint256 aliceUnclaimed = hook.unclaimedDividends(users[0]);
        uint256 bobUnclaimed = hook.unclaimedDividends(users[1]);

        // Alice should have her initial pending dividends preserved as unclaimed
        assertEq(aliceUnclaimed, aliceInitialPending);
        assertEq(aliceShares, INITIAL_BALANCE / 2);

        // Bob should have his initial dividends plus new earnings
        uint256 bobInitialPending =
            (INITIAL_BALANCE / 2 * 1500 ether) / (INITIAL_BALANCE + INITIAL_BALANCE / 2 + INITIAL_BALANCE / 4);
        assertApproxEqAbs(bobUnclaimed, bobInitialPending, 1000);
        assertEq(bobShares, INITIAL_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emergencyWithdraw() public {
        DividendDistributorHook hook = hooks[0];
        ERC20xD dividendToken = dividendTokens[0];

        // Deposit dividends
        _depositDividends(1000 ether);

        uint256 withdrawAmount = 500 ether;
        uint256 fee = dividendToken.quoteTransfer(address(hook), TRANSFER_GAS_LIMIT);

        vm.deal(owner, fee);
        vm.startPrank(owner);

        vm.expectEmit(address(hook));
        emit DividendDistributorHook.EmergencyWithdraw(users[0], withdrawAmount);

        hook.emergencyWithdraw{ value: fee }(users[0], withdrawAmount, abi.encode(TRANSFER_GAS_LIMIT, users[0]));

        vm.stopPrank();

        // Execute the emergency withdraw transfer
        _executeTransferDividends(dividendToken, address(hook), "");

        assertEq(dividendToken.balanceOf(users[0]), withdrawAmount);
    }

    function test_emergencyWithdraw_onlyOwner() public {
        DividendDistributorHook hook = hooks[0];
        ERC20xD dividendToken = dividendTokens[0];

        uint256 fee = dividendToken.quoteTransfer(address(hook), TRANSFER_GAS_LIMIT);
        vm.deal(users[0], fee);

        vm.prank(users[0]);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users[0]));
        hook.emergencyWithdraw{ value: fee }(users[0], 100 ether, abi.encode(TRANSFER_GAS_LIMIT, users[0]));
    }

    // Cross-chain query tests removed - functionality no longer exists in new architecture
    // The DividendDistributorHook now uses the standard reduce pattern for aggregating
    // dividends across chains during claim operations, rather than separate query functions

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _depositDividends(uint256 amount) internal {
        ERC20xD dividendToken = dividendTokens[0];
        DividendDistributorHook hook = hooks[0];

        uint256 fee = dividendToken.quoteTransfer(owner, TRANSFER_GAS_LIMIT);
        vm.deal(owner, fee);

        vm.startPrank(owner);
        bytes memory data = abi.encode(uint128(TRANSFER_GAS_LIMIT), owner);
        // Encode the depositDividends function call
        bytes memory callData = abi.encodeWithSelector(hook.depositDividends.selector, amount);
        dividendToken.transfer{ value: fee }(address(hook), amount, callData, 0, data);
        vm.stopPrank();

        // Execute the transfer - this will trigger compose and call depositDividends
        _executeTransferDividends(dividendToken, owner, "");
    }

    function _executeReadPendingDividends(DividendDistributorHook hook, address user, bytes memory error) internal {
        address[] memory readers = new address[](CHAINS);
        for (uint256 i = 0; i < CHAINS; ++i) {
            readers[i] = address(hooks[i]);
        }
        _executeRead(
            address(hook),
            readers,
            abi.encodeWithSelector(DividendDistributorHook.pendingDividends.selector, user),
            error
        );
    }

    function _executeTransferDividends(ERC20xD dividendToken, address user, bytes memory error) internal {
        address[] memory readers = new address[](CHAINS);
        for (uint256 i = 0; i < CHAINS; ++i) {
            readers[i] = address(dividendTokens[i]);
        }
        _executeRead(
            address(dividendToken),
            readers,
            abi.encodeWithSelector(BaseERC20xD.availableLocalBalanceOf.selector, user),
            error
        );
    }
}
