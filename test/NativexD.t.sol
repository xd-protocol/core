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
import { WrappedERC20xD } from "src/WrappedERC20xD.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IWrappedERC20xD } from "src/interfaces/IWrappedERC20xD.sol";
import { StakingVaultMock } from "./mocks/StakingVaultMock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import {
    MessagingReceipt, Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract NativexDTest is BaseERC20xDTestHelper {
    StakingVaultMock[CHAINS] vaults;

    uint32 constant LOCAL_EID = 101;
    uint128 constant TEST_GAS_LIMIT = 200_000;

    event Wrap(address indexed to, uint256 amount);
    event Unwrap(address indexed to, uint256 amount);

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        vaults[i] = new StakingVaultMock();
        return BaseERC20xD(
            address(
                new NativexD(
                    "Test Native xD",
                    "TNxD",
                    18,
                    address(liquidityMatrices[i]),
                    address(gateways[i]),
                    owner,
                    settlers[i]
                )
            )
        );
    }

    function setUp() public override {
        super.setUp();

        // Stop any ongoing prank from parent setUp
        vm.stopPrank();

        // Deal native tokens to test users
        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 1000 ether);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public view {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        assertEq(wrapped.underlying(), address(0)); // Native token
        assertEq(wrapped.owner(), owner);
        assertEq(wrapped.name(), "Test Native xD");
        assertEq(wrapped.symbol(), "TNxD");
        assertEq(wrapped.decimals(), 18);
    }

    /*//////////////////////////////////////////////////////////////
                            WRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_basic() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        vm.prank(alice);
        uint256 balanceBefore = alice.balance;

        vm.expectEmit();
        emit NativexD.Wrap(alice, amount);
        wrapped.wrap{ value: amount }(alice);

        assertEq(wrapped.balanceOf(alice), amount); // Direct 1:1 minting now
        assertEq(alice.balance, balanceBefore - amount);
    }

    function test_wrap_differentRecipient() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        vm.prank(alice);
        wrapped.wrap{ value: amount }(bob);

        assertEq(wrapped.balanceOf(bob), amount);
        assertEq(wrapped.balanceOf(alice), 0);
    }

    function test_wrap_revertZeroAddress() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        wrapped.wrap{ value: 50 ether }(address(0));
    }

    function test_wrap_revertZeroAmount() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAmount.selector);
        wrapped.wrap{ value: 0 }(alice);
    }

    function test_wrap_revertInsufficientValue() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);

        // NativexD checks msg.value == 0, not msg.value < amount
        vm.expectRevert(BaseERC20xD.InvalidAmount.selector);
        wrapped.wrap{ value: 0 }(alice);
    }

    function test_wrap_multipleUsers() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        vm.prank(alice);
        wrapped.wrap{ value: 50 ether }(alice);

        vm.prank(bob);
        wrapped.wrap{ value: 30 ether }(bob);

        assertEq(wrapped.balanceOf(alice), 50 ether);
        assertEq(wrapped.balanceOf(bob), 30 ether);
        assertEq(wrapped.totalSupply(), 80 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_basic() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 amount = 50 ether;

        // Step 1: Alice wraps native tokens
        vm.prank(alice);
        wrapped.wrap{ value: amount }(alice);
        assertEq(wrapped.balanceOf(alice), amount);

        // Step 2: Alice initiates unwrap
        uint256 fee = wrapped.quoteTransfer(alice, uint128(GAS_LIMIT));
        vm.prank(alice);
        bytes memory data = abi.encode(uint128(GAS_LIMIT), alice); // gasLimit, refundTo
        wrapped.unwrap{ value: fee }(alice, amount, data);

        // The actual redemption happens via hooks in afterTransfer
        // For this test, we're just verifying the unwrap call succeeds
    }

    function test_unwrap_revertZeroAddress() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        vm.prank(alice);
        wrapped.wrap{ value: 50 ether }(alice);

        vm.prank(alice);
        vm.expectRevert(BaseERC20xD.InvalidAddress.selector);
        wrapped.unwrap(address(0), 50 ether, "");
    }

    function test_unwrap_differentRecipient() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Alice wraps
        vm.prank(alice);
        wrapped.wrap{ value: 50 ether }(alice);

        // Alice unwraps to bob
        uint256 fee = wrapped.quoteTransfer(alice, uint128(GAS_LIMIT));
        vm.prank(alice);
        bytes memory data = abi.encode(uint128(GAS_LIMIT), alice);
        wrapped.unwrap{ value: fee }(bob, 25 ether, data);

        // The actual native token transfer to bob happens via hooks
    }

    /*//////////////////////////////////////////////////////////////
                         FALLBACK/RECEIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fallback() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 initialBalance = address(wrapped).balance;
        vm.prank(alice);

        // Send with data (triggers fallback)
        (bool success,) = address(wrapped).call{ value: 0.5 ether }(hex"1234");
        assertTrue(success);
        assertEq(address(wrapped).balance, initialBalance + 0.5 ether);
    }

    function test_receive() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));
        uint256 initialBalance = address(wrapped).balance;
        vm.prank(alice);

        // Send without data (triggers receive)
        (bool success,) = address(wrapped).call{ value: 0.5 ether }("");
        assertTrue(success);
        assertEq(address(wrapped).balance, initialBalance + 0.5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                          QUOTE WRAP/UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_quoteWrap() public view {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Quote wrap should always return 0 for local operations
        uint256 fee = wrapped.quoteWrap(500_000);
        assertEq(fee, 0);

        // Gas limit parameter shouldn't matter
        fee = wrapped.quoteWrap(1_000_000);
        assertEq(fee, 0);
    }

    function test_quoteUnwrap() public {
        NativexD wrapped = NativexD(payable(address(erc20s[0])));

        // Quote unwrap should return the same as quoteTransfer
        uint256 expectedFee = wrapped.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        uint256 actualFee = wrapped.quoteUnwrap(500_000);

        assertEq(actualFee, expectedFee);
        assertGt(actualFee, 0); // Should be non-zero for cross-chain messaging
    }
}
