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
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { StakingVaultMock } from "./mocks/StakingVaultMock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";

contract NativexDTest is BaseERC20xDTestHelper {
    address constant NATIVE = address(0);

    StakingVaultMock vault;

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        return new NativexD(address(vault), "xD", "xD", 18, address(liquidityMatrices[i]), address(gateways[i]), owner);
    }

    function setUp() public override {
        vault = new StakingVaultMock();
        super.setUp();
    }

    function test_wrap() public {
        NativexD local = NativexD(payable(address(erc20s[0])));

        changePrank(alice, alice);

        uint256 amount = 1e18;
        (uint256 minAmount, uint256 fee) = vault.quoteDepositNative(amount, GAS_LIMIT);

        uint256 balance = address(vault).balance;
        uint256 shares = local.wrap{ value: amount + fee }(alice, amount, fee, abi.encode(minAmount, GAS_LIMIT, alice));

        assertEq(local.balanceOf(alice), shares);
        assertEq(vault.sharesOf(NATIVE, address(local)), shares);
        assertEq(address(vault).balance - balance - fee, amount);
    }

    function test_unwrap() public {
        NativexD local = NativexD(payable(address(erc20s[0])));

        changePrank(alice, alice);

        uint256 amount = 1e18;
        (uint256 minAmount, uint256 fee) = vault.quoteDepositNative(amount, GAS_LIMIT);

        bytes memory data = abi.encode(minAmount, GAS_LIMIT, alice);
        uint256 shares = local.wrap{ value: amount + fee }(alice, amount, fee, data);

        bytes memory callbackData = abi.encode(alice, alice); // from, to
        uint256 receivingFee;
        (minAmount, receivingFee) = vault.quoteSendTokenNative(shares, callbackData, GAS_LIMIT);
        bytes memory redeemData = abi.encode(minAmount, GAS_LIMIT, alice);
        bytes memory receivingData = abi.encode(GAS_LIMIT, alice);
        uint256 redeemFee =
            local.quoteRedeem(alice, alice, shares, receivingData, uint128(receivingFee), minAmount, GAS_LIMIT);
        fee = local.quoteUnwrap(alice, redeemFee, GAS_LIMIT);
        bytes memory readData = abi.encode(GAS_LIMIT, alice);
        local.unwrap{ value: fee }(alice, shares, receivingData, uint128(receivingFee), redeemData, redeemFee, readData);

        uint256 balance = alice.balance;
        _executeTransfer(local, alice, 1, "");

        assertEq(local.balanceOf(alice), 0);
        assertEq(vault.sharesOf(NATIVE, alice), 0);
        assertEq(alice.balance - balance, minAmount);
    }
}
