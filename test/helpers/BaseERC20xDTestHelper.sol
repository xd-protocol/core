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
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { LiquidityMatrixTestHelper } from "./LiquidityMatrixTestHelper.sol";
import { SettlerMock } from "../mocks/SettlerMock.sol";

abstract contract BaseERC20xDTestHelper is LiquidityMatrixTestHelper {
    uint8 public constant CHAINS = 8;
    uint16 public constant CMD_XD_TRANSFER = 1;
    uint96 public constant GAS_LIMIT = 500_000;

    uint32[CHAINS] eids;
    ILiquidityMatrix[CHAINS] liquidityMatrices;
    address[CHAINS] settlers;
    BaseERC20xD[CHAINS] erc20s;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address[] users = [alice, bob, charlie];

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(CHAINS, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        address[] memory oapps = new address[](CHAINS);
        address[] memory _erc20s = new address[](CHAINS);
        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            liquidityMatrices[i] = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[eids[i]], owner);
            settlers[i] = address(new SettlerMock(address(liquidityMatrices[i])));
            oapps[i] = address(liquidityMatrices[i]);
            erc20s[i] = _newBaseERC20xD(i);
            _erc20s[i] = address(erc20s[i]);

            liquidityMatrices[i].updateSettlerWhitelisted(settlers[i], true);
            vm.label(address(liquidityMatrices[i]), string.concat("LiquidityMatrix", vm.toString(i)));
            vm.label(address(erc20s[i]), string.concat("ERC20xD", vm.toString(i)));
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
        }

        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }
    }

    function _newBaseERC20xD(uint256 index) internal virtual returns (BaseERC20xD);

    function _syncAndSettleLiquidity() internal {
        ILiquidityMatrix local = liquidityMatrices[0];
        address localSettler = settlers[0];
        BaseERC20xD localApp = erc20s[0];

        changePrank(localSettler, localSettler);
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint256 i; i < remotes.length; ++i) {
            remotes[i] = liquidityMatrices[i + 1];
        }
        _sync(local, remotes);

        for (uint256 i = 1; i < CHAINS; ++i) {
            ILiquidityMatrix remote = liquidityMatrices[i];
            BaseERC20xD remoteApp = erc20s[i];

            (, uint256 rootTimestamp) = local.getLastSyncedLiquidityRoot(eids[i]);

            int256[] memory liquidity = new int256[](users.length);
            for (uint256 j; j < users.length; ++j) {
                liquidity[j] = remote.getLocalLiquidity(address(remoteApp), users[j]);
            }

            local.settleLiquidity(
                ILiquidityMatrix.SettleLiquidityParams(address(localApp), eids[i], rootTimestamp, users, liquidity)
            );
        }
    }

    function _executeTransfer(BaseERC20xD erc20, address from, uint256 nonce, bytes memory error) internal {
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
        this.verifyPackets(eid, addressToBytes32(address(erc20)), 0, address(0), payload);
    }
}
