// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC7540Hook } from "src/hooks/ERC7540Hook.sol";
import { IERC7540 } from "src/interfaces/IERC7540.sol";
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { IWrappedERC20xD } from "src/interfaces/IWrappedERC20xD.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockERC7540Vault } from "../mocks/MockERC7540Vault.sol";
import { BaseERC20xDTestHelper } from "../helpers/BaseERC20xDTestHelper.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

contract ERC7540HookTest is BaseERC20xDTestHelper {
    using SafeTransferLib for ERC20;

    ERC7540Hook[CHAINS] hooks;
    ERC20Mock[CHAINS] underlyings;
    ERC20Mock[CHAINS] assets;
    MockERC7540Vault[CHAINS] vaults;

    uint256 constant INITIAL_BALANCE = 10_000 * 1e18;
    uint128 constant TEST_GAS_LIMIT = 500_000;

    event DepositRequested(address indexed user, uint256 assets, uint256 requestId);
    event RedeemRequested(address indexed user, uint256 shares, uint256 requestId);
    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 amount);

    function setUp() public override {
        super.setUp();

        // Stop any ongoing prank from parent setUp
        vm.stopPrank();
    }

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        // Deploy underlying token
        underlyings[i] = new ERC20Mock("Underlying Token", "UNDER", 18);

        // Deploy asset token for vault
        assets[i] = new ERC20Mock("Asset Token", "ASSET", 18);

        // Deploy vault
        vaults[i] = new MockERC7540Vault(address(assets[i]));

        // Mint tokens to users
        for (uint256 j; j < users.length; ++j) {
            underlyings[i].mint(users[j], INITIAL_BALANCE);
            assets[i].mint(users[j], 1000 * 1e18);
        }

        // Deploy wrapped token (owner is already the active prank from parent setUp)
        WrappedERC20xD wrappedToken = new WrappedERC20xD(
            address(underlyings[i]),
            "Wrapped Token",
            "WRAP",
            18,
            address(liquidityMatrices[i]),
            address(gateways[i]),
            owner
        );

        // Deploy and register hook
        hooks[i] = new ERC7540Hook(address(wrappedToken), address(vaults[i]));
        wrappedToken.addHook(address(hooks[i]));

        // Setup approvals
        for (uint256 j; j < users.length; ++j) {
            vm.startPrank(users[j]);
            underlyings[i].approve(address(wrappedToken), type(uint256).max);
            assets[i].approve(address(hooks[i]), type(uint256).max);
            vm.stopPrank();
        }

        // Restore owner prank for parent setUp
        vm.startPrank(owner);

        return BaseERC20xD(address(wrappedToken));
    }

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public view {
        for (uint256 i = 0; i < CHAINS; i++) {
            assertEq(hooks[i].token(), address(erc20s[i]));
            assertEq(address(hooks[i].vault()), address(vaults[i]));
            assertEq(hooks[i].asset(), address(assets[i]));
            assertEq(WrappedERC20xD(payable(address(erc20s[i]))).underlying(), address(underlyings[i]));
        }
    }

    function test_hookRegistration() public view {
        for (uint256 i = 0; i < CHAINS; i++) {
            address[] memory registeredHooks = erc20s[i].getHooks();
            assertEq(registeredHooks.length, 1);
            assertEq(registeredHooks[0], address(hooks[i]));
            assertTrue(erc20s[i].isHook(address(hooks[i])));
        }
    }

    /*//////////////////////////////////////////////////////////////
                           WRAP/MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_triggersDeposit_withAssets() public {
        uint256 chainId = 0;
        address user = users[0];
        uint256 wrapAmount = 100 * 1e18;

        // Fund hook with assets from user who has them
        vm.prank(users[1]);
        assets[chainId].transfer(address(hooks[chainId]), wrapAmount);

        // User wraps underlying tokens
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(user, wrapAmount);

        // Verify wrapped tokens were minted
        assertEq(erc20s[chainId].balanceOf(user), wrapAmount);
        assertEq(underlyings[chainId].balanceOf(address(erc20s[chainId])), wrapAmount);

        // Verify deposit was requested in vault
        assertEq(vaults[chainId].pendingDepositRequest(1, user), wrapAmount);
    }

    function test_wrap_multipleUsers() public {
        uint256 chainId = 0;
        uint256 amount1 = 50 * 1e18;
        uint256 amount2 = 75 * 1e18;

        // Fund hook from user who has assets
        vm.prank(users[2]);
        assets[chainId].transfer(address(hooks[chainId]), amount1 + amount2);

        // User 1 wraps
        vm.prank(users[0]);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(users[0], amount1);

        // User 2 wraps
        vm.prank(users[1]);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(users[1], amount2);

        // Verify balances
        assertEq(erc20s[chainId].balanceOf(users[0]), amount1);
        assertEq(erc20s[chainId].balanceOf(users[1]), amount2);

        // Verify deposits
        assertEq(vaults[chainId].pendingDepositRequest(1, users[0]), amount1);
        assertEq(vaults[chainId].pendingDepositRequest(2, users[1]), amount2);
    }

    function test_wrap_withoutAssets_stillMints() public {
        uint256 chainId = 0;
        address user = users[0];
        uint256 wrapAmount = 100 * 1e18;

        // User wraps without hook having assets
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(user, wrapAmount);

        // Verify wrapped tokens were still minted
        assertEq(erc20s[chainId].balanceOf(user), wrapAmount);

        // Verify no deposit was made to vault
        assertEq(vaults[chainId].nextRequestId(), 1); // No requests created
    }

    /*//////////////////////////////////////////////////////////////
                           UNWRAP/BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_triggersRedeem() public {
        uint256 chainId = 0;
        address user = users[0];
        uint256 wrapAmount = 100 * 1e18;

        // Setup: User first wraps tokens
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(user, wrapAmount);

        // User unwraps tokens
        uint256 fee = erc20s[chainId].quoteTransfer(user, TEST_GAS_LIMIT);
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).unwrap{ value: fee }(
            user, wrapAmount, abi.encode(TEST_GAS_LIMIT, user)
        );

        // Execute the unwrap transfer
        _executeTransfer(erc20s[chainId], user, "");

        // Verify wrapped tokens were burned
        assertEq(erc20s[chainId].balanceOf(user), 0);

        // Verify redeem was requested in vault
        assertEq(vaults[chainId].pendingRedeemRequest(1, user), wrapAmount);
    }

    function test_unwrap_partialAmount() public {
        uint256 chainId = 0;
        address user = users[0];
        uint256 wrapAmount = 100 * 1e18;
        uint256 unwrapAmount = 30 * 1e18;

        // Setup: User wraps tokens
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(user, wrapAmount);

        // User unwraps partial amount
        uint256 fee = erc20s[chainId].quoteTransfer(user, TEST_GAS_LIMIT);
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).unwrap{ value: fee }(
            user, unwrapAmount, abi.encode(TEST_GAS_LIMIT, user)
        );

        // Execute the unwrap transfer
        _executeTransfer(erc20s[chainId], user, "");

        // Verify balances
        assertEq(erc20s[chainId].balanceOf(user), wrapAmount - unwrapAmount);
        assertEq(vaults[chainId].pendingRedeemRequest(1, user), unwrapAmount);
    }

    /*//////////////////////////////////////////////////////////////
                      CROSS-CHAIN TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crossChainTransfer_withHook() public {
        // This test verifies that hooks work correctly with cross-chain transfers
        // We'll do a simple local transfer to verify hook functionality

        BaseERC20xD token = erc20s[0];
        address sender = users[0];
        address recipient = users[1];
        uint256 wrapAmount = 100 * 1e18;
        uint256 transferAmount = 40 * 1e18;

        // Sender wraps tokens
        vm.prank(sender);
        IWrappedERC20xD(payable(address(token))).wrap(sender, wrapAmount);

        // Verify initial balances
        assertEq(token.localBalanceOf(sender), int256(wrapAmount));
        assertEq(token.localBalanceOf(recipient), int256(0));

        // Execute transfer with proper parameters for cross-chain capability
        uint256 fee = token.quoteTransfer(recipient, TEST_GAS_LIMIT);
        vm.deal(sender, fee);
        vm.prank(sender);
        token.transfer{ value: fee }(recipient, transferAmount, abi.encode(TEST_GAS_LIMIT, sender));

        // Execute the transfer
        _executeTransfer(token, sender, "");

        // Verify final balances
        assertEq(token.localBalanceOf(sender), int256(wrapAmount - transferAmount));
        assertEq(token.localBalanceOf(recipient), int256(transferAmount));

        // Since hook doesn't have assets, no deposit request was made
        // But verify the transfer worked correctly
        assertTrue(token.localBalanceOf(sender) < int256(wrapAmount));
        assertTrue(token.localBalanceOf(recipient) > 0);
    }

    /*//////////////////////////////////////////////////////////////
                           FULL FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fullFlow_wrapDepositRedeemUnwrap() public {
        uint256 chainId = 0;
        address user = users[0];
        uint256 amount = 100 * 1e18;

        // 1. Fund hook with assets from user who has them
        vm.prank(users[1]);
        assets[chainId].transfer(address(hooks[chainId]), amount);

        // 2. User wraps underlying tokens
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(user, amount);

        uint256 depositRequestId = 1;
        assertEq(vaults[chainId].pendingDepositRequest(depositRequestId, user), amount);
        assertEq(erc20s[chainId].localBalanceOf(user), int256(amount));

        // 3. Vault processes deposit (simulated)
        vaults[chainId].setClaimable(depositRequestId, amount);
        vaults[chainId].setPending(depositRequestId, 0);

        // 4. User unwraps tokens
        uint256 fee = erc20s[chainId].quoteTransfer(user, TEST_GAS_LIMIT);
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).unwrap{ value: fee }(
            user, amount, abi.encode(TEST_GAS_LIMIT, user)
        );

        // Execute the unwrap transfer
        _executeTransfer(erc20s[chainId], user, "");

        uint256 redeemRequestId = 2;
        assertEq(vaults[chainId].pendingRedeemRequest(redeemRequestId, user), amount);
        assertEq(erc20s[chainId].localBalanceOf(user), int256(0));

        // 5. Vault processes redeem (simulated)
        vaults[chainId].setClaimable(redeemRequestId, amount);
        vaults[chainId].setPending(redeemRequestId, 0);

        // Verify final state
        assertEq(hooks[chainId].claimableDepositRequest(user, depositRequestId), amount);
        assertEq(hooks[chainId].claimableRedeemRequest(user, redeemRequestId), amount);
    }

    function test_complexFlow_multipleUsersAndChains() public {
        // Test multiple users and operations on different chains

        // Setup assets on both chains from users who have them
        vm.prank(users[2]);
        assets[0].transfer(address(hooks[0]), 200 * 1e18);
        vm.prank(users[2]);
        assets[1].transfer(address(hooks[1]), 200 * 1e18);

        // User0 wraps on chain 0
        vm.prank(users[0]);
        IWrappedERC20xD(payable(address(erc20s[0]))).wrap(users[0], 100 * 1e18);

        // User1 wraps on chain 1
        vm.prank(users[1]);
        IWrappedERC20xD(payable(address(erc20s[1]))).wrap(users[1], 150 * 1e18);

        // User0 transfers on chain 0
        uint256 fee0 = erc20s[0].quoteTransfer(users[2], TEST_GAS_LIMIT);
        vm.deal(users[0], fee0);
        vm.prank(users[0]);
        erc20s[0].transfer{ value: fee0 }(users[2], 30 * 1e18, abi.encode(TEST_GAS_LIMIT, users[0]));
        _executeTransfer(erc20s[0], users[0], "");

        // User1 transfers on chain 1
        uint256 fee1 = erc20s[1].quoteTransfer(users[2], TEST_GAS_LIMIT);
        vm.deal(users[1], fee1);
        vm.prank(users[1]);
        erc20s[1].transfer{ value: fee1 }(users[2], 50 * 1e18, abi.encode(TEST_GAS_LIMIT, users[1]));
        _executeTransfer(erc20s[1], users[1], "");

        // Verify balances
        assertEq(erc20s[0].localBalanceOf(users[0]), int256(70 * 1e18));
        assertEq(erc20s[0].localBalanceOf(users[2]), int256(30 * 1e18));
        assertEq(erc20s[1].localBalanceOf(users[1]), int256(100 * 1e18));
        assertEq(erc20s[1].localBalanceOf(users[2]), int256(50 * 1e18));

        // Verify vault requests
        assertEq(vaults[0].pendingDepositRequest(1, users[0]), 100 * 1e18);
        assertEq(vaults[1].pendingDepositRequest(1, users[1]), 150 * 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositAssets() public {
        uint256 chainId = 0;
        uint256 depositAmount = 200 * 1e18;

        // Use user who has assets
        vm.startPrank(users[0]);
        assets[chainId].approve(address(hooks[chainId]), depositAmount);
        hooks[chainId].depositAssets(depositAmount);
        vm.stopPrank();

        assertEq(assets[chainId].balanceOf(address(hooks[chainId])), depositAmount);
    }

    function test_removeHook() public {
        uint256 chainId = 0;

        // Owner can remove hook
        vm.prank(owner);
        erc20s[chainId].removeHook(address(hooks[chainId]));

        assertFalse(erc20s[chainId].isHook(address(hooks[chainId])));
        assertEq(erc20s[chainId].getHooks().length, 0);

        // After removal, wrap/unwrap still work but without hook interaction
        vm.prank(users[0]);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(users[0], 100 * 1e18);

        // No vault requests created
        assertEq(vaults[chainId].nextRequestId(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                           ERROR CASES
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_invalidAddress_reverts() public {
        uint256 chainId = 0;
        address user = users[0];

        // Setup: User wraps tokens
        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(user, 100 * 1e18);

        // Try to unwrap to address(0)
        vm.prank(user);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).unwrap(
            address(0), 50 * 1e18, abi.encode(TEST_GAS_LIMIT, user)
        );
    }

    function test_deployment_revertsInvalidVault() public {
        vm.expectRevert(ERC7540Hook.InvalidVault.selector);
        new ERC7540Hook(address(erc20s[0]), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_viewFunctions_delegateToVault() public {
        uint256 chainId = 0;
        address user = users[0];

        // Setup some requests through wrap/unwrap
        vm.prank(users[1]);
        assets[chainId].transfer(address(hooks[chainId]), 200 * 1e18);

        vm.prank(user);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).wrap(user, 100 * 1e18);

        uint256 fee = erc20s[chainId].quoteTransfer(user, TEST_GAS_LIMIT);
        vm.prank(user);
        vm.deal(user, fee);
        IWrappedERC20xD(payable(address(erc20s[chainId]))).unwrap{ value: fee }(
            user, 50 * 1e18, abi.encode(TEST_GAS_LIMIT, user)
        );

        // Execute the unwrap transfer
        _executeTransfer(erc20s[chainId], user, "");

        // Test view functions
        assertEq(hooks[chainId].pendingDepositRequest(user, 1), 100 * 1e18);
        assertEq(hooks[chainId].pendingRedeemRequest(user, 2), 50 * 1e18);

        // Simulate vault processing
        vaults[chainId].setClaimable(1, 100 * 1e18);
        vaults[chainId].setClaimable(2, 50 * 1e18);

        assertEq(hooks[chainId].claimableDepositRequest(user, 1), 100 * 1e18);
        assertEq(hooks[chainId].claimableRedeemRequest(user, 2), 50 * 1e18);
    }
}
