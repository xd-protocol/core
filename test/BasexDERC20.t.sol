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
import { Synchronizer } from "src/Synchronizer.sol";
import { xDERC20 } from "src/xDERC20.sol";
import { BasexDERC20 } from "src/mixins/BasexDERC20.sol";
import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { LzLib } from "src/libraries/LzLib.sol";
import { BaseSynchronizerTest } from "./BaseSynchronizerTest.sol";

contract Composable {
    event Compose(address indexed token, uint256 amount);

    function compose(address token, uint256 amount) external payable {
        BasexDERC20(token).transferFrom(msg.sender, address(this), amount);

        emit Compose(token, amount);
    }
}

contract BasexDERC20Test is BaseSynchronizerTest {
    uint8 public constant CHAINS = 8;
    uint16 public constant CMD_XD_TRANSFER = 1;
    uint96 public constant GAS_LIMIT = 500_000;

    uint32[CHAINS] eids;
    ISynchronizer[CHAINS] synchronizers;
    address[CHAINS] settlers;
    xDERC20[CHAINS] erc20s;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address[] users = [alice, bob, charlie];
    Composable composable = new Composable();

    function setUp() public override {
        super.setUp();
        setUpEndpoints(CHAINS, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        address[] memory oapps = new address[](CHAINS);
        address[] memory _erc20s = new address[](CHAINS);
        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            synchronizers[i] = new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[eids[i]], owner);
            settlers[i] = address(new Settler(address(synchronizers[i])));
            oapps[i] = address(synchronizers[i]);
            erc20s[i] = new xDERC20("xD", "xD", 18, address(synchronizers[i]), owner);
            _erc20s[i] = address(erc20s[i]);

            synchronizers[i].updateSettlerWhitelisted(settlers[i], true);
            vm.label(address(synchronizers[i]), string.concat("Synchronizer", vm.toString(i)));
            vm.label(address(erc20s[i]), string.concat("xDERC20", vm.toString(i)));
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
                erc20s[i].mint(users[j], 100e18);
            }
        }

        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }
    }

    function test_updateTransferDelays() public {
        changePrank(owner, owner);
        uint32[] memory _eids = new uint32[](CHAINS - 1);
        uint64[] memory delays = new uint64[](CHAINS - 1);
        for (uint64 i = 1; i < CHAINS; ++i) {
            _eids[i - 1] = eids[i];
            delays[i - 1] = i;
        }
        erc20s[0].updateTransferDelays(_eids, delays);

        for (uint64 i = 1; i < CHAINS; ++i) {
            assertEq(erc20s[0].transferDelay(eids[i]), i);
        }
    }

    function test_transfer() public {
        xDERC20 local = erc20s[0];
        assertEq(local.localTotalSupply(), 300e18);
        assertEq(local.localBalanceOf(alice), 100e18);
        assertEq(local.localBalanceOf(bob), 100e18);

        _syncAndSettleLiquidity();
        assertEq(local.totalSupply(), CHAINS * 300e18);
        assertEq(local.balanceOf(alice), CHAINS * 100e18);
        assertEq(local.balanceOf(bob), CHAINS * 100e18);

        changePrank(alice, alice);
        uint256 amount = 101e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));

        uint256 nonce = 1;
        xDERC20.PendingTransfer memory pending = local.pendingTransfer(alice);
        assertEq(pending.pending, true);
        assertEq(pending.from, alice);
        assertEq(pending.to, bob);
        assertEq(pending.amount, amount);
        assertEq(pending.callData, "");
        assertEq(pending.value, 0);
        assertEq(local.pendingNonce(alice), nonce);
        assertEq(local.availableLocalBalanceOf(alice, 0), -1e18);

        _executeTransfer(local, alice, nonce, "");

        assertEq(local.localTotalSupply(), 300e18);
        assertEq(local.localBalanceOf(alice), -1e18);
        assertEq(local.localBalanceOf(bob), 201e18);

        assertEq(local.totalSupply(), CHAINS * 300e18);
        assertEq(local.balanceOf(alice), CHAINS * 100e18 - 101e18);
        assertEq(local.balanceOf(bob), CHAINS * 100e18 + 101e18);
    }

    function test_transfer_composable() public {
        xDERC20 local = erc20s[0];

        changePrank(alice, alice);
        uint256 amount = 100e18;
        bytes memory callData = abi.encodeWithSelector(Composable.compose.selector, local, amount);
        uint256 native = 1e18;
        uint96 gasLimit = 1_000_000;
        uint256 fee = local.quoteTransfer(bob, gasLimit);
        local.transfer{ value: fee + native }(
            address(composable), amount, callData, native, LzLib.encodeOptions(gasLimit, address(composable))
        );

        vm.expectEmit();
        emit Composable.Compose(address(local), amount);
        _executeTransfer(local, alice, 1, "");

        assertEq(local.balanceOf(address(composable)), amount);
        assertEq(address(composable).balance, native);
    }

    function test_transfer_revertInsufficientBalance() public {
        xDERC20 local = erc20s[0];

        assertEq(local.balanceOf(alice), 100e18);

        changePrank(alice, alice);
        uint256 amount = 101e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        vm.expectRevert(BasexDERC20.InsufficientBalance.selector);
        local.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));

        _syncAndSettleLiquidity();
        assertEq(local.balanceOf(alice), 100e18 * CHAINS);

        changePrank(alice, alice);
        local.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));
    }

    function test_transfer_revertTransferPending() public {
        xDERC20 local = erc20s[0];

        assertEq(local.balanceOf(alice), 100e18);

        changePrank(alice, alice);
        uint256 amount = 1e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));

        vm.expectRevert(BasexDERC20.TransferPending.selector);
        local.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));
    }

    function test_transfer_revertInsufficientAvailability() public {
        xDERC20 local = erc20s[0];
        xDERC20 remote = erc20s[1];

        _syncAndSettleLiquidity();
        assertEq(local.localBalanceOf(alice), 100e18);
        assertEq(local.balanceOf(alice), CHAINS * 100e18);

        changePrank(alice, alice);
        uint256 amount = CHAINS * 100e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));

        _executeTransfer(local, alice, 1, "");
        assertEq(local.localBalanceOf(alice), -(int256(int8(CHAINS) - 1)) * 100e18);
        assertEq(local.balanceOf(alice), 0);

        // on the remote chain, sync didn't happen yet
        assertEq(remote.localBalanceOf(alice), 100e18);
        assertEq(remote.balanceOf(alice), 100e18);

        amount = 100e18;
        fee = remote.quoteTransfer(bob, GAS_LIMIT);
        remote.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));
        assertEq(remote.availableLocalBalanceOf(alice, 0), 0);

        uint256 nonce = 1;
        int256 availability = 0;
        bytes memory error =
            abi.encodeWithSelector(BasexDERC20.InsufficientAvailability.selector, nonce, amount, availability);
        _executeTransfer(remote, alice, nonce, error);
    }

    function test_cancelPendingTransfer() public {
        xDERC20 local = erc20s[0];

        _syncAndSettleLiquidity();

        changePrank(alice, alice);
        uint256 amount = 101e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));

        uint256 nonce = 1;
        assertEq(local.pendingNonce(alice), nonce);
        assertEq(local.availableLocalBalanceOf(alice, 0), -1e18);

        local.cancelPendingTransfer();
        assertEq(local.pendingNonce(alice), 0);
        assertEq(local.availableLocalBalanceOf(alice, 0), 100e18);
    }

    function test_cancelPendingTransfer_revertTransferNotPending() public {
        xDERC20 local = erc20s[0];

        changePrank(alice, alice);
        vm.expectRevert(abi.encodeWithSelector(BasexDERC20.TransferNotPending.selector, 0));
        local.cancelPendingTransfer();

        uint256 amount = 1e18;
        uint256 fee = local.quoteTransfer(bob, GAS_LIMIT);
        local.transfer{ value: fee }(bob, amount, LzLib.encodeOptions(GAS_LIMIT, bob));

        local.cancelPendingTransfer();
        assertEq(local.pendingNonce(alice), 0);
    }

    function _syncAndSettleLiquidity() internal {
        ISynchronizer local = synchronizers[0];
        address localSettler = settlers[0];
        xDERC20 localApp = erc20s[0];

        changePrank(localSettler, localSettler);
        ISynchronizer[] memory remotes = new ISynchronizer[](CHAINS - 1);
        for (uint256 i; i < remotes.length; ++i) {
            remotes[i] = synchronizers[i + 1];
        }
        _sync(local, remotes);

        for (uint256 i = 1; i < CHAINS; ++i) {
            ISynchronizer remote = synchronizers[i];
            xDERC20 remoteApp = erc20s[i];

            (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(eids[i]);

            int256[] memory liquidity = new int256[](users.length);
            for (uint256 j; j < users.length; ++j) {
                liquidity[j] = remote.getLocalLiquidity(address(remoteApp), users[j]);
            }

            local.settleLiquidity(
                ISynchronizer.SettleLiquidityParams(address(localApp), eids[i], rootTimestamp, users, liquidity)
            );
        }
    }

    function _executeTransfer(xDERC20 erc20, address from, uint256 nonce, bytes memory error) internal {
        bytes[] memory responses = new bytes[](CHAINS - 1);
        uint32 eid;
        uint256 count;
        for (uint256 i; i < CHAINS; ++i) {
            if (erc20s[i] == erc20) {
                eid = eids[i];
                continue;
            }
            responses[count++] = abi.encode(erc20s[i].availableLocalBalanceOf(from, nonce));
        }
        bytes memory payload = erc20.lzReduce(erc20.getTransferCmd(from, nonce), responses);
        if (error.length > 0) {
            vm.expectRevert(error);
        }
        this.verifyPackets(eid, bytes32(uint256(uint160(address(erc20)))), 0, address(0), payload);
    }
}
