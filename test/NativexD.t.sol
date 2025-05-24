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
import { BaseERC20xDWrapper } from "src/mixins/BaseERC20xDWrapper.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { LzLib } from "src/libraries/LzLib.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { StakingVaultMock } from "./mocks/StakingVaultMock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";

contract NativexDTest is BaseERC20xDTestHelper {
    uint64 public constant TIMELOCK_PERIOD = 1 days;

    StakingVaultMock vault;

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        return new NativexD(TIMELOCK_PERIOD, address(vault), "xD", "xD", 18, address(liquidityMatrices[i]), owner);
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
        uint256 shares =
            local.wrap{ value: amount + fee }(alice, amount, minAmount, fee, LzLib.encodeOptions(GAS_LIMIT, alice));

        assertEq(local.balanceOf(alice), shares);
        assertEq(vault.sharesOf(address(local)), shares);
        assertEq(address(vault).balance - balance - fee, amount);
    }

    function test_unwrap() public {
        NativexD local = NativexD(payable(address(erc20s[0])));

        changePrank(alice, alice);

        uint256 amount = 1e18;
        (uint256 minAmount, uint256 fee) = vault.quoteDepositNative(amount, GAS_LIMIT);

        bytes memory options = LzLib.encodeOptions(GAS_LIMIT, alice);
        uint256 shares = local.wrap{ value: amount + fee }(alice, amount, minAmount, fee, options);

        uint256 incomingFee;
        (minAmount, incomingFee) = vault.quoteDepositNative(shares, GAS_LIMIT);
        bytes memory incomingData = abi.encode(alice, alice); // from, to
        fee = vault.quoteRedeemNative(alice, shares, minAmount, incomingData, uint128(incomingFee), options, GAS_LIMIT);
        uint256 readFee = local.quoteUnwrap(alice, GAS_LIMIT);
        local.unwrap{ value: fee + readFee }(
            alice, shares, minAmount, uint128(incomingFee), options, uint128(fee), options, options
        );

        uint256 balance = alice.balance;
        _executeTransfer(local, alice, 1, "");

        assertEq(local.balanceOf(alice), 0);
        assertEq(vault.sharesOf(alice), 0);
        assertEq(alice.balance - balance, minAmount);
    }
}
