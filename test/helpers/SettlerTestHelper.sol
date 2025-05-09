// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { LibString } from "solmate/utils/LibString.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ArrayLib } from "src/libraries/ArrayLib.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { Test, console } from "forge-std/Test.sol";
import { AppMock } from "../mocks/AppMock.sol";
import { IAppMock } from "../mocks/IAppMock.sol";
import { LiquidityMatrixTestHelper } from "./LiquidityMatrixTestHelper.sol";

abstract contract SettlerTestHelper is LiquidityMatrixTestHelper {
    using MerkleTreeLib for MerkleTreeLib.Tree;

    uint32 constant TRAILING_MASK = uint32(0x80000000);
    uint32 constant INDEX_MASK = uint32(0x7fffffff);

    mapping(address => bool) accountUpdated;
    mapping(bytes32 => bool) keyUpdated;

    address owner = makeAddr("owner");
    address[] users;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        changePrank(owner, owner);
        local = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[EID_LOCAL], owner);
        remote = new LiquidityMatrix(DEFAULT_CHANNEL_ID, endpoints[EID_REMOTE], owner);
        localApp = address(new AppMock(address(local)));
        remoteApp = address(new AppMock(address(remote)));

        address[] memory oapps = new address[](2);
        oapps[0] = address(local);
        oapps[1] = address(remote);
        wireOApps(oapps);

        vm.deal(localApp, 10_000e18);
        vm.deal(remoteApp, 10_000e18);

        ILiquidityMatrix.ChainConfig[] memory configs = new ILiquidityMatrix.ChainConfig[](1);
        configs[0] = ILiquidityMatrix.ChainConfig(EID_REMOTE, 0);
        local.configChains(configs);
        configs[0] = ILiquidityMatrix.ChainConfig(EID_LOCAL, 0);
        remote.configChains(configs);

        initialize(localStorage);
        initialize(remoteStorage);

        for (uint256 i; i < 256; ++i) {
            users.push(makeAddr(string(abi.encodePacked("account", LibString.toString(i)))));
        }

        vm.deal(users[0], 10_000e18);
    }

    function _accountsData(uint256[] memory indices, address[] memory accounts)
        internal
        returns (bytes memory accountsData)
    {
        for (uint256 i; i < accounts.length; ++i) {
            address account = accounts[i];
            uint32 index = uint32(indices[i]);
            if (accountUpdated[account]) {
                accountsData = abi.encodePacked(accountsData, index);
            } else {
                accountsData = abi.encodePacked(accountsData, TRAILING_MASK | index & INDEX_MASK, accounts[i]);
            }
            accountUpdated[account] = true;
        }
    }

    function _keysData(uint256[] memory indices, bytes32[] memory keys) internal returns (bytes memory keysData) {
        for (uint256 i; i < keys.length; ++i) {
            bytes32 key = keys[i];
            uint32 index = uint32(indices[i]);
            if (keyUpdated[key]) {
                keysData = abi.encodePacked(keysData, index);
            } else {
                keysData = abi.encodePacked(keysData, TRAILING_MASK | index & INDEX_MASK, keys[i]);
            }
            keyUpdated[key] = true;
        }
    }
}
