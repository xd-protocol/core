// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { Test, console } from "forge-std/Test.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { xDERC20 } from "src/xDERC20.sol";
import { BasexDERC20 } from "src/mixins/BasexDERC20.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";

contract BasexDERC20Test is TestHelperOz5 {
    uint8 public constant CHAINS = 16;
    uint16 public constant CMD_XD_TRANSFER = 1;

    uint32[CHAINS] eids;
    ILiquidityMatrix[CHAINS] liquidityMatrixs;
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
            liquidityMatrixs[i] = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[eids[i]], owner);
            oapps[i] = address(liquidityMatrixs[i]);
            erc20s[i] = new xDERC20("xD", "xD", 18, address(liquidityMatrixs[i]), owner);
            _erc20s[i] = address(erc20s[i]);
        }

        wireOApps(address[](oapps));
        wireOApps(address[](_erc20s));

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(address(erc20s[i]), 1000e18);
            changePrank(address(erc20s[i]), address(erc20s[i]));
            liquidityMatrixs[i].registerApp(false, false);

            ILiquidityMatrix.ChainConfig[] memory configs = new ILiquidityMatrix.ChainConfig[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configs[count++] = ILiquidityMatrix.ChainConfig(eids[j], 0);
                liquidityMatrixs[i].updateRemoteApp(eids[j], address(erc20s[j]));
            }

            changePrank(owner, owner);
            liquidityMatrixs[i].configChains(configs);
            for (uint256 j; j < users.length; ++j) {
                erc20s[i].mint(users[j], 100e18);
            }
        }

        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }
    }

    function test_updateXdTransferDelays() public {
        changePrank(owner, owner);
        uint32[] memory _eids = new uint32[](CHAINS - 1);
        uint64[] memory delays = new uint64[](CHAINS - 1);
        for (uint64 i = 1; i < CHAINS; ++i) {
            _eids[i - 1] = eids[i];
            delays[i - 1] = i;
        }
        erc20s[0].updateXdTransferDelays(_eids, delays);

        for (uint64 i = 1; i < CHAINS; ++i) {
            assertEq(erc20s[0].xdTransferDelay(eids[i]), i);
        }
    }

    function test_xdTransfer() public {
        xDERC20 local = erc20s[0];
        assertEq(local.localTotalSupply(), 300e18);
        assertEq(local.localBalanceOf(alice), 100e18);
        assertEq(local.localBalanceOf(bob), 100e18);

        changePrank(alice, alice);
        uint128 gasLimit = 1_000_000;
        uint32 calldataSize = uint32(32) * CHAINS;
        MessagingFee memory fee = local.quoteXdTransfer(bob, gasLimit, calldataSize);
        local.xdTransfer{ value: fee.nativeFee }(bob, 1e18, "", 0, gasLimit, calldataSize);

        uint256 nonce = 1;
        xDERC20.PendingTransfer memory pending = local.pendingTransfer(alice);
        assertEq(pending.pending, true);
        assertEq(pending.from, alice);
        assertEq(pending.to, bob);
        assertEq(pending.amount, 1e18);
        assertEq(pending.callData, "");
        assertEq(pending.value, 0);
        assertEq(local.pendingNonce(alice), nonce);

        bytes[] memory responses = new bytes[](CHAINS - 1);
        for (uint256 i; i < CHAINS - 1; ++i) {
            responses[i] = abi.encode(erc20s[i].availableLocalBalanceOf(alice, nonce));
        }
        bytes memory payload = local.lzReduce(local.getXdTransferCmd(alice, nonce), responses);
        verifyPackets(eids[0], bytes32(uint256(uint160(address(local)))), 0, address(0), payload);

        assertEq(local.localTotalSupply(), 300e18);
        assertEq(local.localBalanceOf(alice), 99e18);
        assertEq(local.localBalanceOf(bob), 101e18);
    }

    function test_cancelPendingTransfer() public {
        xDERC20 local = erc20s[0];

        changePrank(alice, alice);
        uint128 gasLimit = 1_000_000;
        uint32 calldataSize = uint32(32) * CHAINS;
        MessagingFee memory fee = local.quoteXdTransfer(bob, gasLimit, calldataSize);
        local.xdTransfer{ value: fee.nativeFee }(bob, 1e18, "", 0, gasLimit, calldataSize);

        uint256 nonce = 1;
        assertEq(local.pendingNonce(alice), nonce);

        local.cancelPendingTransfer();
        assertEq(local.pendingNonce(alice), 0);
    }
}
