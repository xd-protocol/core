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
import { ERC20xDWrapper } from "src/ERC20xDWrapper.sol";
import { BaseERC20xDWrapper } from "src/mixins/BaseERC20xDWrapper.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { StakingVaultMock } from "./mocks/StakingVaultMock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";

contract ERC20xDWrapperTest is BaseERC20xDTestHelper {
    uint64 public constant TIMELOCK_PERIOD = 1 days;

    ERC20Mock[CHAINS] underlyings;
    StakingVaultMock vault;

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
        for (uint256 j; j < users.length; ++j) {
            underlyings[i].mint(users[j], 100e18);
        }
        return new ERC20xDWrapper(
            address(underlyings[i]),
            TIMELOCK_PERIOD,
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
    }

    function test_wrap() public {
        ERC20xDWrapper local = ERC20xDWrapper(payable(address(erc20s[0])));

        changePrank(alice, alice);

        uint256 amount = 1e18;
        (uint256 minAmount, uint256 fee) = vault.quoteDeposit(address(underlyings[0]), amount, GAS_LIMIT);

        underlyings[0].approve(address(local), amount);
        uint256 shares = local.wrap(alice, amount, minAmount, fee, abi.encode(GAS_LIMIT, alice));

        assertEq(local.balanceOf(alice), shares);
        assertEq(vault.sharesOf(address(local)), shares);
        assertEq(underlyings[0].balanceOf(address(vault)), amount);
    }

    function test_unwrap() public {
        ERC20xDWrapper local = ERC20xDWrapper(payable(address(erc20s[0])));

        changePrank(alice, alice);

        uint256 amount = 1e18;
        (uint256 minAmount, uint256 fee) = vault.quoteDeposit(address(underlyings[0]), amount, GAS_LIMIT);

        underlyings[0].approve(address(local), amount);
        bytes memory options = abi.encode(GAS_LIMIT, alice);
        uint256 shares = local.wrap(alice, amount, minAmount, fee, options);

        uint256 incomingFee;
        (minAmount, incomingFee) = vault.quoteDeposit(address(underlyings[0]), shares, GAS_LIMIT);
        bytes memory incomingData = abi.encode(alice, alice); // from, to
        uint256 outgoingFee = vault.quoteRedeem(
            address(underlyings[0]), alice, shares, minAmount, incomingData, uint128(incomingFee), options, GAS_LIMIT
        );
        uint256 readFee = local.quoteUnwrap(alice, GAS_LIMIT);
        local.unwrap{ value: incomingFee + outgoingFee + readFee }(
            alice, shares, minAmount, uint128(incomingFee), options, uint128(outgoingFee), options, options
        );

        uint256 balance = underlyings[0].balanceOf(alice);
        _executeTransfer(local, alice, 1, "");

        assertEq(local.balanceOf(alice), 0);
        assertEq(vault.sharesOf(alice), 0);
        assertEq(underlyings[0].balanceOf(alice) - balance, minAmount);
    }
}
