// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ArrayLib } from "src/libraries/ArrayLib.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { BaseLiquidityMatrixTest } from "./BaseLiquidityMatrixTest.sol";

contract LiquidityMatrixTest is BaseLiquidityMatrixTest {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    uint8 public constant CHAINS = 16;

    uint32[CHAINS] eids;
    ILiquidityMatrix[CHAINS] liquidityMatrixs;
    address[CHAINS] apps;
    Storage[CHAINS] storages;

    address owner = makeAddr("owner");
    address[] users;

    function setUp() public override {
        super.setUp();
        setUpEndpoints(CHAINS, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        address[] memory oapps = new address[](CHAINS);
        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            liquidityMatrixs[i] = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[eids[i]], owner);
            oapps[i] = address(liquidityMatrixs[i]);
            apps[i] = address(new AppMock(address(liquidityMatrixs[i])));
        }

        wireOApps(address[](oapps));

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(apps[i], 1000e18);
            changePrank(apps[i], apps[i]);
            liquidityMatrixs[i].registerApp(false, false);

            ILiquidityMatrix.ChainConfig[] memory configs = new ILiquidityMatrix.ChainConfig[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configs[count++] = ILiquidityMatrix.ChainConfig(eids[j], 0, address(liquidityMatrixs[j]));
                liquidityMatrixs[i].updateRemoteApp(eids[j], address(apps[j]));
            }

            changePrank(owner, owner);
            liquidityMatrixs[i].configChains(configs);
            initialize(storages[i]);
        }

        for (uint256 i; i < 100; ++i) {
            users.push(makeAddr(string.concat("account", vm.toString(i))));
        }

        vm.deal(users[0], 10_000e18);
        changePrank(users[0], users[0]);
    }

    function test_sync(bytes32 seed) public {
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            _updateLocalLiquidity(liquidityMatrixs[i], apps[i], storages[i], users, seed);
            remotes[i - 1] = liquidityMatrixs[i];
            seed = keccak256(abi.encodePacked(seed, i));
        }
        _sync(liquidityMatrixs[0], remotes);
    }

    function test_requestMapRemoteAccounts() public {
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        address[] memory remoteApps = new address[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            remotes[i - 1] = liquidityMatrixs[i];
            remoteApps[i - 1] = apps[i];
        }
        _requestMapRemoteAccounts(liquidityMatrixs[0], apps[0], remotes, remoteApps, users);
    }
}
