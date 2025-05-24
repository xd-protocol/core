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
import { LzLib } from "src/libraries/LzLib.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { BaseERC20xDTestHelper } from "./helpers/BaseERC20xDTestHelper.sol";

contract BaseERC20xDWrapperTest is BaseERC20xDTestHelper {
    uint64 public constant TIMELOCK_PERIOD = 1 days;

    ERC20Mock[CHAINS] underlyings;
    address[CHAINS] vaults;

    function _newBaseERC20xD(uint256 i) internal override returns (BaseERC20xD) {
        underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
        for (uint256 j; j < users.length; ++j) {
            underlyings[i].mint(users[j], 100e18);
        }
        vaults[i] = makeAddr(string.concat("vault", vm.toString(i)));
        return new ERC20xDWrapper(
            address(underlyings[i]), TIMELOCK_PERIOD, vaults[i], "xD", "xD", 18, address(liquidityMatrices[i]), owner
        );
    }

    function test_queueUpdateTimeLockPeriod() public {
        ERC20xDWrapper local = ERC20xDWrapper(payable(address(erc20s[0])));

        uint64 timestamp = uint64(vm.getBlockTimestamp());
        local.queueUpdateTimeLockPeriod(1 weeks);

        (BaseERC20xDWrapper.TimeLockType _type, bytes memory params, uint64 startedAt, bool executed) =
            local.timeLocks(0);
        assertEq(uint8(_type), uint8(BaseERC20xDWrapper.TimeLockType.UpdateTimeLockPeriod));
        assertEq(params, abi.encode(uint64(1 weeks)));
        assertEq(startedAt, timestamp);
        assertEq(executed, false);
    }

    function test_queueUpdateVault() public {
        ERC20xDWrapper local = ERC20xDWrapper(payable(address(erc20s[0])));

        address vault = makeAddr("vault");
        uint64 timestamp = uint64(vm.getBlockTimestamp());
        local.queueUpdateVault(vault);

        (BaseERC20xDWrapper.TimeLockType _type, bytes memory params, uint64 startedAt, bool executed) =
            local.timeLocks(0);
        assertEq(uint8(_type), uint8(BaseERC20xDWrapper.TimeLockType.UpdateVault));
        assertEq(params, abi.encode(vault));
        assertEq(startedAt, timestamp);
        assertEq(executed, false);
    }

    function test_executeTimeLock() public {
        ERC20xDWrapper local = ERC20xDWrapper(payable(address(erc20s[0])));

        local.queueUpdateTimeLockPeriod(1 weeks);

        vm.expectRevert(BaseERC20xDWrapper.TimeNotPassed.selector);
        local.executeTimeLock(0);

        skip(TIMELOCK_PERIOD);
        local.executeTimeLock(0);

        assertEq(local.timeLockPeriod(), 1 weeks);

        vm.expectRevert(BaseERC20xDWrapper.TimeLockExecuted.selector);
        local.executeTimeLock(0);

        address vault = makeAddr("vault");
        local.queueUpdateVault(vault);

        vm.expectRevert(BaseERC20xDWrapper.TimeNotPassed.selector);
        local.executeTimeLock(1);

        skip(1 weeks);
        local.executeTimeLock(1);

        assertEq(local.vault(), vault);

        vm.expectRevert(BaseERC20xDWrapper.TimeLockExecuted.selector);
        local.executeTimeLock(1);
    }
}
