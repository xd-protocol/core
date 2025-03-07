// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { Test, Vm, console } from "forge-std/Test.sol";
import { MockERC20 } from "forge-std/mocks/MockERC20.sol";
import { Settler } from "src/settlers/Settler.sol";
import { Synchronizer } from "src/Synchronizer.sol";
import { xDERC20Wrapper } from "src/xDERC20Wrapper.sol";
import { BasexDERC20Wrapper } from "src/mixins/BasexDERC20Wrapper.sol";
import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { LzLib } from "src/libraries/LzLib.sol";
import { BaseSynchronizerTest } from "./BaseSynchronizerTest.sol";

contract ERC20 is MockERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) {
        initialize(name, symbol, decimals);
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}

contract BasexDERC20WrapperTest is BaseSynchronizerTest {
    uint8 public constant CHAINS = 8;
    uint64 public constant TIMELOCK_PERIOD = 1 days;
    uint16 public constant CMD_XD_TRANSFER = 1;
    uint96 public constant GAS_LIMIT = 500_000;

    uint32[CHAINS] eids;
    ERC20[CHAINS] underlyings;
    address[CHAINS] vaults;
    ISynchronizer[CHAINS] synchronizers;
    address[CHAINS] settlers;
    xDERC20Wrapper[CHAINS] erc20s;

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
            underlyings[i] = new ERC20("Mock", "MOCK", 18);
            vaults[i] = makeAddr(string.concat("vault", vm.toString(i)));
            synchronizers[i] = new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[eids[i]], owner);
            settlers[i] = address(new Settler(address(synchronizers[i])));
            oapps[i] = address(synchronizers[i]);
            erc20s[i] = new xDERC20Wrapper(
                address(underlyings[i]), TIMELOCK_PERIOD, vaults[i], "xD", "xD", 18, address(synchronizers[i]), owner
            );
            _erc20s[i] = address(erc20s[i]);

            synchronizers[i].updateSettlerWhitelisted(settlers[i], true);
            vm.label(address(synchronizers[i]), string.concat("Synchronizer", vm.toString(i)));
            vm.label(address(erc20s[i]), string.concat("xDERC20Wrapper", vm.toString(i)));
            vm.deal(settlers[i], 1000e18);
        }

        wireOApps(address[](oapps));
        wireOApps(address[](_erc20s));

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(address(erc20s[i]), 1000e18);
            changePrank(address(erc20s[i]), address(erc20s[i]));
            synchronizers[i].registerApp(false, false, settlers[i]);

            ISynchronizer.ChainConfig[] memory configs = new ISynchronizer.ChainConfig[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configs[count++] = ISynchronizer.ChainConfig(eids[j], 0);
                synchronizers[i].updateRemoteApp(eids[j], address(erc20s[j]));
            }

            changePrank(owner, owner);
            synchronizers[i].configChains(configs);
            for (uint256 j; j < users.length; ++j) {
                underlyings[i].mint(users[j], 100e18);
            }
        }

        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }
    }

    function test_queueUpdateTimeLockPeriod() public {
        xDERC20Wrapper local = erc20s[0];

        uint64 timestamp = uint64(vm.getBlockTimestamp());
        local.queueUpdateTimeLockPeriod(1 weeks);

        (BasexDERC20Wrapper.TimeLockType _type, bytes memory params, uint64 startedAt, bool executed) =
            local.timeLocks(0);
        assertEq(uint8(_type), uint8(BasexDERC20Wrapper.TimeLockType.UpdateTimeLockPeriod));
        assertEq(params, abi.encode(uint64(1 weeks)));
        assertEq(startedAt, timestamp);
        assertEq(executed, false);
    }

    function test_queueUpdateVault() public {
        xDERC20Wrapper local = erc20s[0];

        address vault = makeAddr("vault");
        uint64 timestamp = uint64(vm.getBlockTimestamp());
        local.queueUpdateVault(vault);

        (BasexDERC20Wrapper.TimeLockType _type, bytes memory params, uint64 startedAt, bool executed) =
            local.timeLocks(0);
        assertEq(uint8(_type), uint8(BasexDERC20Wrapper.TimeLockType.UpdateVault));
        assertEq(params, abi.encode(vault));
        assertEq(startedAt, timestamp);
        assertEq(executed, false);
    }

    function test_executeTimeLock() public {
        xDERC20Wrapper local = erc20s[0];

        local.queueUpdateTimeLockPeriod(1 weeks);

        vm.expectRevert(BasexDERC20Wrapper.TimeNotPassed.selector);
        local.executeTimeLock(0);

        skip(TIMELOCK_PERIOD);
        local.executeTimeLock(0);

        assertEq(local.timeLockPeriod(), 1 weeks);

        vm.expectRevert(BasexDERC20Wrapper.TimeLockExecuted.selector);
        local.executeTimeLock(0);

        address vault = makeAddr("vault");
        local.queueUpdateVault(vault);

        vm.expectRevert(BasexDERC20Wrapper.TimeNotPassed.selector);
        local.executeTimeLock(1);

        skip(1 weeks);
        local.executeTimeLock(1);

        assertEq(local.vault(), vault);

        vm.expectRevert(BasexDERC20Wrapper.TimeLockExecuted.selector);
        local.executeTimeLock(1);
    }
}
