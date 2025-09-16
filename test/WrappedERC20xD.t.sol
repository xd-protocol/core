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
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IBaseERC20xD } from "src/interfaces/IBaseERC20xD.sol";
import { IWrappedERC20xD } from "src/interfaces/IWrappedERC20xD.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import {
    MessagingReceipt, Origin
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract WrappedERC20xDTest is BaseERC20xDTestHelper {
    using SafeTransferLib for ERC20;

    ERC20Mock[CHAINS] underlyings;

    uint32 constant LOCAL_EID = 101;
    uint128 constant TEST_GAS_LIMIT = 200_000;

    event Wrap(address to, uint256 amount);
    event Unwrap(address to, uint256 amount);

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
        for (uint256 j; j < users.length; ++j) {
            underlyings[i].mint(users[j], 100e18);
        }
        return BaseERC20xD(
            address(
                new WrappedERC20xD(
                    address(underlyings[i]),
                    "Mock Wrapped",
                    "mWRAPPED",
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

        // Approve wrapped token contracts
        for (uint256 i; i < CHAINS; ++i) {
            for (uint256 j; j < users.length; ++j) {
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
        assertEq(wrapped.owner(), owner);
        assertEq(wrapped.name(), "Mock Wrapped");
        assertEq(wrapped.symbol(), "mWRAPPED");
        assertEq(wrapped.decimals(), 18);
    }

    /*//////////////////////////////////////////////////////////////
                            WRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_wrap_basic() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        vm.startPrank(alice);

        uint256 underlyingBefore = underlyings[0].balanceOf(alice);

        vm.expectEmit();
        emit IWrappedERC20xD.Wrap(alice, amount);
        wrapped.wrap(alice, amount, "");

        assertEq(wrapped.balanceOf(alice), amount); // Direct 1:1 minting
        assertEq(underlyings[0].balanceOf(alice), underlyingBefore - amount);
        assertEq(underlyings[0].balanceOf(address(wrapped)), amount); // Tokens held by contract

        vm.stopPrank();
    }

    function test_wrap_differentRecipient() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        vm.prank(alice);
        wrapped.wrap(bob, amount, "");

        assertEq(wrapped.balanceOf(bob), amount);
        assertEq(wrapped.balanceOf(alice), 0);
    }

    function test_wrap_revertZeroAddress() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAddress.selector);
        wrapped.wrap(address(0), 50e18, "");
    }

    function test_wrap_revertZeroAmount() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAmount.selector);
        wrapped.wrap(alice, 0, "");
    }

    function test_wrap_multipleUsers() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");

        vm.prank(bob);
        wrapped.wrap(bob, 30e18, "");

        assertEq(wrapped.balanceOf(alice), 50e18);
        assertEq(wrapped.balanceOf(bob), 30e18);
        assertEq(wrapped.totalSupply(), 80e18);
        assertEq(underlyings[0].balanceOf(address(wrapped)), 80e18);
    }

    /*//////////////////////////////////////////////////////////////
                           UNWRAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unwrap_basic() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 amount = 50e18;

        // Step 1: Alice wraps tokens
        vm.prank(alice);
        wrapped.wrap(alice, amount, "");
        assertEq(wrapped.balanceOf(alice), amount);

        // Step 2: Alice initiates unwrap
        uint256 fee = wrapped.quoteTransfer(alice, uint128(GAS_LIMIT));
        vm.prank(alice);
        bytes memory data = abi.encode(uint128(GAS_LIMIT), alice); // gasLimit, refundTo
        wrapped.unwrap{ value: fee }(alice, amount, data, "");

        // The actual redemption happens via hooks in afterTransfer
        // For this test, we're just verifying the unwrap call succeeds
    }

    function test_unwrap_revertZeroAddress() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");

        vm.prank(alice);
        vm.expectRevert(IBaseERC20xD.InvalidAddress.selector);
        wrapped.unwrap(address(0), 50e18, "", "");
    }

    function test_unwrap_differentRecipient() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // Alice wraps
        vm.prank(alice);
        wrapped.wrap(alice, 50e18, "");

        // Alice unwraps to bob
        uint256 fee = wrapped.quoteTransfer(alice, uint128(GAS_LIMIT));
        vm.prank(alice);
        bytes memory data = abi.encode(uint128(GAS_LIMIT), alice);
        wrapped.unwrap{ value: fee }(bob, 25e18, data, "");

        // The actual token transfer to bob happens via hooks
    }

    /*//////////////////////////////////////////////////////////////
                         FALLBACK/RECEIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fallback() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
        uint256 initialBalance = address(wrapped).balance;
        vm.prank(alice);

        // Send with data (triggers fallback)
        (bool success,) = address(wrapped).call{ value: 0.5 ether }(hex"1234");
        assertTrue(success);
        assertEq(address(wrapped).balance, initialBalance + 0.5 ether);
    }

    function test_receive() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));
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

    function test_quoteUnwrap() public {
        WrappedERC20xD wrapped = WrappedERC20xD(payable(address(erc20s[0])));

        // Quote unwrap should return the same as quoteTransfer
        uint256 expectedFee = wrapped.quoteTransfer(alice, 500_000);

        vm.prank(alice);
        uint256 actualFee = wrapped.quoteUnwrap(500_000);

        assertEq(actualFee, expectedFee);
        assertGt(actualFee, 0); // Should be non-zero for cross-chain messaging
    }
}
