// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Synchronizer } from "src/Synchronizer.sol";
import { ISynchronizer } from "src/interfaces/ISynchronizer.sol";
import { ArrayLib } from "src/libraries/ArrayLib.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "./mocks/AppMock.sol";
import { IAppMock } from "./mocks/IAppMock.sol";
import { BaseSynchronizerTest } from "./BaseSynchronizerTest.sol";

contract SynchronizerTest is BaseSynchronizerTest {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    uint8 public constant CHAINS = 16;

    uint32[CHAINS] eids;
    ISynchronizer[CHAINS] synchronizers;
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
            synchronizers[i] = new Synchronizer(DEFAULT_CHANNEL_ID, endpoints[eids[i]], owner);
            oapps[i] = address(synchronizers[i]);
            apps[i] = address(new AppMock(address(synchronizers[i])));
        }

        wireOApps(address[](oapps));

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(apps[i], 1000e18);
            changePrank(apps[i], apps[i]);
            synchronizers[i].registerApp(false, false);

            ISynchronizer.ChainConfig[] memory configs = new ISynchronizer.ChainConfig[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configs[count++] = ISynchronizer.ChainConfig(eids[j], 0);
                synchronizers[i].updateRemoteApp(eids[j], address(apps[j]));
            }

            changePrank(owner, owner);
            synchronizers[i].configChains(configs);
            initialize(storages[i]);
        }

        for (uint256 i; i < 100; ++i) {
            users.push(makeAddr(string.concat("account", vm.toString(i))));
        }

        vm.deal(users[0], 10_000e18);
        changePrank(users[0], users[0]);
    }

    function test_sync(bytes32 seed) public {
        ISynchronizer[] memory remotes = new ISynchronizer[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            _updateLocalLiquidity(synchronizers[i], apps[i], storages[i], users, seed);
            remotes[i - 1] = synchronizers[i];
            seed = keccak256(abi.encodePacked(seed, i));
        }
        _sync(synchronizers[0], remotes);
    }

    function test_requestMapRemoteAccounts() public {
        ISynchronizer[] memory remotes = new ISynchronizer[](CHAINS - 1);
        address[] memory remoteApps = new address[](CHAINS - 1);
        for (uint32 i = 1; i < CHAINS; ++i) {
            remotes[i - 1] = synchronizers[i];
            remoteApps[i - 1] = apps[i];
        }
        _requestMapRemoteAccounts(synchronizers[0], apps[0], remotes, remoteApps, users);
    }
}
