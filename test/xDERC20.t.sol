// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
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
import { BaseSynchronizerTest } from "./BaseSynchronizerTest.sol";

contract xDERC20Test is BaseSynchronizerTest {
    uint8 public constant CHAINS = 8;
    uint16 public constant CMD_XD_TRANSFER = 1;
    uint128 public constant GAS_LIMIT = 500_000;

    uint32[CHAINS] eids;
    ISynchronizer[CHAINS] synchronizers;
    address[CHAINS] settlers;
    xDERC20[CHAINS] erc20s;

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
        }

        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }

        changePrank(owner, owner);
    }

    function test_mint(bytes32 seed) public {
        uint256 total;
        for (uint256 i = 1; i < CHAINS; ++i) {
            uint256 amount = (uint256(seed) % 100) * 1e18;
            erc20s[i].mint(alice, amount);
            total += amount;
            seed = keccak256(abi.encodePacked(seed, i));
        }
        _syncAndSettleLiquidity();

        assertEq(erc20s[0].localBalanceOf(alice), 0);
        assertEq(erc20s[0].balanceOf(alice), total);
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

    function test_burn() public {
        erc20s[0].mint(alice, 100e18);
        assertEq(erc20s[0].localBalanceOf(alice), 100e18);
        assertEq(erc20s[0].balanceOf(alice), 100e18);

        changePrank(alice, alice);
        MessagingFee memory fee = erc20s[0].quoteTransfer(alice, GAS_LIMIT);
        erc20s[0].burn{ value: fee.nativeFee }(100e18, GAS_LIMIT);
        _executeTransfer(erc20s[0], alice, 1, "");

        assertEq(erc20s[0].localBalanceOf(alice), 0);
        assertEq(erc20s[0].balanceOf(alice), 0);
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
