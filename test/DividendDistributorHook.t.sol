// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { DividendDistributorHook } from "src/hooks/DividendDistributorHook.sol";
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IERC20xDHook } from "src/interfaces/IERC20xDHook.sol";
import { BaseERC20xDHook } from "src/mixins/BaseERC20xDHook.sol";
import { AddressLib } from "src/libraries/AddressLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20xDGateway } from "src/interfaces/IERC20xDGateway.sol";
import { ReadCodecV1, EVMCallRequestV1 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import {
    MessagingReceipt,
    MessagingFee
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract MockContract {
// Empty contract for testing contract vs EOA distinction
}

contract DividendDistributorHookTest is BaseERC20xDTestHelper {
    using AddressLib for address;

    DividendDistributorHook hook;
    WrappedERC20xD dividendToken;
    ERC20Mock underlyingDividendToken;

    // Using inherited addresses from BaseERC20xDTestHelper
    // users[0] = users[0], users[1] = users[1], users[2] = users[2]
    MockContract contractAccount;

    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant INITIAL_DIVIDEND_SUPPLY = 10_000 ether;
    uint128 constant EXTENDED_GAS_LIMIT = 2_000_000;

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        return BaseERC20xD(
            address(
                new WrappedERC20xD(
                    address(new ERC20Mock("Mock", "MOCK", 18)),
                    "Test Token",
                    "TEST",
                    18,
                    address(liquidityMatrices[i]),
                    address(gateways[i]),
                    owner
                )
            )
        );
    }

    function setUp() public override {
        super.setUp();

        // Create dividend token
        underlyingDividendToken = new ERC20Mock("Dividend Token", "DIV", 18);
        dividendToken = new WrappedERC20xD(
            address(underlyingDividendToken),
            "Dividend Token xD",
            "DIVxD",
            18,
            address(liquidityMatrices[0]),
            address(gateways[0]),
            owner
        );

        // Set up peers for dividend token
        vm.stopPrank();
        for (uint256 i = 1; i < CHAINS; ++i) {
            vm.startPrank(owner);
            dividendToken.setPeer(uint32(i + 1), bytes32(uint256(uint160(address(dividendToken)))));
            vm.stopPrank();
        }

        // Create hook attached to main token
        hook = new DividendDistributorHook(address(erc20s[0]), address(dividendToken), address(gateways[0]), owner);

        // Add hook to main token
        vm.startPrank(owner);
        WrappedERC20xD(payable(address(erc20s[0]))).addHook(address(hook));
        vm.stopPrank();

        // Create contract account
        contractAccount = new MockContract();

        // Setup initial balances
        _setupInitialBalances();
    }

    function _setupInitialBalances() internal {
        WrappedERC20xD mainToken = WrappedERC20xD(payable(address(erc20s[0])));

        // Give users some underlying tokens
        ERC20Mock underlying = ERC20Mock(mainToken.underlying());
        underlying.mint(users[0], INITIAL_BALANCE); // users[0]
        underlying.mint(users[1], INITIAL_BALANCE); // users[1]
        underlying.mint(users[2], INITIAL_BALANCE); // users[2]
        underlying.mint(address(contractAccount), INITIAL_BALANCE);

        // Have users wrap their tokens
        vm.startPrank(users[0]);
        underlying.approve(address(mainToken), INITIAL_BALANCE);
        mainToken.wrap(users[0], INITIAL_BALANCE);
        vm.stopPrank();

        vm.startPrank(users[1]);
        underlying.approve(address(mainToken), INITIAL_BALANCE);
        mainToken.wrap(users[1], INITIAL_BALANCE / 2); // Bob wraps half
        vm.stopPrank();

        vm.startPrank(users[2]);
        underlying.approve(address(mainToken), INITIAL_BALANCE);
        mainToken.wrap(users[2], INITIAL_BALANCE / 4); // Charlie wraps quarter
        vm.stopPrank();

        // Contract wraps tokens too
        vm.startPrank(address(contractAccount));
        underlying.approve(address(mainToken), INITIAL_BALANCE);
        mainToken.wrap(address(contractAccount), INITIAL_BALANCE);
        vm.stopPrank();

        // Mint dividend tokens for distribution
        vm.stopPrank(); // Stop any ongoing prank
        underlyingDividendToken.mint(owner, INITIAL_DIVIDEND_SUPPLY);
        vm.startPrank(owner);
        underlyingDividendToken.approve(address(dividendToken), INITIAL_DIVIDEND_SUPPLY);
        dividendToken.wrap(owner, INITIAL_DIVIDEND_SUPPLY);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SHARE TRACKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_sharesTracking_onlyEOAs() public view {
        // Shares are already set up via wrapping in _setupInitialBalances()
        // Check shares - only EOAs should have shares
        uint256 aliceShares = hook.userBalances(users[0]);
        uint256 bobShares = hook.userBalances(users[1]);
        uint256 charlieShares = hook.userBalances(users[2]);
        uint256 contractShares = hook.userBalances(address(contractAccount));

        assertEq(aliceShares, INITIAL_BALANCE);
        assertEq(bobShares, INITIAL_BALANCE / 2);
        assertEq(charlieShares, INITIAL_BALANCE / 4);
        assertEq(contractShares, 0); // Contract should have 0 shares

        // Verify total shares only includes EOAs
        uint256 totalShares = hook.totalShares();
        assertEq(totalShares, INITIAL_BALANCE + INITIAL_BALANCE / 2 + INITIAL_BALANCE / 4);
    }

    function test_sharesTracking_isEOAFlag() public view {
        // Shares are already set up via wrapping in _setupInitialBalances()
        // Check isEOA flag
        bool aliceIsEOA = !users[0].isContract();
        bool contractIsEOA = !address(contractAccount).isContract();

        assertTrue(aliceIsEOA);
        assertFalse(contractIsEOA);
    }

    /*//////////////////////////////////////////////////////////////
                          DIVIDEND DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_dividendDeposit_viaTransfer() public {
        // Shares are already set up via wrapping in _setupInitialBalances()

        uint256 dividendAmount = 1000 ether;

        // Owner transfers dividend tokens to hook using ERC20xD transfer with compose
        uint256 fee = dividendToken.quoteTransfer(owner, EXTENDED_GAS_LIMIT);

        vm.deal(owner, fee);
        vm.startPrank(owner);

        bytes memory data = abi.encode(uint128(EXTENDED_GAS_LIMIT), owner);
        bytes memory callData = abi.encodeWithSelector(hook.depositDividends.selector, dividendAmount);

        // Initiate the transfer with callData to trigger compose
        dividendToken.transfer{ value: fee }(address(hook), dividendAmount, callData, 0, data);

        // Get the nonce for the pending transfer
        uint256 nonce = dividendToken.pendingNonce(owner);

        vm.stopPrank();

        // Execute the transfer - this will trigger compose and emit DividendDeposited
        uint256 totalShares = hook.totalShares();
        uint256 expectedCumulativePerShare = (dividendAmount * 1e18) / totalShares;

        vm.expectEmit(address(hook));
        emit DividendDistributorHook.DividendDeposited(dividendAmount, expectedCumulativePerShare);

        _executeDividendTransfer(owner, nonce, "");

        // Verify dividend stats
        uint256 totalDistributed = hook.totalDividendsDistributed();
        uint256 cumulativePerShare = hook.cumulativeDividendsPerShare();
        assertEq(totalDistributed, dividendAmount);
        assertEq(cumulativePerShare, expectedCumulativePerShare);
    }

    function test_dividendDeposit_noSharesReverts() public {
        // Create a new dividend distributor hook with no initial balances
        DividendDistributorHook emptyHook =
            new DividendDistributorHook(address(erc20s[0]), address(dividendToken), address(gateways[0]), owner);

        // Add the empty hook to main token
        vm.startPrank(owner);
        WrappedERC20xD(payable(address(erc20s[0]))).addHook(address(emptyHook));
        vm.stopPrank();

        uint256 dividendAmount = 1000 ether;

        // Try to transfer dividends when no shares exist
        uint256 fee = dividendToken.quoteTransfer(owner, EXTENDED_GAS_LIMIT);
        vm.deal(owner, fee);
        vm.startPrank(owner);

        bytes memory data = abi.encode(uint128(EXTENDED_GAS_LIMIT), owner);
        bytes memory callData = abi.encodeWithSelector(emptyHook.depositDividends.selector, dividendAmount);

        // Transfer with compose - dividends won't be distributed (no shares)
        dividendToken.transfer{ value: fee }(address(emptyHook), dividendAmount, callData, 0, data);

        // Get the nonce for the pending transfer
        uint256 nonce = dividendToken.pendingNonce(owner);

        vm.stopPrank();

        // Execute the transfer - compose will call depositDividends
        _executeDividendTransfer(owner, nonce, "");

        // Verify no dividends were distributed
        uint256 totalDistributed = emptyHook.totalDividendsDistributed();
        assertEq(totalDistributed, 0);
        assertEq(emptyHook.getDividendBalance(), dividendAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          DIVIDEND CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claimDividends_basic() public {
        // Shares are already set up via wrapping in _setupInitialBalances()

        // Deposit dividends
        uint256 dividendAmount = 1500 ether;
        _depositDividends(dividendAmount);

        // Calculate expected dividends
        uint256 totalShares = INITIAL_BALANCE + INITIAL_BALANCE / 2 + INITIAL_BALANCE / 4;
        uint256 expectedAlice = (INITIAL_BALANCE * dividendAmount) / totalShares;
        uint256 expectedBob = (INITIAL_BALANCE / 2 * dividendAmount) / totalShares;

        // Alice claims
        uint256 claimFee = hook.quoteClaim(EXTENDED_GAS_LIMIT);
        vm.deal(users[0], claimFee);

        uint256 aliceBalanceBefore = dividendToken.balanceOf(users[0]);

        vm.startPrank(users[0]);
        // Don't check exact amount due to rounding
        uint256 claimedAmount = hook.claimDividends{ value: claimFee }(abi.encode(EXTENDED_GAS_LIMIT, users[0]));
        uint256 aliceNonce = dividendToken.pendingNonce(address(hook));
        vm.stopPrank();

        // Execute Alice's claim transfer
        _executeDividendTransfer(address(hook), aliceNonce, "");

        assertApproxEqAbs(dividendToken.balanceOf(users[0]), aliceBalanceBefore + expectedAlice, 1000);
        assertApproxEqAbs(claimedAmount, expectedAlice, 1000);

        // Bob claims
        vm.deal(users[1], claimFee);
        uint256 bobBalanceBefore = dividendToken.balanceOf(users[1]);

        vm.startPrank(users[1]);
        hook.claimDividends{ value: claimFee }(abi.encode(EXTENDED_GAS_LIMIT, users[1]));
        uint256 bobNonce = dividendToken.pendingNonce(address(hook));
        vm.stopPrank();

        // Execute Bob's claim transfer
        _executeDividendTransfer(address(hook), bobNonce, "");

        assertApproxEqAbs(dividendToken.balanceOf(users[1]), bobBalanceBefore + expectedBob, 1000);
    }

    function test_claimDividends_onlyEOA() public {
        // Contract already has wrapped tokens but no shares (since it's not an EOA)

        // Deposit dividends
        _depositDividends(1000 ether);

        // Contract tries to claim (should fail)
        uint256 claimFee = hook.quoteClaim(EXTENDED_GAS_LIMIT);
        vm.deal(address(contractAccount), claimFee);

        vm.prank(address(contractAccount));
        vm.expectRevert(BaseERC20xDHook.Forbidden.selector);
        hook.claimDividends{ value: claimFee }(abi.encodePacked(EXTENDED_GAS_LIMIT, address(contractAccount)));
    }

    function test_claimDividends_insufficientFee() public {
        // Shares are already set up via wrapping in _setupInitialBalances()
        _depositDividends(1000 ether);

        // Try to claim with insufficient fee
        uint256 claimFee = hook.quoteClaim(EXTENDED_GAS_LIMIT);
        vm.deal(users[0], claimFee / 2);

        vm.prank(users[0]);
        vm.expectRevert(); // TODO: which error
        hook.claimDividends{ value: claimFee / 2 }(abi.encode(EXTENDED_GAS_LIMIT, users[0]));
    }

    function test_claimDividends_noDividends() public {
        // Shares are already set up via wrapping in _setupInitialBalances()
        // Don't deposit any dividends

        uint256 claimFee = hook.quoteClaim(EXTENDED_GAS_LIMIT);
        vm.deal(users[0], claimFee);

        vm.prank(users[0]);
        vm.expectRevert(DividendDistributorHook.NoDividends.selector);
        hook.claimDividends{ value: claimFee }(abi.encode(EXTENDED_GAS_LIMIT, users[0]));
    }

    /*//////////////////////////////////////////////////////////////
                         PENDING DIVIDENDS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pendingDividends_calculation() public {
        // Shares are already set up via wrapping in _setupInitialBalances()

        // Deposit first round of dividends
        _depositDividends(1500 ether);

        // Total shares includes Alice, Bob, and Charlie (not the contract)
        uint256 totalShares = INITIAL_BALANCE + INITIAL_BALANCE / 2 + INITIAL_BALANCE / 4;
        uint256 expectedAlice = (INITIAL_BALANCE * 1500 ether) / totalShares;
        uint256 expectedBob = (INITIAL_BALANCE / 2 * 1500 ether) / totalShares;
        uint256 expectedCharlie = (INITIAL_BALANCE / 4 * 1500 ether) / totalShares;

        // Allow for small rounding differences (up to 1000 wei due to precision loss)
        assertApproxEqAbs(hook.pendingDividends(users[0]), expectedAlice, 1000);
        assertApproxEqAbs(hook.pendingDividends(users[1]), expectedBob, 1000);
        assertApproxEqAbs(hook.pendingDividends(users[2]), expectedCharlie, 1000);

        // Alice claims
        uint256 claimFee = hook.quoteClaim(EXTENDED_GAS_LIMIT);
        vm.deal(users[0], claimFee);
        vm.startPrank(users[0]);
        hook.claimDividends{ value: claimFee }(abi.encode(EXTENDED_GAS_LIMIT, users[0]));
        uint256 aliceNonce = dividendToken.pendingNonce(address(hook));
        vm.stopPrank();

        // Execute Alice's claim transfer
        _executeDividendTransfer(address(hook), aliceNonce, "");

        assertEq(hook.pendingDividends(users[0]), 0);
        assertApproxEqAbs(hook.pendingDividends(users[1]), expectedBob, 1000); // Bob's pending unchanged (with rounding tolerance)
        assertApproxEqAbs(hook.pendingDividends(users[2]), expectedCharlie, 1000); // Charlie's pending unchanged (with rounding tolerance)

        // Deposit second round
        _depositDividends(3000 ether);

        uint256 expectedAliceRound2 = (INITIAL_BALANCE * 3000 ether) / totalShares;
        uint256 expectedBobTotal = expectedBob + (INITIAL_BALANCE / 2 * 3000 ether) / totalShares;
        uint256 expectedCharlieTotal = expectedCharlie + (INITIAL_BALANCE / 4 * 3000 ether) / totalShares;

        // Allow for larger rounding differences due to multiple calculations
        assertApproxEqAbs(hook.pendingDividends(users[0]), expectedAliceRound2, 10_000);
        assertApproxEqAbs(hook.pendingDividends(users[1]), expectedBobTotal, 10_000);
        assertApproxEqAbs(hook.pendingDividends(users[2]), expectedCharlieTotal, 10_000);
    }

    /*//////////////////////////////////////////////////////////////
                         SHARE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_shareUpdate_transfer() public {
        // Shares are already set up via wrapping in _setupInitialBalances()
        // Deposit dividends
        _depositDividends(1500 ether);

        // Calculate Alice's initial pending dividends
        uint256 aliceInitialPending = hook.pendingDividends(users[0]);
        assertGt(aliceInitialPending, 0);

        // Simulate Alice transferring half her tokens to Bob via cross-chain transfer
        WrappedERC20xD mainToken = WrappedERC20xD(payable(address(erc20s[0])));

        // Alice transfers half her tokens to Bob
        vm.startPrank(users[0]);
        uint256 transferFee = mainToken.quoteTransfer(users[0], EXTENDED_GAS_LIMIT);
        vm.deal(users[0], transferFee);
        mainToken.transfer{ value: transferFee }(
            users[1], INITIAL_BALANCE / 2, abi.encode(EXTENDED_GAS_LIMIT, users[0])
        );
        uint256 nonce = mainToken.pendingNonce(users[0]);
        vm.stopPrank();

        // Execute the transfer
        _executeTransfer(users[0], nonce, "");

        // Check updated shares
        uint256 aliceShares = hook.userBalances(users[0]);
        uint256 bobShares = hook.userBalances(users[1]);

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
        // Deposit dividends
        _depositDividends(1000 ether);

        uint256 withdrawAmount = 500 ether;
        uint256 fee = dividendToken.quoteTransfer(address(hook), EXTENDED_GAS_LIMIT);

        vm.deal(owner, fee);
        vm.startPrank(owner);

        vm.expectEmit(address(hook));
        emit DividendDistributorHook.EmergencyWithdraw(users[0], withdrawAmount);

        hook.emergencyWithdraw{ value: fee }(users[0], withdrawAmount, abi.encode(EXTENDED_GAS_LIMIT, users[0]));

        uint256 nonce = dividendToken.pendingNonce(address(hook));

        vm.stopPrank();

        // Execute the emergency withdraw transfer
        _executeDividendTransfer(address(hook), nonce, "");

        assertEq(dividendToken.balanceOf(users[0]), withdrawAmount);
    }

    function test_emergencyWithdraw_onlyOwner() public {
        uint256 fee = dividendToken.quoteTransfer(address(hook), EXTENDED_GAS_LIMIT);
        vm.deal(users[0], fee);

        vm.prank(users[0]);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users[0]));
        hook.emergencyWithdraw{ value: fee }(users[0], 100 ether, abi.encode(EXTENDED_GAS_LIMIT, users[0]));
    }

    /*//////////////////////////////////////////////////////////////
                      CROSS-CHAIN DIVIDEND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crossChainDividendQuery() public {
        // Setup peers for cross-chain
        uint32 localEid = 1;
        uint32 remoteEid = 2;
        bytes32 localPeer = bytes32(uint256(uint160(address(hook))));
        bytes32 remotePeer = bytes32(uint256(uint160(address(hook))));
        vm.startPrank(owner);
        hook.setPeer(localEid, localPeer);
        hook.setPeer(remoteEid, remotePeer);
        vm.stopPrank();

        // Setup chain configs in gateway
        uint32[] memory chainEids = new uint32[](2);
        chainEids[0] = 1; // local
        chainEids[1] = remoteEid;
        uint16[] memory confirmations = new uint16[](2);
        confirmations[0] = 15;
        confirmations[1] = 15;

        vm.mockCall(
            address(gateways[0]),
            abi.encodeWithSelector(IERC20xDGateway.chainConfigs.selector),
            abi.encode(chainEids, confirmations)
        );

        // Mock getCmd response
        bytes memory expectedCmd = abi.encode("test_cmd");
        vm.mockCall(
            address(gateways[0]), abi.encodeWithSelector(IERC20xDGateway.getCmd.selector), abi.encode(expectedCmd)
        );

        // Mock quote
        uint256 expectedFee = 0.1 ether;
        vm.mockCall(
            address(gateways[0]), abi.encodeWithSelector(IERC20xDGateway.quoteRead.selector), abi.encode(expectedFee)
        );

        // Test quote function
        uint256 fee = hook.quoteGlobalDividendQuery(200_000);
        assertEq(fee, expectedFee);

        // Mock read call
        vm.mockCall(
            address(gateways[0]),
            abi.encodeWithSelector(IERC20xDGateway.read.selector),
            abi.encode(MessagingReceipt(bytes32(uint256(1)), 1, MessagingFee(0, 0)))
        );

        // Query global dividends
        vm.deal(users[0], expectedFee);
        vm.startPrank(users[0]);
        uint256 queryId = hook.queryGlobalDividends(users[0], "");
        vm.stopPrank();

        assertEq(queryId, 1);
        (address queryUser, bool pending) = hook.pendingQueries(queryId);
        assertTrue(pending);
        assertEq(queryUser, users[0]);
    }

    function test_lzReduce_dividendInfo() public {
        // Create mock command and responses
        uint16 cmdLabel = 100; // CMD_READ_DIVIDEND_INFO
        address user = users[0];

        // Create EVMCallRequestV1
        EVMCallRequestV1[] memory requests = new EVMCallRequestV1[](2);
        requests[0] = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: 1,
            isBlockNum: false,
            blockNumOrTimestamp: 0,
            confirmations: 0,
            to: address(hook),
            callData: abi.encodeWithSelector(hook.pendingDividends.selector, user)
        });
        requests[1] = requests[0];

        bytes memory cmd = ReadCodecV1.encode(cmdLabel, requests);

        // Create responses
        bytes[] memory responses = new bytes[](2);
        // Response format: just pending amount (uint256)
        responses[0] = abi.encode(15e18);
        responses[1] = abi.encode(35e18);

        // Call lzReduce
        bytes memory result = hook.lzReduce(cmd, responses);

        // Decode result
        (uint16 resultCmd, address resultUser, uint256 totalPending) = abi.decode(result, (uint16, address, uint256));

        assertEq(resultCmd, cmdLabel);
        assertEq(resultUser, user);
        assertEq(totalPending, 50e18); // 15e18 + 35e18
    }

    function test_onRead_dividendInfo() public {
        // Setup a pending query
        uint32 localEid = 1;
        uint32 remoteEid = 2;
        bytes32 localPeer = bytes32(uint256(uint160(address(hook))));
        bytes32 remotePeer = bytes32(uint256(uint160(address(hook))));
        vm.startPrank(owner);
        hook.setPeer(localEid, localPeer);
        hook.setPeer(remoteEid, remotePeer);
        vm.stopPrank();

        // Mock gateway calls for query setup
        uint32[] memory chainEids = new uint32[](1);
        chainEids[0] = 1;
        uint16[] memory confirmations = new uint16[](1);
        confirmations[0] = 15;

        vm.mockCall(
            address(gateways[0]),
            abi.encodeWithSelector(IERC20xDGateway.chainConfigs.selector),
            abi.encode(chainEids, confirmations)
        );
        vm.mockCall(address(gateways[0]), abi.encodeWithSelector(IERC20xDGateway.getCmd.selector), abi.encode(""));
        vm.mockCall(
            address(gateways[0]),
            abi.encodeWithSelector(IERC20xDGateway.read.selector),
            abi.encode(MessagingReceipt(bytes32(0), 0, MessagingFee(0, 0)))
        );

        // Create a pending query
        vm.deal(users[0], 1 ether);
        vm.startPrank(users[0]);
        uint256 queryId = hook.queryGlobalDividends(users[0], "");
        vm.stopPrank();

        // Create message
        uint16 cmdLabel = 100;
        address user = users[0];
        uint256 totalPending = 50e18;
        bytes memory message = abi.encode(cmdLabel, user, totalPending);

        // Expect event
        vm.expectEmit(address(hook));
        emit DividendDistributorHook.GlobalDividendInfo(user, totalPending, queryId);

        // Call onRead from gateway
        vm.prank(address(gateways[0]));
        hook.onRead(message);

        // Verify query is no longer pending
        (, bool pending) = hook.pendingQueries(queryId);
        assertFalse(pending);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _depositDividends(uint256 amount) internal {
        uint256 fee = dividendToken.quoteTransfer(owner, EXTENDED_GAS_LIMIT);
        vm.deal(owner, fee);

        vm.startPrank(owner);
        bytes memory data = abi.encode(uint128(EXTENDED_GAS_LIMIT), owner);
        // Encode the depositDividends function call
        bytes memory callData = abi.encodeWithSelector(hook.depositDividends.selector, amount);
        dividendToken.transfer{ value: fee }(address(hook), amount, callData, 0, data);
        uint256 nonce = dividendToken.pendingNonce(owner);
        vm.stopPrank();

        // Execute the transfer - this will trigger compose and call depositDividends
        _executeDividendTransfer(owner, nonce, "");
    }

    function _executeDividendTransfer(address from, uint256 nonce, bytes memory error) internal {
        // Build responses from all chains
        bytes[] memory responses = new bytes[](CHAINS - 1);
        uint256 count;
        for (uint256 i = 0; i < CHAINS; ++i) {
            if (i == 0) continue; // Skip local chain
            responses[count++] = abi.encode(dividendToken.availableLocalBalanceOf(from, nonce));
        }

        // Execute the transfer
        bytes memory payload = dividendToken.lzReduce(dividendToken.getReadAvailabilityCmd(from, nonce), responses);
        if (error.length > 0) {
            vm.expectRevert(error);
        }
        this.verifyPackets(eids[0], addressToBytes32(address(gateways[0])), 0, address(0), payload);
    }

    function _executeTransfer(address from, uint256 nonce, bytes memory error) internal {
        // Build responses from all chains for main token
        WrappedERC20xD mainToken = WrappedERC20xD(payable(address(erc20s[0])));
        bytes[] memory responses = new bytes[](CHAINS - 1);
        uint256 count;
        for (uint256 i = 0; i < CHAINS; ++i) {
            if (i == 0) continue; // Skip local chain
            responses[count++] = abi.encode(mainToken.availableLocalBalanceOf(from, nonce));
        }

        // Execute the transfer
        bytes memory payload = mainToken.lzReduce(mainToken.getReadAvailabilityCmd(from, nonce), responses);
        if (error.length > 0) {
            vm.expectRevert(error);
        }
        this.verifyPackets(eids[0], addressToBytes32(address(gateways[0])), 0, address(0), payload);
    }
}
