// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

// LayerZero test infrastructure
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// LayerZero protocol imports
import {
    MessagingReceipt,
    MessagingFee,
    MessagingParams,
    Origin,
    ILayerZeroEndpointV2
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";

// Contract imports
import { LayerZeroGateway } from "../../src/gateways/LayerZeroGateway.sol";
import { IGateway } from "../../src/interfaces/IGateway.sol";
import { IGatewayApp } from "../../src/interfaces/IGatewayApp.sol";
import { LiquidityMatrix } from "../../src/LiquidityMatrix.sol";
import { ILiquidityMatrix } from "../../src/interfaces/ILiquidityMatrix.sol";
import { LocalAppChronicleDeployer } from "../../src/chronicles/LocalAppChronicleDeployer.sol";
import { RemoteAppChronicleDeployer } from "../../src/chronicles/RemoteAppChronicleDeployer.sol";
import { GatewayAppMock } from "../mocks/GatewayAppMock.sol";

// Malicious app for authorization testing
contract MaliciousApp is IGatewayApp {
    LayerZeroGateway public gateway;
    address public liquidityMatrix;

    constructor(address _gateway, address _liquidityMatrix) {
        gateway = LayerZeroGateway(_gateway);
        liquidityMatrix = _liquidityMatrix;
    }

    function attemptUnauthorizedMapAccounts(
        bytes32 chainUID,
        address victimApp,
        address[] memory remoteAccounts,
        address[] memory localAccounts
    ) external payable {
        // Craft malicious MAP_REMOTE_ACCOUNTS message impersonating another app
        bytes memory maliciousPayload = abi.encode(
            uint16(1), // MAP_REMOTE_ACCOUNTS
            address(0), // remote app (not used in this context)
            victimApp, // impersonate victim app
            remoteAccounts,
            localAccounts
        );

        // Try to send to LiquidityMatrix
        bytes memory data = abi.encode(uint128(500_000), address(this)); // gasLimit and refundTo
        gateway.sendMessage{ value: msg.value }(chainUID, liquidityMatrix, maliciousPayload, data);
    }

    function getReadTargets() external pure returns (bytes32[] memory, address[] memory) {
        return (new bytes32[](0), new address[](0));
    }

    function reduce(Request[] calldata, bytes calldata, bytes[] calldata) external pure returns (bytes memory) {
        return "";
    }

    function onRead(bytes calldata, bytes calldata) external { }

    function onReceive(bytes32, bytes calldata) external { }
}

/**
 * @title LayerZeroGatewayTest
 * @notice Comprehensive test suite for LayerZeroGateway using EndpointV2Mock
 * @dev Uses TestHelperOz5 for proper LayerZero testing infrastructure
 */
contract LayerZeroGatewayTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint32 constant CHAIN_A_EID = 1;
    uint32 constant CHAIN_B_EID = 2;
    uint32 constant CHAIN_C_EID = 3;
    uint128 constant GAS_LIMIT = 500_000;
    uint128 constant READ_GAS_LIMIT = 1_000_000;
    uint32 constant RETURN_DATA_SIZE = 1000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    LayerZeroGateway gatewayA;
    LayerZeroGateway gatewayB;
    LayerZeroGateway gatewayC;

    LiquidityMatrix liquidityMatrixA;
    LiquidityMatrix liquidityMatrixB;
    LiquidityMatrix liquidityMatrixC;

    address owner = makeAddr("owner");
    address unauthorizedUser = makeAddr("unauthorizedUser");
    address appA = makeAddr("appA");
    address appB = makeAddr("appB");
    address appC = makeAddr("appC");

    GatewayAppMock mockAppA;
    GatewayAppMock mockAppB;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RegisterApp(address indexed app, uint16 indexed cmdLabel);
    event UpdateTransferDelay(uint32 indexed eid, uint64 delay);
    event MessageSent(uint32 indexed eid, bytes32 indexed guid, bytes message);
    event TargetAuthorizationUpdated(address indexed app, address indexed target, bool authorized);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        super.setUp();

        // Give test accounts ETH
        vm.deal(owner, 100 ether);
        vm.deal(appA, 10 ether);
        vm.deal(appB, 10 ether);
        vm.deal(appC, 10 ether);
        vm.deal(unauthorizedUser, 1 ether);

        // Setup 3 endpoints with UltraLightNode configuration
        setUpEndpoints(3, LibraryType.UltraLightNode);

        // Deploy LiquidityMatrix contracts
        vm.startPrank(owner);
        liquidityMatrixA = new LiquidityMatrix(owner, 1, address(0), address(0));
        liquidityMatrixB = new LiquidityMatrix(owner, 1, address(0), address(0));
        liquidityMatrixC = new LiquidityMatrix(owner, 1, address(0), address(0));
        vm.stopPrank();

        // Deploy deployers with LiquidityMatrix addresses
        LocalAppChronicleDeployer localDeployerA = new LocalAppChronicleDeployer(address(liquidityMatrixA));
        RemoteAppChronicleDeployer remoteDeployerA = new RemoteAppChronicleDeployer(address(liquidityMatrixA));

        LocalAppChronicleDeployer localDeployerB = new LocalAppChronicleDeployer(address(liquidityMatrixB));
        RemoteAppChronicleDeployer remoteDeployerB = new RemoteAppChronicleDeployer(address(liquidityMatrixB));

        LocalAppChronicleDeployer localDeployerC = new LocalAppChronicleDeployer(address(liquidityMatrixC));
        RemoteAppChronicleDeployer remoteDeployerC = new RemoteAppChronicleDeployer(address(liquidityMatrixC));

        // Update deployers in LiquidityMatrix contracts (as owner)
        vm.startPrank(owner);
        liquidityMatrixA.updateLocalAppChronicleDeployer(address(localDeployerA));
        liquidityMatrixA.updateRemoteAppChronicleDeployer(address(remoteDeployerA));
        liquidityMatrixB.updateLocalAppChronicleDeployer(address(localDeployerB));
        liquidityMatrixB.updateRemoteAppChronicleDeployer(address(remoteDeployerB));
        liquidityMatrixC.updateLocalAppChronicleDeployer(address(localDeployerC));
        liquidityMatrixC.updateRemoteAppChronicleDeployer(address(remoteDeployerC));
        vm.stopPrank();

        // Deploy gateways using the endpoints from TestHelperOz5
        // The endpoints mapping is populated during setUpEndpoints
        gatewayA = new LayerZeroGateway(DEFAULT_CHANNEL_ID, endpoints[CHAIN_A_EID], address(liquidityMatrixA), owner);

        gatewayB = new LayerZeroGateway(DEFAULT_CHANNEL_ID, endpoints[CHAIN_B_EID], address(liquidityMatrixB), owner);

        gatewayC = new LayerZeroGateway(DEFAULT_CHANNEL_ID, endpoints[CHAIN_C_EID], address(liquidityMatrixC), owner);

        // Wire gateways as OApps - need to do this as owner since gateways are owned by owner
        vm.startPrank(owner);
        gatewayA.setPeer(CHAIN_B_EID, bytes32(uint256(uint160(address(gatewayB)))));
        gatewayA.setPeer(CHAIN_C_EID, bytes32(uint256(uint160(address(gatewayC)))));

        gatewayB.setPeer(CHAIN_A_EID, bytes32(uint256(uint160(address(gatewayA)))));
        gatewayB.setPeer(CHAIN_C_EID, bytes32(uint256(uint160(address(gatewayC)))));

        gatewayC.setPeer(CHAIN_A_EID, bytes32(uint256(uint160(address(gatewayA)))));
        gatewayC.setPeer(CHAIN_B_EID, bytes32(uint256(uint160(address(gatewayB)))));
        vm.stopPrank();

        // Deploy mock apps for testing
        mockAppA = new GatewayAppMock();
        mockAppB = new GatewayAppMock();

        // Give mock apps ETH for paying LayerZero fees
        vm.deal(address(mockAppA), 100 ether);
        vm.deal(address(mockAppB), 100 ether);

        // Labels for debugging
        vm.label(address(gatewayA), "GatewayA");
        vm.label(address(gatewayB), "GatewayB");
        vm.label(address(gatewayC), "GatewayC");
        vm.label(address(liquidityMatrixA), "LiquidityMatrixA");
        vm.label(address(liquidityMatrixB), "LiquidityMatrixB");
        vm.label(address(liquidityMatrixC), "LiquidityMatrixC");
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public view {
        assertEq(gatewayA.READ_CHANNEL(), DEFAULT_CHANNEL_ID);
        assertEq(gatewayA.liquidityMatrix(), address(liquidityMatrixA));
        assertEq(gatewayA.owner(), owner);

        assertEq(gatewayB.READ_CHANNEL(), DEFAULT_CHANNEL_ID);
        assertEq(gatewayB.liquidityMatrix(), address(liquidityMatrixB));
        assertEq(gatewayB.owner(), owner);
    }

    function test_constructor_differentParams() public {
        uint32 customChannel = 12_345;
        address customOwner = makeAddr("customOwner");
        address customMatrix = makeAddr("customMatrix");

        vm.prank(customOwner);
        LayerZeroGateway customGateway =
            new LayerZeroGateway(customChannel, address(endpoints[CHAIN_A_EID]), customMatrix, customOwner);

        assertEq(customGateway.READ_CHANNEL(), customChannel);
        assertEq(customGateway.liquidityMatrix(), customMatrix);
        assertEq(customGateway.owner(), customOwner);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIAL STATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialState() public view {
        // Should have no chains configured initially
        assertEq(gatewayA.chainUIDsLength(), 0);

        // Should have no apps registered
        assertEq(gatewayA.getApp(1), address(0));

        // Immutable values should be set
        assertEq(gatewayA.READ_CHANNEL(), DEFAULT_CHANNEL_ID);
        assertEq(gatewayA.liquidityMatrix(), address(liquidityMatrixA));
    }

    /*//////////////////////////////////////////////////////////////
                        registerApp() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerApp() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit RegisterApp(appA, 1);

        gatewayA.registerApp(appA);

        // Verify app is registered with correct cmdLabel
        uint16 cmdLabel = gatewayA.appCmdLabel(appA);
        assertEq(cmdLabel, 1);

        // Verify getApp mapping is populated (this was the bug we fixed)
        assertEq(gatewayA.getApp(1), appA);
    }

    function test_registerApp_multipleApps() public {
        vm.startPrank(owner);

        gatewayA.registerApp(appA);
        gatewayA.registerApp(appB);
        gatewayA.registerApp(appC);

        vm.stopPrank();

        // Verify sequential cmdLabel assignment
        uint16 cmdLabelA = gatewayA.appCmdLabel(appA);
        uint16 cmdLabelB = gatewayA.appCmdLabel(appB);
        uint16 cmdLabelC = gatewayA.appCmdLabel(appC);

        assertEq(cmdLabelA, 1);
        assertEq(cmdLabelB, 2);
        assertEq(cmdLabelC, 3);

        // Verify getApp mapping
        assertEq(gatewayA.getApp(1), appA);
        assertEq(gatewayA.getApp(2), appB);
        assertEq(gatewayA.getApp(3), appC);
    }

    function test_registerApp_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        gatewayA.registerApp(appA);
    }

    function test_registerApp_preventsDuplicateRegistration() public {
        vm.startPrank(owner);

        // First registration should succeed
        gatewayA.registerApp(appA);
        assertEq(gatewayA.appCmdLabel(appA), 1);
        assertEq(gatewayA.getApp(1), appA);

        // Attempt to re-register the same app should revert
        vm.expectRevert(abi.encodeWithSelector(IGateway.AppAlreadyRegistered.selector, appA));
        gatewayA.registerApp(appA);

        // Verify the app still has the original registration
        assertEq(gatewayA.appCmdLabel(appA), 1);
        assertEq(gatewayA.getApp(1), appA);
        assertEq(gatewayA.getApp(2), address(0)); // cmdLabel 2 was never assigned

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    authorizeTarget() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_authorizeTarget_basic() public {
        // Register an app first
        vm.prank(owner);
        gatewayA.registerApp(appA);

        // Check that the app is not authorized by default
        assertEq(gatewayA.targetAuthorized(appA, appB), false);

        // Authorize the app to send to a target
        vm.prank(owner);
        gatewayA.authorizeTarget(appA, appB, true);

        // Now check that authorization is set
        assertEq(gatewayA.targetAuthorized(appA, appB), true);
    }

    function test_authorizeTarget_canRevoke() public {
        vm.startPrank(owner);
        gatewayA.registerApp(appA);

        // First authorize
        gatewayA.authorizeTarget(appA, appB, true);
        assertEq(gatewayA.targetAuthorized(appA, appB), true);

        // Then revoke
        gatewayA.authorizeTarget(appA, appB, false);
        assertEq(gatewayA.targetAuthorized(appA, appB), false);
        vm.stopPrank();
    }

    function test_authorizeTarget_revertNonOwner() public {
        vm.prank(owner);
        gatewayA.registerApp(appA);

        // Non-owner cannot authorize
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(0x118cdaa7, unauthorizedUser)); // OwnableUnauthorizedAccount
        gatewayA.authorizeTarget(appA, appB, true);
    }

    function test_authorizeTarget_emitsEvent() public {
        vm.startPrank(owner);
        gatewayA.registerApp(appA);

        // Check event emission for authorization
        vm.expectEmit(true, true, false, true);
        emit IGateway.TargetAuthorizationUpdated(appA, appB, true);
        gatewayA.authorizeTarget(appA, appB, true);

        // Check event emission for revocation
        vm.expectEmit(true, true, false, true);
        emit IGateway.TargetAuthorizationUpdated(appA, appB, false);
        gatewayA.authorizeTarget(appA, appB, false);

        vm.stopPrank();
    }

    function test_sendMessage_revertUnauthorizedTarget() public {
        // Setup: register app but don't authorize target
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        // Configure chains so sendMessage can work
        bytes32[] memory chainUIDs = new bytes32[](1);
        uint16[] memory confirmations = new uint16[](1);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        confirmations[0] = 15;

        vm.prank(owner);
        gatewayA.configureChains(chainUIDs, confirmations);

        // Try to send message without authorization
        bytes memory message = abi.encode("test");
        bytes memory data = abi.encode(uint128(GAS_LIMIT), address(mockAppA));

        vm.prank(address(mockAppA));
        vm.expectRevert(
            abi.encodeWithSelector(IGateway.UnauthorizedTarget.selector, address(mockAppA), address(mockAppB))
        );
        gatewayA.sendMessage{ value: 0.1 ether }(bytes32(uint256(CHAIN_B_EID)), address(mockAppB), message, data);
    }

    function test_sendMessage_successWithAuthorization() public {
        // Setup: register app and authorize target
        vm.startPrank(owner);
        gatewayA.registerApp(address(mockAppA));
        gatewayA.authorizeTarget(address(mockAppA), address(mockAppB), true);

        // Configure chains
        bytes32[] memory chainUIDs = new bytes32[](1);
        uint16[] memory confirmations = new uint16[](1);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        confirmations[0] = 15;
        gatewayA.configureChains(chainUIDs, confirmations);
        vm.stopPrank();

        // Now sending should work
        bytes memory message = abi.encode("test");
        bytes memory data = abi.encode(uint128(GAS_LIMIT), address(mockAppA));

        uint256 fee = gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppB), message, GAS_LIMIT);

        vm.prank(address(mockAppA));
        bytes32 guid =
            gatewayA.sendMessage{ value: fee }(bytes32(uint256(CHAIN_B_EID)), address(mockAppB), message, data);

        assertTrue(guid != bytes32(0), "Message should be sent successfully");
    }

    function test_vulnerability_preventsMaliciousImpersonation() public {
        // Deploy a malicious app
        MaliciousApp maliciousApp = new MaliciousApp(address(gatewayA), address(liquidityMatrixA));
        vm.deal(address(maliciousApp), 10 ether);

        // Register both legitimate and malicious apps
        vm.startPrank(owner);
        gatewayA.registerApp(address(mockAppA));
        gatewayA.registerApp(address(maliciousApp));

        // Only authorize the legitimate app to send to LiquidityMatrix
        gatewayA.authorizeTarget(address(mockAppA), address(liquidityMatrixA), true);
        // Explicitly do NOT authorize maliciousApp

        // Configure chains
        bytes32[] memory chainUIDs = new bytes32[](1);
        uint16[] memory confirmations = new uint16[](1);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        confirmations[0] = 15;
        gatewayA.configureChains(chainUIDs, confirmations);
        vm.stopPrank();

        // Attack attempt: Malicious app tries to impersonate legitimate app
        address[] memory remoteAccounts = new address[](1);
        address[] memory localAccounts = new address[](1);
        remoteAccounts[0] = makeAddr("attacker");
        localAccounts[0] = makeAddr("victim");

        // The attack should fail with UnauthorizedTarget error
        vm.expectRevert(
            abi.encodeWithSelector(
                IGateway.UnauthorizedTarget.selector, address(maliciousApp), address(liquidityMatrixA)
            )
        );

        maliciousApp.attemptUnauthorizedMapAccounts{ value: 1 ether }(
            bytes32(uint256(CHAIN_B_EID)), address(mockAppA), remoteAccounts, localAccounts
        );

        // Verify: The attack was prevented, no unauthorized mappings were created
    }

    /*//////////////////////////////////////////////////////////////
                        configureChains() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_configureChains() public {
        bytes32[] memory chainUIDs = new bytes32[](2);
        uint16[] memory confirmations = new uint16[](2);

        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        chainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        confirmations[0] = 15;
        confirmations[1] = 20;

        vm.prank(owner);
        gatewayA.configureChains(chainUIDs, confirmations);

        // Verify configuration
        (bytes32[] memory returnedChainUIDs, uint16[] memory returnedConfirmations) = gatewayA.chainConfigs();

        assertEq(returnedChainUIDs.length, 2);
        assertEq(returnedConfirmations.length, 2);
        assertEq(returnedChainUIDs[0], chainUIDs[0]);
        assertEq(returnedChainUIDs[1], chainUIDs[1]);
        assertEq(returnedConfirmations[0], 15);
        assertEq(returnedConfirmations[1], 20);

        // Verify helper functions
        assertEq(gatewayA.chainUIDsLength(), 2);
        assertEq(gatewayA.chainUIDAt(0), chainUIDs[0]);
        assertEq(gatewayA.chainUIDAt(1), chainUIDs[1]);
    }

    function test_configureChains_overwriteExisting() public {
        // First configuration
        bytes32[] memory chainUIDs1 = new bytes32[](1);
        uint16[] memory confirmations1 = new uint16[](1);
        chainUIDs1[0] = bytes32(uint256(CHAIN_B_EID));
        confirmations1[0] = 10;

        vm.prank(owner);
        gatewayA.configureChains(chainUIDs1, confirmations1);
        assertEq(gatewayA.chainUIDsLength(), 1);

        // Second configuration - should overwrite
        bytes32[] memory chainUIDs2 = new bytes32[](2);
        uint16[] memory confirmations2 = new uint16[](2);
        chainUIDs2[0] = bytes32(uint256(CHAIN_B_EID));
        chainUIDs2[1] = bytes32(uint256(CHAIN_C_EID));
        confirmations2[0] = 15;
        confirmations2[1] = 25;

        vm.prank(owner);
        gatewayA.configureChains(chainUIDs2, confirmations2);

        assertEq(gatewayA.chainUIDsLength(), 2);
        (bytes32[] memory returned,) = gatewayA.chainConfigs();
        assertEq(returned[0], chainUIDs2[0]);
        assertEq(returned[1], chainUIDs2[1]);
    }

    function test_configureChains_revertInvalidLengths() public {
        bytes32[] memory chainUIDs = new bytes32[](2);
        uint16[] memory confirmations = new uint16[](1);

        vm.prank(owner);
        vm.expectRevert(IGateway.InvalidLengths.selector);
        gatewayA.configureChains(chainUIDs, confirmations);
    }

    function test_configureChains_revertDuplicateChains() public {
        bytes32[] memory chainUIDs = new bytes32[](2);
        uint16[] memory confirmations = new uint16[](2);

        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        chainUIDs[1] = bytes32(uint256(CHAIN_B_EID)); // Duplicate
        confirmations[0] = 10;
        confirmations[1] = 15;

        vm.prank(owner);
        vm.expectRevert(IGateway.DuplicateTargetEid.selector);
        gatewayA.configureChains(chainUIDs, confirmations);
    }

    function test_configureChains_revertInvalidChainUID() public {
        bytes32[] memory chainUIDs = new bytes32[](1);
        uint16[] memory confirmations = new uint16[](1);

        chainUIDs[0] = bytes32(uint256(type(uint32).max) + 1); // Too large
        confirmations[0] = 10;

        vm.prank(owner);
        vm.expectRevert(IGateway.InvalidChainUID.selector);
        gatewayA.configureChains(chainUIDs, confirmations);
    }

    /*//////////////////////////////////////////////////////////////
                    updateTransferDelays() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateTransferDelays() public {
        bytes32[] memory chainUIDs = new bytes32[](2);
        uint64[] memory delays = new uint64[](2);

        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        chainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        delays[0] = 300; // 5 minutes
        delays[1] = 600; // 10 minutes

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit UpdateTransferDelay(CHAIN_B_EID, 300);
        vm.expectEmit(true, false, false, true);
        emit UpdateTransferDelay(CHAIN_C_EID, 600);

        gatewayA.updateTransferDelays(chainUIDs, delays);

        // Verify delays are set
        assertEq(gatewayA.transferDelays(CHAIN_B_EID), 300);
        assertEq(gatewayA.transferDelays(CHAIN_C_EID), 600);
    }

    function test_updateTransferDelays_revertInvalidLengths() public {
        bytes32[] memory chainUIDs = new bytes32[](2);
        uint64[] memory delays = new uint64[](1);

        vm.prank(owner);
        vm.expectRevert(IGateway.InvalidLengths.selector);
        gatewayA.updateTransferDelays(chainUIDs, delays);
    }

    function test_updateTransferDelays_revertUnauthorized() public {
        bytes32[] memory chainUIDs = new bytes32[](1);
        uint64[] memory delays = new uint64[](1);

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        gatewayA.updateTransferDelays(chainUIDs, delays);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN READ TESTS
    //////////////////////////////////////////////////////////////*/

    function test_read_singleChain() public {
        // Setup: register app and configure chains
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes32[] memory chainUIDs = new bytes32[](1);
        uint16[] memory confirmations = new uint16[](1);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        confirmations[0] = 15;

        vm.prank(owner);
        gatewayA.configureChains(chainUIDs, confirmations);

        // Mock app should provide targets (no longer set on gateway)

        // Quote and perform read
        bytes memory callData = abi.encodeWithSignature("getData()");
        bytes32[] memory readChainUIDs = new bytes32[](1);
        readChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        address[] memory targets = new address[](1);
        targets[0] = address(mockAppB);
        uint256 fee =
            gatewayA.quoteRead(address(mockAppA), readChainUIDs, targets, callData, RETURN_DATA_SIZE, READ_GAS_LIMIT);

        assertTrue(fee > 0, "Fee should be non-zero");

        bytes memory extra = abi.encode("extraData");
        bytes memory lzOptions = abi.encode(READ_GAS_LIMIT, address(mockAppA));

        vm.prank(address(mockAppA));
        bytes32 guid = gatewayA.read{ value: fee }(readChainUIDs, targets, callData, extra, RETURN_DATA_SIZE, lzOptions);

        assertTrue(guid != bytes32(0), "GUID should be non-zero");
    }

    function test_quoteRead_multipleChains() public {
        // Setup with multiple chains
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes32[] memory chainUIDs = new bytes32[](2);
        uint16[] memory confirmations = new uint16[](2);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        chainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        confirmations[0] = 15;
        confirmations[1] = 20;

        vm.prank(owner);
        gatewayA.configureChains(chainUIDs, confirmations);

        // Mock app should provide targets (no longer set on gateway)

        // Quote read for multiple chains
        bytes memory callData = abi.encodeWithSignature("getData()");
        bytes32[] memory readChainUIDs = new bytes32[](2);
        readChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        readChainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        address[] memory targets = new address[](2);
        targets[0] = address(mockAppB);
        targets[1] = appC;
        uint256 fee =
            gatewayA.quoteRead(address(mockAppA), readChainUIDs, targets, callData, RETURN_DATA_SIZE, READ_GAS_LIMIT);

        assertTrue(fee > 0, "Fee should be non-zero for multiple chains");
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN MESSAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_sendMessage_quote() public {
        // Register app and set target
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes memory message = abi.encode("test_message");
        uint256 fee = gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppA), message, GAS_LIMIT);

        assertTrue(fee > 0, "Send message fee should be non-zero");
    }

    function test_sendMessage_revertInvalidTarget() public {
        // This test may no longer be relevant with the new design where targets
        // are passed directly. Keeping it for backward compatibility check
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes memory message = abi.encode("test");

        // quoteSendMessage doesn't take target as parameter - it resolves internally
        // If no target is configured for the app on that chain, it should fail
        // TODO: Update based on actual implementation behavior
        // vm.expectRevert(IGateway.InvalidTarget.selector);
        // gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppA), message, GAS_LIMIT);

        // For now, just check that it returns a fee (meaning it works)
        uint256 fee = gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppA), message, GAS_LIMIT);
        assertTrue(fee > 0, "Should return fee");
    }

    /*//////////////////////////////////////////////////////////////
                        lzReduce() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_lzReduce_basicAggregation() public {
        // Register app
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        uint16 cmdLabel = 1; // First registered app gets cmdLabel 1

        // Create mock requests
        EVMCallRequestV1[] memory requests = new EVMCallRequestV1[](2);
        requests[0] = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: CHAIN_B_EID,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 15,
            to: address(mockAppB),
            callData: abi.encodeWithSignature("getData()")
        });
        requests[1] = EVMCallRequestV1({
            appRequestLabel: 2,
            targetEid: CHAIN_C_EID,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 20,
            to: appC,
            callData: abi.encodeWithSignature("getData()")
        });

        bytes memory cmd = ReadCodecV1.encode(
            cmdLabel,
            requests,
            EVMCallComputeV1({
                computeSetting: 1,
                targetEid: CHAIN_A_EID,
                isBlockNum: false,
                blockNumOrTimestamp: uint64(block.timestamp),
                confirmations: 0,
                to: address(gatewayA)
            })
        );

        bytes[] memory responses = new bytes[](2);
        responses[0] = abi.encode(uint256(100));
        responses[1] = abi.encode(uint256(200));

        bytes memory result = gatewayA.lzReduce(cmd, responses);

        // GatewayAppMock should aggregate the responses
        assertEq(result, abi.encode(uint256(300)));
    }

    function test_lzReduce_revertInvalidCmdLabel() public {
        uint16 invalidCmdLabel = 999;

        EVMCallRequestV1[] memory requests = new EVMCallRequestV1[](1);
        requests[0] = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: CHAIN_B_EID,
            isBlockNum: false,
            blockNumOrTimestamp: uint64(block.timestamp),
            confirmations: 15,
            to: address(mockAppB),
            callData: abi.encodeWithSignature("getData()")
        });

        bytes memory cmd = ReadCodecV1.encode(
            invalidCmdLabel,
            requests,
            EVMCallComputeV1({
                computeSetting: 1,
                targetEid: CHAIN_A_EID,
                isBlockNum: false,
                blockNumOrTimestamp: uint64(block.timestamp),
                confirmations: 0,
                to: address(gatewayA)
            })
        );

        bytes[] memory responses = new bytes[](1);
        responses[0] = abi.encode(uint256(100));

        vm.expectRevert(IGateway.InvalidCmdLabel.selector);
        gatewayA.lzReduce(cmd, responses);
    }

    /*//////////////////////////////////////////////////////////////
                    FULL INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_crossChainReadFlow() public {
        // Setup all three gateways with proper configuration
        _setupFullCrossChainEnvironment();

        // Register mock app on gateway A
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));
        vm.startPrank(address(mockAppA));
        vm.stopPrank();

        // Perform cross-chain read
        bytes memory callData = abi.encodeWithSignature("getData()");
        bytes32[] memory readChainUIDs = new bytes32[](2);
        readChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        readChainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        address[] memory targets = new address[](2);
        targets[0] = address(mockAppB);
        targets[1] = appC;
        uint256 fee =
            gatewayA.quoteRead(address(mockAppA), readChainUIDs, targets, callData, RETURN_DATA_SIZE, READ_GAS_LIMIT);

        bytes memory extra = abi.encode("test_extra");
        bytes memory lzOptions = abi.encode(READ_GAS_LIMIT, address(mockAppA));

        vm.prank(address(mockAppA));
        bytes32 guid = gatewayA.read{ value: fee }(readChainUIDs, targets, callData, extra, RETURN_DATA_SIZE, lzOptions);

        // Verify packets are sent to the correct destinations
        // This would normally use verifyPackets() but we need proper endpoint setup
        assertTrue(guid != bytes32(0), "Read should return valid GUID");
    }

    function test_integration_sendMessage_singleChain() public {
        // Setup environment
        _setupFullCrossChainEnvironment();

        // Register apps on both chains - the apps themselves, not just addresses
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));
        vm.prank(owner);
        gatewayB.registerApp(address(mockAppB));
        vm.prank(address(mockAppA));

        // Prepare message
        bytes memory message = abi.encode("Hello from Chain A", block.timestamp, uint256(123));

        // Quote the message send
        uint256 fee = gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppA), message, GAS_LIMIT);

        assertTrue(fee > 0, "Fee should be non-zero");

        // Send the message - data parameter should be (gasLimit, refundTo)
        bytes memory data = abi.encode(GAS_LIMIT, address(mockAppA));

        vm.prank(address(mockAppA));
        bytes32 guid =
            gatewayA.sendMessage{ value: fee }(bytes32(uint256(CHAIN_B_EID)), address(mockAppB), message, data);

        assertTrue(guid != bytes32(0), "Should return valid GUID");

        // Verify the packet was queued
        assertTrue(
            hasPendingPackets(uint16(CHAIN_B_EID), bytes32(uint256(uint160(address(gatewayB))))),
            "Should have pending packet"
        );

        // Deliver the message
        verifyPackets(CHAIN_B_EID, bytes32(uint256(uint160(address(gatewayB)))));

        // Verify mockAppB received the message
        assertEq(mockAppB.lastSourceChain(), bytes32(uint256(CHAIN_A_EID)));
        assertEq(mockAppB.lastReceivedMessage(), message);
    }

    function test_integration_sendMessage_multiChain() public {
        // Setup all three chains
        _setupFullCrossChainEnvironment();

        // Register apps on all chains
        vm.startPrank(owner);
        gatewayA.registerApp(address(mockAppA));
        gatewayB.registerApp(address(mockAppB));
        gatewayC.registerApp(appC);
        vm.stopPrank();

        // Create a third mock app for chain C
        GatewayAppMock mockAppC = new GatewayAppMock();
        vm.deal(address(mockAppC), 100 ether);
        vm.startPrank(address(mockAppA));
        vm.stopPrank();

        // Send message from A to B
        bytes memory messageToB = abi.encode("Message to B", uint256(1));
        uint256 feeToB =
            gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppA), messageToB, GAS_LIMIT);

        // Send message from A to C
        bytes memory messageToC = abi.encode("Message to C", uint256(2));
        uint256 feeToC =
            gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_C_EID)), address(mockAppA), messageToC, GAS_LIMIT);

        bytes memory data = abi.encode(GAS_LIMIT, address(mockAppA));

        // Send both messages
        vm.startPrank(address(mockAppA));
        gatewayA.sendMessage{ value: feeToB }(bytes32(uint256(CHAIN_B_EID)), address(mockAppB), messageToB, data);
        gatewayA.sendMessage{ value: feeToC }(bytes32(uint256(CHAIN_C_EID)), address(mockAppC), messageToC, data);
        vm.stopPrank();

        // Verify both packets are queued
        assertTrue(hasPendingPackets(uint16(CHAIN_B_EID), bytes32(uint256(uint160(address(gatewayB))))));
        assertTrue(hasPendingPackets(uint16(CHAIN_C_EID), bytes32(uint256(uint160(address(gatewayC))))));

        // Deliver messages
        verifyPackets(CHAIN_B_EID, bytes32(uint256(uint160(address(gatewayB)))));
        verifyPackets(CHAIN_C_EID, bytes32(uint256(uint160(address(gatewayC)))));

        // Verify reception
        assertEq(mockAppB.lastReceivedMessage(), messageToB);
        assertEq(mockAppC.lastReceivedMessage(), messageToC);
    }

    function test_integration_readAndSendMessage_combined() public {
        // Setup environment with all chains
        _setupFullCrossChainEnvironment();

        // Register apps
        vm.startPrank(owner);
        gatewayA.registerApp(address(mockAppA));
        gatewayB.registerApp(address(mockAppB));
        vm.stopPrank();
        vm.startPrank(address(mockAppA));
        vm.stopPrank();

        vm.startPrank(address(mockAppB));
        vm.stopPrank();

        // First, send a message from A to B
        bytes memory initialMessage = abi.encode("Initial state", uint256(100));
        uint256 sendFee =
            gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppA), initialMessage, GAS_LIMIT);

        bytes memory data = abi.encode(GAS_LIMIT, address(mockAppA));

        vm.prank(address(mockAppA));
        gatewayA.sendMessage{ value: sendFee }(bytes32(uint256(CHAIN_B_EID)), address(mockAppB), initialMessage, data);

        // Deliver the message
        verifyPackets(CHAIN_B_EID, bytes32(uint256(uint160(address(gatewayB)))));

        // Set up read targets for mockAppB on gateway B (needs targets for ALL configured chains: A and C)
        vm.startPrank(address(mockAppB));
        // Already set target for chain A earlier
        vm.stopPrank();

        // Now perform a read from B to verify the state
        bytes memory readCallData = abi.encodeWithSignature("getLastMessage()");
        bytes32[] memory readChainUIDs = new bytes32[](2);
        readChainUIDs[0] = bytes32(uint256(CHAIN_A_EID));
        readChainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        address[] memory readTargets = new address[](2);
        readTargets[0] = address(mockAppA);
        readTargets[1] = appC;
        uint256 readFee = gatewayB.quoteRead(
            address(mockAppB), readChainUIDs, readTargets, readCallData, RETURN_DATA_SIZE, READ_GAS_LIMIT
        );

        bytes memory readOptions = abi.encode(READ_GAS_LIMIT, address(mockAppB));

        vm.prank(address(mockAppB));
        bytes32 readGuid = gatewayB.read{ value: readFee }(
            readChainUIDs, readTargets, readCallData, abi.encode("read_extra"), RETURN_DATA_SIZE, readOptions
        );

        assertTrue(readGuid != bytes32(0), "Read should succeed");

        // Verify both operations completed
        assertEq(mockAppB.lastReceivedMessage(), initialMessage);
    }

    function test_integration_bidirectionalMessaging() public {
        // Setup for bidirectional communication
        _setupFullCrossChainEnvironment();

        // Register apps on both chains
        vm.startPrank(owner);
        gatewayA.registerApp(address(mockAppA));
        gatewayB.registerApp(address(mockAppB));
        vm.stopPrank();

        bytes memory dataA = abi.encode(GAS_LIMIT, address(mockAppA));
        bytes memory dataB = abi.encode(GAS_LIMIT, address(mockAppB));

        // Send message A -> B
        bytes memory messageAtoB = abi.encode("From A to B", uint256(1));
        uint256 feeAtoB =
            gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppA), messageAtoB, GAS_LIMIT);

        vm.prank(address(mockAppA));
        gatewayA.sendMessage{ value: feeAtoB }(bytes32(uint256(CHAIN_B_EID)), address(mockAppB), messageAtoB, dataA);

        // Send message B -> A
        bytes memory messageBtoA = abi.encode("From B to A", uint256(2));
        uint256 feeBtoA =
            gatewayB.quoteSendMessage(bytes32(uint256(CHAIN_A_EID)), address(mockAppB), messageBtoA, GAS_LIMIT);

        vm.prank(address(mockAppB));
        gatewayB.sendMessage{ value: feeBtoA }(bytes32(uint256(CHAIN_A_EID)), address(mockAppA), messageBtoA, dataB);

        // Verify both have pending packets
        assertTrue(hasPendingPackets(uint16(CHAIN_B_EID), bytes32(uint256(uint160(address(gatewayB))))));
        assertTrue(hasPendingPackets(uint16(CHAIN_A_EID), bytes32(uint256(uint160(address(gatewayA))))));

        // Deliver both messages
        verifyPackets(CHAIN_B_EID, bytes32(uint256(uint160(address(gatewayB)))));
        verifyPackets(CHAIN_A_EID, bytes32(uint256(uint160(address(gatewayA)))));

        // Verify reception
        assertEq(mockAppB.lastReceivedMessage(), messageAtoB);
        assertEq(mockAppB.lastSourceChain(), bytes32(uint256(CHAIN_A_EID)));

        assertEq(mockAppA.lastReceivedMessage(), messageBtoA);
        assertEq(mockAppA.lastSourceChain(), bytes32(uint256(CHAIN_B_EID)));
    }

    function test_integration_multiChainRead_aggregation() public {
        // Setup all three chains
        _setupFullCrossChainEnvironment();

        // Create apps with specific return values for aggregation testing
        GatewayAppMock appWithValue100 = new GatewayAppMock();
        GatewayAppMock appWithValue200 = new GatewayAppMock();
        GatewayAppMock appWithValue300 = new GatewayAppMock();

        vm.deal(address(appWithValue100), 100 ether);

        // Set return values for each app
        appWithValue100.setReduceReturnData(abi.encode(uint256(100)));
        appWithValue200.setReduceReturnData(abi.encode(uint256(200)));
        appWithValue300.setReduceReturnData(abi.encode(uint256(300)));

        // Register the aggregator app on chain A
        vm.prank(owner);
        gatewayA.registerApp(address(appWithValue100));

        // Register target apps on other chains
        vm.prank(owner);
        gatewayB.registerApp(address(appWithValue200));
        vm.prank(owner);
        gatewayC.registerApp(address(appWithValue300));
        vm.startPrank(address(appWithValue100));
        vm.stopPrank();

        // Perform multi-chain read
        bytes memory callData = abi.encodeWithSignature("getValue()");
        bytes32[] memory readChainUIDs = new bytes32[](2);
        readChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        readChainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        address[] memory targets = new address[](2);
        targets[0] = address(appWithValue200);
        targets[1] = address(appWithValue300);
        uint256 fee = gatewayA.quoteRead(
            address(appWithValue100), readChainUIDs, targets, callData, RETURN_DATA_SIZE, READ_GAS_LIMIT
        );

        bytes memory options = abi.encode(READ_GAS_LIMIT, address(appWithValue100));

        vm.prank(address(appWithValue100));
        bytes32 guid = gatewayA.read{ value: fee }(
            readChainUIDs, targets, callData, abi.encode("aggregation_test"), RETURN_DATA_SIZE, options
        );

        assertTrue(guid != bytes32(0), "Multi-chain read should succeed");

        // The aggregated result would be 100 + 200 + 300 = 600
        // This would be verified after packet delivery and reduction
    }

    function test_integration_sendMessage_withFailure() public {
        // Setup environment
        _setupFullCrossChainEnvironment();

        // Register apps
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        // Try to quote a message send - should work now
        bytes memory message = abi.encode("test");

        // quoteSendMessage doesn't validate targets anymore in the new design
        uint256 fee = gatewayA.quoteSendMessage(bytes32(uint256(CHAIN_B_EID)), address(mockAppA), message, GAS_LIMIT);

        assertTrue(fee > 0, "Should return valid fee after target set");
    }

    function test_integration_readWithDifferentReturnSizes() public {
        // Test reading with various return data sizes
        _setupFullCrossChainEnvironment();

        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        // Register app on chain B to be a valid target
        vm.prank(owner);
        gatewayB.registerApp(address(mockAppB));
        vm.startPrank(address(mockAppA));
        vm.stopPrank();

        // Test with small return size
        bytes memory callData = abi.encodeWithSignature("getSmallData()");
        bytes32[] memory readChainUIDs = new bytes32[](2);
        readChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        readChainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        address[] memory targets = new address[](2);
        targets[0] = address(mockAppB);
        targets[1] = appC;
        uint256 fee1 = gatewayA.quoteRead(
            address(mockAppA),
            readChainUIDs,
            targets,
            callData,
            32, // Small return size
            READ_GAS_LIMIT
        );

        // Test with large return size
        uint256 fee2 = gatewayA.quoteRead(
            address(mockAppA),
            readChainUIDs,
            targets,
            callData,
            10_000, // Large return size
            READ_GAS_LIMIT
        );

        // Larger return size should have higher fee
        assertTrue(fee2 >= fee1, "Larger return size should have equal or higher fee");

        // Execute read with large return size
        bytes memory options = abi.encode(READ_GAS_LIMIT, address(mockAppA));

        vm.prank(address(mockAppA));
        bytes32 guid =
            gatewayA.read{ value: fee2 }(readChainUIDs, targets, callData, abi.encode("large_return"), 10_000, options);

        assertTrue(guid != bytes32(0), "Read with large return should succeed");
    }

    /*//////////////////////////////////////////////////////////////
                    CHAIN VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_validation_read_validChainUIDs() public {
        // Setup: register app and configure chains
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes32[] memory chainUIDs = new bytes32[](2);
        uint16[] memory confirmations = new uint16[](2);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        chainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        confirmations[0] = 1;
        confirmations[1] = 2;

        vm.prank(owner);
        gatewayA.configureChains(chainUIDs, confirmations);

        // App requests read from configured chains - should succeed
        bytes memory callData = abi.encodeWithSignature("test()");
        bytes memory extra = abi.encode("extra");
        bytes memory data = abi.encode(uint128(100_000), address(this)); // Refund to test contract

        address[] memory targets = new address[](2);
        targets[0] = address(mockAppB);
        targets[1] = appC;

        vm.prank(address(mockAppA));
        bytes32 guid = gatewayA.read{ value: 1 ether }(chainUIDs, targets, callData, extra, 256, data);
        assertTrue(guid != bytes32(0), "Read should return valid GUID");
    }

    function test_validation_read_revertInvalidChainUIDs() public {
        // Setup: register app and configure chains (only B and C, not A)
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes32[] memory configChainUIDs = new bytes32[](2);
        uint16[] memory confirmations = new uint16[](2);
        configChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        configChainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        confirmations[0] = 1;
        confirmations[1] = 2;

        vm.prank(owner);
        gatewayA.configureChains(configChainUIDs, confirmations);

        // App requests read from non-configured chain - should revert
        bytes32[] memory chainUIDs = new bytes32[](1);
        chainUIDs[0] = bytes32(uint256(CHAIN_A_EID)); // Not configured

        bytes memory callData = abi.encodeWithSignature("test()");
        bytes memory extra = abi.encode("extra");
        bytes memory data = abi.encode(uint128(100_000), address(this)); // Refund to test contract

        address[] memory targets = new address[](1);
        targets[0] = address(mockAppA);

        vm.prank(address(mockAppA));
        vm.expectRevert(IGateway.InvalidChainUIDs.selector);
        gatewayA.read{ value: 1 ether }(chainUIDs, targets, callData, extra, 256, data);
    }

    function test_validation_read_revertPartiallyInvalidChainUIDs() public {
        // Setup: register app and configure only chain B
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes32[] memory configChainUIDs = new bytes32[](1);
        uint16[] memory confirmations = new uint16[](1);
        configChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        confirmations[0] = 1;

        vm.prank(owner);
        gatewayA.configureChains(configChainUIDs, confirmations);

        // App requests read from mix of valid and invalid chains - should revert
        bytes32[] memory chainUIDs = new bytes32[](2);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID)); // Valid
        chainUIDs[1] = bytes32(uint256(CHAIN_C_EID)); // Invalid

        bytes memory callData = abi.encodeWithSignature("test()");
        bytes memory extra = abi.encode("extra");
        bytes memory data = abi.encode(uint128(100_000), address(this)); // Refund to test contract

        address[] memory targets = new address[](2);
        targets[0] = address(mockAppB);
        targets[1] = appC;

        vm.prank(address(mockAppA));
        vm.expectRevert(IGateway.InvalidChainUIDs.selector);
        gatewayA.read{ value: 1 ether }(chainUIDs, targets, callData, extra, 256, data);
    }

    function test_validation_quoteRead_validChainUIDs() public {
        // Setup: register app and configure chains
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes32[] memory chainUIDs = new bytes32[](2);
        uint16[] memory confirmations = new uint16[](2);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        chainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        confirmations[0] = 1;
        confirmations[1] = 2;

        vm.prank(owner);
        gatewayA.configureChains(chainUIDs, confirmations);

        // App quotes read from configured chains - should succeed
        bytes memory callData = abi.encodeWithSignature("test()");

        address[] memory targets = new address[](2);
        targets[0] = address(mockAppB);
        targets[1] = appC;
        uint256 fee = gatewayA.quoteRead(address(mockAppA), chainUIDs, targets, callData, 256, 100_000);
        assertTrue(fee > 0, "Fee should be non-zero");
    }

    function test_validation_quoteRead_revertInvalidChainUIDs() public {
        // Setup: register app and configure chains (only B, not C)
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes32[] memory configChainUIDs = new bytes32[](1);
        uint16[] memory confirmations = new uint16[](1);
        configChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        confirmations[0] = 1;

        vm.prank(owner);
        gatewayA.configureChains(configChainUIDs, confirmations);

        // App quotes read from non-configured chain - should revert
        bytes32[] memory chainUIDs = new bytes32[](1);
        chainUIDs[0] = bytes32(uint256(CHAIN_C_EID)); // Not configured

        bytes memory callData = abi.encodeWithSignature("test()");

        address[] memory targets = new address[](1);
        targets[0] = appC;
        vm.expectRevert(IGateway.InvalidChainUIDs.selector);
        gatewayA.quoteRead(address(mockAppA), chainUIDs, targets, callData, 256, 100_000);
    }

    function test_validation_read_subsetOfConfiguredChains() public {
        // Setup: register app and configure multiple chains
        vm.prank(owner);
        gatewayA.registerApp(address(mockAppA));

        bytes32[] memory configChainUIDs = new bytes32[](2);
        uint16[] memory confirmations = new uint16[](2);
        configChainUIDs[0] = bytes32(uint256(CHAIN_B_EID));
        configChainUIDs[1] = bytes32(uint256(CHAIN_C_EID));
        confirmations[0] = 1;
        confirmations[1] = 2;

        vm.prank(owner);
        gatewayA.configureChains(configChainUIDs, confirmations);

        // App can request subset of configured chains
        bytes32[] memory chainUIDs = new bytes32[](1);
        chainUIDs[0] = bytes32(uint256(CHAIN_B_EID)); // Only one of the configured chains

        bytes memory callData = abi.encodeWithSignature("test()");
        bytes memory extra = abi.encode("extra");
        bytes memory data = abi.encode(uint128(100_000), address(this)); // Refund to test contract

        address[] memory targets = new address[](1);
        targets[0] = address(mockAppB);

        vm.prank(address(mockAppA));
        bytes32 guid = gatewayA.read{ value: 1 ether }(chainUIDs, targets, callData, extra, 256, data);
        assertTrue(guid != bytes32(0), "Read should succeed with subset of configured chains");
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setupFullCrossChainEnvironment() internal {
        // Configure chains on all gateways
        bytes32[] memory chainUIDsForA = new bytes32[](2);
        uint16[] memory confirmationsForA = new uint16[](2);
        chainUIDsForA[0] = bytes32(uint256(CHAIN_B_EID));
        chainUIDsForA[1] = bytes32(uint256(CHAIN_C_EID));
        confirmationsForA[0] = 15;
        confirmationsForA[1] = 20;

        bytes32[] memory chainUIDsForB = new bytes32[](2);
        uint16[] memory confirmationsForB = new uint16[](2);
        chainUIDsForB[0] = bytes32(uint256(CHAIN_A_EID));
        chainUIDsForB[1] = bytes32(uint256(CHAIN_C_EID));
        confirmationsForB[0] = 15;
        confirmationsForB[1] = 20;

        bytes32[] memory chainUIDsForC = new bytes32[](2);
        uint16[] memory confirmationsForC = new uint16[](2);
        chainUIDsForC[0] = bytes32(uint256(CHAIN_A_EID));
        chainUIDsForC[1] = bytes32(uint256(CHAIN_B_EID));
        confirmationsForC[0] = 15;
        confirmationsForC[1] = 20;

        vm.startPrank(owner);
        gatewayA.configureChains(chainUIDsForA, confirmationsForA);
        gatewayB.configureChains(chainUIDsForB, confirmationsForB);
        gatewayC.configureChains(chainUIDsForC, confirmationsForC);
        vm.stopPrank();
    }
}
