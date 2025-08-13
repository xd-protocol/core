// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { LocalAppChronicleDeployer } from "src/chronicles/LocalAppChronicleDeployer.sol";
import { RemoteAppChronicleDeployer } from "src/chronicles/RemoteAppChronicleDeployer.sol";
import { RemoteAppChronicle } from "src/chronicles/RemoteAppChronicle.sol";
import { LayerZeroGateway } from "src/gateways/LayerZeroGateway.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ILocalAppChronicle } from "src/interfaces/ILocalAppChronicle.sol";
import { IGatewayApp } from "src/interfaces/IGatewayApp.sol";
import { MerkleTreeLib } from "src/libraries/MerkleTreeLib.sol";
import { LiquidityMatrixTestHelper } from "./LiquidityMatrixTestHelper.sol";
import { SettlerMock } from "../mocks/SettlerMock.sol";

abstract contract BaseERC20xDTestHelper is LiquidityMatrixTestHelper {
    uint8 public constant CHAINS = 8;
    uint16 public constant CMD_TRANSFER = 1;
    uint128 public constant GAS_LIMIT = 500_000;

    uint32[CHAINS] eids;
    address[CHAINS] syncers;
    ILiquidityMatrix[CHAINS] liquidityMatrices;
    LayerZeroGateway[CHAINS] gateways;
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
        address[] memory _liquidityMatrices = new address[](CHAINS);
        address[] memory _gateways = new address[](CHAINS);
        address[] memory _erc20s = new address[](CHAINS);
        // Deploy deployers for each chain (they need the LiquidityMatrix address)
        LocalAppChronicleDeployer[] memory localDeployers = new LocalAppChronicleDeployer[](CHAINS);
        RemoteAppChronicleDeployer[] memory remoteDeployers = new RemoteAppChronicleDeployer[](CHAINS);

        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            syncers[i] = makeAddr(string.concat("syncer", vm.toString(i)));

            // Create a dummy LiquidityMatrix first to get the address
            LiquidityMatrix tempMatrix = new LiquidityMatrix(owner, 1, address(0), address(0));

            // Create deployers with the LiquidityMatrix address
            localDeployers[i] = new LocalAppChronicleDeployer(address(tempMatrix));
            remoteDeployers[i] = new RemoteAppChronicleDeployer(address(tempMatrix));

            // Update the LiquidityMatrix with the correct deployer addresses
            tempMatrix.updateLocalAppChronicleDeployer(address(localDeployers[i]));
            tempMatrix.updateRemoteAppChronicleDeployer(address(remoteDeployers[i]));

            liquidityMatrices[i] = tempMatrix;
            _liquidityMatrices[i] = address(liquidityMatrices[i]);

            // Create gateway with endpoint first (needed by Synchronizer)
            gateways[i] =
                new LayerZeroGateway(DEFAULT_CHANNEL_ID, endpoints[eids[i]], address(liquidityMatrices[i]), owner);
            _gateways[i] = address(gateways[i]);

            // Set gateway and syncer in LiquidityMatrix
            liquidityMatrices[i].updateGateway(address(gateways[i]));
            liquidityMatrices[i].updateSyncer(syncers[i]);

            // Register LiquidityMatrix as an app with the gateway
            gateways[i].registerApp(address(liquidityMatrices[i]));

            settlers[i] = address(new SettlerMock(address(liquidityMatrices[i])));

            // Whitelist settler BEFORE creating ERC20xD (which calls registerApp in constructor)
            liquidityMatrices[i].updateSettlerWhitelisted(settlers[i], true);

            erc20s[i] = _newBaseERC20xD(i);
            _erc20s[i] = address(erc20s[i]);
            // gateways[i].registerApp(_erc20s[i]);

            vm.label(address(liquidityMatrices[i]), string.concat("LiquidityMatrix", vm.toString(i)));
            vm.label(address(gateways[i]), string.concat("Gateway", vm.toString(i)));
            vm.label(address(settlers[i]), string.concat("Settler", vm.toString(i)));
            vm.label(address(erc20s[i]), string.concat("ERC20xD", vm.toString(i)));

            vm.deal(settlers[i], 1000e18);
        }

        // Wire gateways (they have the OApp functionality)
        wireOApps(_gateways);

        for (uint32 i; i < CHAINS; ++i) {
            vm.deal(address(erc20s[i]), 1000e18);

            uint32[] memory configEids = new uint32[](CHAINS - 1);
            uint16[] memory configConfirmations = new uint16[](CHAINS - 1);
            uint32 count;
            for (uint32 j; j < CHAINS; ++j) {
                if (i == j) continue;
                configEids[count] = eids[j];
                configConfirmations[count] = 0;
                count++;
            }

            changePrank(owner, owner);
            bytes32[] memory chainUIDs = new bytes32[](configEids.length);
            for (uint256 k; k < configEids.length; k++) {
                chainUIDs[k] = bytes32(uint256(configEids[k]));
            }
            gateways[i].configChains(chainUIDs, configConfirmations);

            // Register ERC20xD with gateway
            gateways[i].registerApp(address(erc20s[i]));
        }

        // Set read targets for LiquidityMatrices (they need to read each other)
        for (uint32 i; i < CHAINS; ++i) {
            for (uint32 j; j < CHAINS; ++j) {
                if (i != j) {
                    liquidityMatrices[i].updateReadTarget(
                        bytes32(uint256(eids[j])), bytes32(uint256(uint160(address(liquidityMatrices[j]))))
                    );
                    erc20s[i].updateRemoteApp(bytes32(uint256(eids[j])), address(erc20s[j]), 0);
                }
            }
        }

        // Set read targets for ERC20xD contracts
        for (uint32 i; i < CHAINS; ++i) {
            for (uint32 j; j < CHAINS; ++j) {
                if (i != j) {
                    erc20s[i].updateReadTarget(bytes32(uint256(eids[j])), bytes32(uint256(uint160(address(erc20s[j])))));
                }
            }
        }

        // Create RemoteAppChronicles for cross-chain functionality
        for (uint32 i; i < CHAINS; ++i) {
            changePrank(settlers[i], settlers[i]);
            for (uint32 j; j < CHAINS; ++j) {
                if (i != j) {
                    // Create RemoteAppChronicle for each ERC20xD on each remote chain
                    liquidityMatrices[i].addRemoteAppChronicle(
                        address(erc20s[i]),
                        bytes32(uint256(eids[j])),
                        1 // Version 1 (initial version)
                    );
                }
            }
        }

        for (uint256 i; i < syncers.length; ++i) {
            vm.deal(syncers[i], 10_000e18);
        }
        for (uint256 i; i < users.length; ++i) {
            vm.deal(users[i], 10_000e18);
        }
    }

    function _newBaseERC20xD(uint256 index) internal virtual returns (BaseERC20xD);

    // Override _eid function to handle array-based structure
    function _eid(ILiquidityMatrix liquidityMatrix) internal view override returns (bytes32) {
        for (uint32 i = 0; i < CHAINS; ++i) {
            if (address(liquidityMatrix) == address(liquidityMatrices[i])) {
                return bytes32(uint256(eids[i]));
            }
        }
        revert("Unknown LiquidityMatrix");
    }

    function _eid(address addr) internal view override returns (bytes32) {
        // For gateway addresses, check which endpoint they're associated with
        for (uint32 i = 0; i < CHAINS; ++i) {
            if (address(liquidityMatrices[i]) != address(0) && addr == address(gateways[i])) {
                return bytes32(uint256(eids[i]));
            }
        }
        revert("Unknown address");
    }

    function _syncAndSettleLiquidity() internal {
        ILiquidityMatrix local = liquidityMatrices[0];
        address localSettler = settlers[0];
        BaseERC20xD localApp = erc20s[0];

        changePrank(localSettler, localSettler);
        ILiquidityMatrix[] memory remotes = new ILiquidityMatrix[](CHAINS - 1);
        for (uint256 i; i < remotes.length; ++i) {
            remotes[i] = liquidityMatrices[i + 1];
        }
        _sync(syncers[0], local, remotes);

        for (uint256 i = 1; i < CHAINS; ++i) {
            ILiquidityMatrix remote = liquidityMatrices[i];
            BaseERC20xD remoteApp = erc20s[i];

            (, uint256 rootTimestamp) = local.getLastReceivedRemoteLiquidityRoot(bytes32(uint256(eids[i])));

            int256[] memory liquidity = new int256[](users.length);
            for (uint256 j; j < users.length; ++j) {
                liquidity[j] = remote.getLocalLiquidity(address(remoteApp), users[j]);
            }
            // Settle liquidity with automatic proof generation
            _settleLiquidity(
                local, remote, address(localApp), bytes32(uint256(eids[i])), uint64(rootTimestamp), users, liquidity
            );
        }

        // Stop the prank to avoid conflicts in tests
        vm.stopPrank();
    }

    function _executeTransfer(BaseERC20xD erc20, address user, bytes memory error) internal {
        address[] memory readers = new address[](CHAINS);
        for (uint256 i; i < readers.length; ++i) {
            readers[i] = address(erc20s[i]);
        }
        _executeRead(
            address(erc20), readers, abi.encodeWithSelector(BaseERC20xD.availableLocalBalanceOf.selector, user), error
        );
    }

    function _executeRead(address reader, address[] memory readers, bytes memory callData, bytes memory error)
        internal
    {
        IGatewayApp.Request[] memory requests = new IGatewayApp.Request[](CHAINS - 1);
        bytes[] memory responses = new bytes[](CHAINS - 1);
        bytes32 chainUID;
        address gateway;
        uint256 count;
        for (uint256 i; i < CHAINS; ++i) {
            if (readers[i] == reader) {
                chainUID = bytes32(uint256(eids[i]));
                gateway = address(gateways[i]);
                continue;
            }
            requests[count] = IGatewayApp.Request({
                chainUID: bytes32(uint256(eids[i])),
                timestamp: uint64(block.timestamp),
                target: address(readers[i])
            });
            (, bytes memory response) = readers[i].call(callData);
            responses[count] = response;
            count++;
        }

        // Simulate the gateway calling reduce and then onRead
        bytes memory payload = IGatewayApp(reader).reduce(requests, callData, responses);

        if (error.length > 0) {
            vm.expectRevert(error);
        }
        this.verifyPackets(uint32(uint256(chainUID)), addressToBytes32(address(gateway)), 0, address(0), payload);
    }
}
