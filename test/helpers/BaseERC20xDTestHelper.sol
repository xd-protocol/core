// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { Synchronizer } from "src/Synchronizer.sol";
import { ERC20xDGateway } from "src/gateways/ERC20xDGateway.sol";
import { BaseERC20xD } from "src/mixins/BaseERC20xD.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { IERC20xDGatewayCallbacks } from "src/interfaces/IERC20xDGatewayCallbacks.sol";
import { LiquidityMatrixTestHelper } from "./LiquidityMatrixTestHelper.sol";
import { SettlerMock } from "../mocks/SettlerMock.sol";

abstract contract BaseERC20xDTestHelper is LiquidityMatrixTestHelper {
    uint8 public constant CHAINS = 8;
    uint16 public constant CMD_TRANSFER = 1;
    uint128 public constant GAS_LIMIT = 500_000;

    uint32[CHAINS] eids;
    address[CHAINS] syncers;
    ILiquidityMatrix[CHAINS] liquidityMatrices;
    Synchronizer[CHAINS] synchronizers;
    ERC20xDGateway[CHAINS] gateways;
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
        for (uint32 i; i < CHAINS; ++i) {
            eids[i] = i + 1;
            syncers[i] = makeAddr(string.concat("syncer", vm.toString(i)));
            // Create LiquidityMatrix (only takes owner)
            liquidityMatrices[i] = new LiquidityMatrix(owner);
            _liquidityMatrices[i] = address(liquidityMatrices[i]);

            // Create Synchronizer with LayerZero integration
            synchronizers[i] = new Synchronizer(
                DEFAULT_CHANNEL_ID, endpoints[eids[i]], address(liquidityMatrices[i]), syncers[i], owner
            );

            // Set synchronizer in LiquidityMatrix
            liquidityMatrices[i].setSynchronizer(address(synchronizers[i]));

            // Create gateway with endpoint
            gateways[i] =
                new ERC20xDGateway(DEFAULT_CHANNEL_ID, endpoints[eids[i]], address(liquidityMatrices[i]), owner);
            _gateways[i] = address(gateways[i]);
            settlers[i] = address(new SettlerMock(address(liquidityMatrices[i])));
            erc20s[i] = _newBaseERC20xD(i);
            _erc20s[i] = address(erc20s[i]);

            liquidityMatrices[i].updateSettlerWhitelisted(settlers[i], true);

            vm.label(address(liquidityMatrices[i]), string.concat("LiquidityMatrix", vm.toString(i)));
            vm.label(address(gateways[i]), string.concat("Gateway", vm.toString(i)));
            vm.label(address(settlers[i]), string.concat("Settler", vm.toString(i)));
            vm.label(address(erc20s[i]), string.concat("ERC20xD", vm.toString(i)));

            vm.deal(settlers[i], 1000e18);
        }

        // Wire synchronizers (they have the OApp functionality)
        address[] memory _synchronizers = new address[](CHAINS);
        for (uint32 i; i < CHAINS; ++i) {
            _synchronizers[i] = address(synchronizers[i]);
        }
        wireOApps(_synchronizers);
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
            synchronizers[i].configChains(configEids, configConfirmations);

            // Register ERC20xD with gateway
            gateways[i].registerReader(address(erc20s[i]));
        }

        // Set read targets for ERC20xD contracts
        for (uint32 i; i < CHAINS; ++i) {
            for (uint32 j; j < CHAINS; ++j) {
                if (i != j) {
                    erc20s[i].updateReadTarget(bytes32(uint256(eids[j])), bytes32(uint256(uint160(address(erc20s[j])))));
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
    function _eid(ILiquidityMatrix liquidityMatrix) internal view override returns (uint32) {
        for (uint32 i = 0; i < CHAINS; ++i) {
            if (address(liquidityMatrix) == address(liquidityMatrices[i])) {
                return eids[i];
            }
        }
        revert("Unknown LiquidityMatrix");
    }

    function _eid(address addr) internal view override returns (uint32) {
        // For synchronizer addresses, check which endpoint they're associated with
        for (uint32 i = 0; i < CHAINS; ++i) {
            if (address(liquidityMatrices[i]) != address(0) && addr == address(synchronizers[i])) {
                return eids[i];
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

            (, uint256 rootTimestamp) = local.getLastReceivedLiquidityRoot(eids[i]);

            int256[] memory liquidity = new int256[](users.length);
            for (uint256 j; j < users.length; ++j) {
                liquidity[j] = remote.getLocalLiquidity(address(remoteApp), users[j]);
            }

            local.settleLiquidity(
                ILiquidityMatrix.SettleLiquidityParams(address(localApp), eids[i], rootTimestamp, users, liquidity)
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
        IERC20xDGatewayCallbacks.Request[] memory requests = new IERC20xDGatewayCallbacks.Request[](CHAINS - 1);
        bytes[] memory responses = new bytes[](CHAINS - 1);
        uint32 eid;
        address gateway;
        uint256 count;
        for (uint256 i; i < CHAINS; ++i) {
            if (readers[i] == reader) {
                eid = eids[i];
                gateway = address(gateways[i]);
                continue;
            }
            requests[count] = IERC20xDGatewayCallbacks.Request({
                chainIdentifier: bytes32(uint256(eids[i])),
                timestamp: uint64(block.timestamp),
                target: address(readers[i])
            });
            (, bytes memory response) = readers[i].call(callData);
            responses[count] = response;
            count++;
        }

        // Simulate the gateway calling reduce and then onRead
        bytes memory payload = IERC20xDGatewayCallbacks(reader).reduce(requests, callData, responses);

        if (error.length > 0) {
            vm.expectRevert(error);
        }
        this.verifyPackets(eid, addressToBytes32(address(gateway)), 0, address(0), payload);
    }
}
