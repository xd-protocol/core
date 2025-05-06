// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { Test, Vm, console } from "forge-std/Test.sol";
import { Settler } from "src/settlers/Settler.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { ERC20xDWrapper } from "src/ERC20xDWrapper.sol";
import { BaseERC20xDWrapper } from "src/mixins/BaseERC20xDWrapper.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { LzLib } from "src/libraries/LzLib.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { BaseLiquidityMatrixTest } from "./BaseLiquidityMatrixTest.sol";

contract BaseERC20xDWrapperTest is BaseLiquidityMatrixTest {
    uint8 public constant CHAINS = 8;
    uint64 public constant TIMELOCK_PERIOD = 1 days;
    uint16 public constant CMD_XD_TRANSFER = 1;
    uint96 public constant GAS_LIMIT = 500_000;

    uint32[CHAINS] eids;
    ERC20Mock[CHAINS] underlyings;
    address[CHAINS] vaults;
    ILiquidityMatrix[CHAINS] liquidityMatrices;
    address[CHAINS] settlers;
    ERC20xDWrapper[CHAINS] erc20s;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address[] users = [alice, bob, charlie];

    function setUp() public override {
        super.setUp();
        setUpEndpoints(CHAINS, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        address[] memory oapps = new address[](CHAINS);
        address[] memory _erc20s = new address[](CHAINS);
        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            underlyings[i] = new ERC20Mock("Mock", "MOCK", 18);
            vaults[i] = makeAddr(string.concat("vault", vm.toString(i)));
            liquidityMatrices[i] = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[eids[i]], owner);
            settlers[i] = address(new Settler(address(liquidityMatrices[i])));
            oapps[i] = address(liquidityMatrices[i]);
            erc20s[i] = new ERC20xDWrapper(
                address(underlyings[i]),
                TIMELOCK_PERIOD,
                vaults[i],
                "xD",
                "xD",
                18,
                address(liquidityMatrices[i]),
                owner
            );
            _erc20s[i] = address(erc20s[i]);

            liquidityMatrices[i].updateSettlerWhitelisted(settlers[i], true);
            vm.label(address(liquidityMatrices[i]), string.concat("LiquidityMatrix", vm.toString(i)));
            vm.label(address(erc20s[i]), string.concat("ERC20xDWrapper", vm.toString(i)));
            vm.deal(settlers[i], 1000e18);
        }

        wireOApps(address[](oapps));
        wireOApps(address[](_erc20s));

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(address(erc20s[i]), 1000e18);
            changePrank(address(erc20s[i]), address(erc20s[i]));
            liquidityMatrices[i].registerApp(false, false, settlers[i]);

            ILiquidityMatrix.ChainConfig[] memory configs = new ILiquidityMatrix.ChainConfig[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configs[count++] = ILiquidityMatrix.ChainConfig(eids[j], 0);
                liquidityMatrices[i].updateRemoteApp(eids[j], address(erc20s[j]));
            }

            changePrank(owner, owner);
            liquidityMatrices[i].configChains(configs);
            for (uint256 j; j < users.length; ++j) {
                underlyings[i].mint(users[j], 100e18);
            }
        }

        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }
    }

    function test_queueUpdateTimeLockPeriod() public {
        ERC20xDWrapper local = erc20s[0];

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
        ERC20xDWrapper local = erc20s[0];

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
        ERC20xDWrapper local = erc20s[0];

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
