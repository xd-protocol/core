// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { RemoteAppChronicleDeployer } from "../../src/chronicles/RemoteAppChronicleDeployer.sol";
import { RemoteAppChronicle } from "../../src/chronicles/RemoteAppChronicle.sol";
import { IRemoteAppChronicleDeployer } from "../../src/interfaces/IRemoteAppChronicleDeployer.sol";

/**
 * @title RemoteAppChronicleDeployerTest
 * @notice Comprehensive tests for RemoteAppChronicleDeployer functionality
 * @dev Tests Create2 deployment, address computation, access control, and deterministic behavior for RemoteAppChronicle deployment
 */
contract RemoteAppChronicleDeployerTest is Test {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    RemoteAppChronicleDeployer deployer;
    address liquidityMatrix;
    address unauthorizedUser;
    address app;
    bytes32 constant CHAIN_UID = keccak256("test_chain");
    uint256 constant VERSION = 1;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        liquidityMatrix = makeAddr("liquidityMatrix");
        unauthorizedUser = makeAddr("unauthorizedUser");
        app = makeAddr("app");

        deployer = new RemoteAppChronicleDeployer(liquidityMatrix);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public {
        RemoteAppChronicleDeployer newDeployer = new RemoteAppChronicleDeployer(liquidityMatrix);

        assertEq(newDeployer.liquidityMatrix(), liquidityMatrix);
    }

    function test_constructor_withDifferentAddress() public {
        address differentMatrix = makeAddr("differentMatrix");
        RemoteAppChronicleDeployer newDeployer = new RemoteAppChronicleDeployer(differentMatrix);

        assertEq(newDeployer.liquidityMatrix(), differentMatrix);
    }

    function test_constructor_zeroAddress() public {
        // Should allow zero address (no validation in constructor)
        RemoteAppChronicleDeployer newDeployer = new RemoteAppChronicleDeployer(address(0));

        assertEq(newDeployer.liquidityMatrix(), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        computeAddress() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_computeAddress() public view {
        address predictedAddress = deployer.computeAddress(app, CHAIN_UID, VERSION);

        // Address should be non-zero
        assertTrue(predictedAddress != address(0));

        // Address should be valid contract address format
        assertTrue(predictedAddress > address(0x10)); // Above precompiles
    }

    function test_computeAddress_differentParams() public {
        address app1 = makeAddr("app1");
        address app2 = makeAddr("app2");
        bytes32 chainUID1 = keccak256("chain1");
        bytes32 chainUID2 = keccak256("chain2");
        uint256 version1 = 1;
        uint256 version2 = 2;

        address addr1 = deployer.computeAddress(app1, chainUID1, version1);
        address addr2 = deployer.computeAddress(app1, chainUID1, version2);
        address addr3 = deployer.computeAddress(app1, chainUID2, version1);
        address addr4 = deployer.computeAddress(app2, chainUID1, version1);

        // All addresses should be different
        assertTrue(addr1 != addr2);
        assertTrue(addr1 != addr3);
        assertTrue(addr1 != addr4);
        assertTrue(addr2 != addr3);
        assertTrue(addr2 != addr4);
        assertTrue(addr3 != addr4);
    }

    function test_computeAddress_deterministicForSameParams() public view {
        address addr1 = deployer.computeAddress(app, CHAIN_UID, VERSION);
        address addr2 = deployer.computeAddress(app, CHAIN_UID, VERSION);

        // Same parameters should give same address
        assertEq(addr1, addr2);
    }

    function test_computeAddress_matchesCreate2Logic() public {
        bytes32 salt = keccak256(abi.encodePacked(app, CHAIN_UID, VERSION));
        bytes memory bytecode = abi.encodePacked(
            type(RemoteAppChronicle).creationCode, abi.encode(liquidityMatrix, app, CHAIN_UID, VERSION)
        );

        address expectedAddress = Create2.computeAddress(salt, keccak256(bytecode), address(deployer));
        address computedAddress = deployer.computeAddress(app, CHAIN_UID, VERSION);

        assertEq(computedAddress, expectedAddress);
    }

    function testFuzz_computeAddress(address _app, bytes32 _chainUID, uint256 _version) public view {
        vm.assume(_app != address(0));
        vm.assume(_chainUID != bytes32(0));
        vm.assume(_version <= type(uint256).max);

        address predictedAddress = deployer.computeAddress(_app, _chainUID, _version);

        // Should always return a valid address
        assertTrue(predictedAddress != address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            deploy() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deploy() public {
        address predictedAddress = deployer.computeAddress(app, CHAIN_UID, VERSION);

        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, CHAIN_UID, VERSION);

        // Deployed address should match predicted address
        assertEq(deployedAddress, predictedAddress);

        // Should have deployed a RemoteAppChronicle contract
        assertTrue(deployedAddress.code.length > 0);

        // Verify the deployed contract is correctly initialized
        RemoteAppChronicle chronicle = RemoteAppChronicle(deployedAddress);
        assertEq(chronicle.liquidityMatrix(), liquidityMatrix);
        assertEq(chronicle.app(), app);
        assertEq(chronicle.chainUID(), CHAIN_UID);
        assertEq(chronicle.version(), VERSION);
    }

    function test_deploy_multipleWithDifferentParams() public {
        address app1 = makeAddr("app1");
        address app2 = makeAddr("app2");
        bytes32 chainUID1 = keccak256("chain1");
        bytes32 chainUID2 = keccak256("chain2");
        uint256 version1 = 1;
        uint256 version2 = 2;

        vm.startPrank(liquidityMatrix);

        address addr1 = deployer.deploy(app1, chainUID1, version1);
        address addr2 = deployer.deploy(app1, chainUID1, version2);
        address addr3 = deployer.deploy(app1, chainUID2, version1);
        address addr4 = deployer.deploy(app2, chainUID1, version1);

        vm.stopPrank();

        // All addresses should be different
        assertTrue(addr1 != addr2);
        assertTrue(addr1 != addr3);
        assertTrue(addr1 != addr4);
        assertTrue(addr2 != addr3);
        assertTrue(addr2 != addr4);
        assertTrue(addr3 != addr4);

        // All should have contract code
        assertTrue(addr1.code.length > 0);
        assertTrue(addr2.code.length > 0);
        assertTrue(addr3.code.length > 0);
        assertTrue(addr4.code.length > 0);

        // Verify correct initialization
        assertEq(RemoteAppChronicle(addr1).app(), app1);
        assertEq(RemoteAppChronicle(addr1).chainUID(), chainUID1);
        assertEq(RemoteAppChronicle(addr1).version(), version1);

        assertEq(RemoteAppChronicle(addr2).app(), app1);
        assertEq(RemoteAppChronicle(addr2).chainUID(), chainUID1);
        assertEq(RemoteAppChronicle(addr2).version(), version2);

        assertEq(RemoteAppChronicle(addr3).app(), app1);
        assertEq(RemoteAppChronicle(addr3).chainUID(), chainUID2);
        assertEq(RemoteAppChronicle(addr3).version(), version1);

        assertEq(RemoteAppChronicle(addr4).app(), app2);
        assertEq(RemoteAppChronicle(addr4).chainUID(), chainUID1);
        assertEq(RemoteAppChronicle(addr4).version(), version1);
    }

    function test_deploy_sameParamsTwice_shouldRevert() public {
        vm.startPrank(liquidityMatrix);

        // First deployment should succeed
        deployer.deploy(app, CHAIN_UID, VERSION);

        // Second deployment with same parameters should revert (Create2 collision)
        vm.expectRevert();
        deployer.deploy(app, CHAIN_UID, VERSION);

        vm.stopPrank();
    }

    function test_deploy_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(IRemoteAppChronicleDeployer.Forbidden.selector);
        deployer.deploy(app, CHAIN_UID, VERSION);
    }

    function test_deploy_onlyLiquidityMatrixCanCall() public {
        // LiquidityMatrix should be able to deploy
        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, CHAIN_UID, VERSION);
        assertTrue(deployedAddress.code.length > 0);

        // Different app/chain/version for next test
        address differentApp = makeAddr("differentApp");
        bytes32 differentChainUID = keccak256("different_chain");

        // Unauthorized users should not be able to deploy
        vm.prank(unauthorizedUser);
        vm.expectRevert(IRemoteAppChronicleDeployer.Forbidden.selector);
        deployer.deploy(differentApp, differentChainUID, VERSION);

        vm.prank(app);
        vm.expectRevert(IRemoteAppChronicleDeployer.Forbidden.selector);
        deployer.deploy(differentApp, differentChainUID, VERSION + 1);
    }

    function testFuzz_deploy_onlyLiquidityMatrix(address caller, address _app, bytes32 _chainUID, uint256 _version)
        public
    {
        vm.assume(caller != liquidityMatrix);
        vm.assume(_app != address(0));
        vm.assume(_chainUID != bytes32(0));
        vm.assume(_version <= type(uint256).max);

        vm.prank(caller);
        vm.expectRevert(IRemoteAppChronicleDeployer.Forbidden.selector);
        deployer.deploy(_app, _chainUID, _version);
    }

    /*//////////////////////////////////////////////////////////////
                        DETERMINISTIC BEHAVIOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deterministicDeployment() public {
        // Deploy with one deployer
        RemoteAppChronicleDeployer deployer1 = new RemoteAppChronicleDeployer(liquidityMatrix);

        // Deploy with another deployer (same liquidityMatrix)
        RemoteAppChronicleDeployer deployer2 = new RemoteAppChronicleDeployer(liquidityMatrix);

        // Predicted addresses should be different (different deployer contracts)
        address pred1 = deployer1.computeAddress(app, CHAIN_UID, VERSION);
        address pred2 = deployer2.computeAddress(app, CHAIN_UID, VERSION);
        assertTrue(pred1 != pred2);

        // But each should be deterministic
        assertEq(pred1, deployer1.computeAddress(app, CHAIN_UID, VERSION));
        assertEq(pred2, deployer2.computeAddress(app, CHAIN_UID, VERSION));
    }

    function test_saltGeneration() public {
        // Test that salt is generated correctly
        bytes32 expectedSalt = keccak256(abi.encodePacked(app, CHAIN_UID, VERSION));

        // We can't directly access the salt, but we can verify through address computation
        bytes memory bytecode = abi.encodePacked(
            type(RemoteAppChronicle).creationCode, abi.encode(liquidityMatrix, app, CHAIN_UID, VERSION)
        );

        address expectedAddress = Create2.computeAddress(expectedSalt, keccak256(bytecode), address(deployer));
        address computedAddress = deployer.computeAddress(app, CHAIN_UID, VERSION);

        assertEq(computedAddress, expectedAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deploy_withZeroApp() public {
        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(address(0), CHAIN_UID, VERSION);

        assertTrue(deployedAddress.code.length > 0);
        RemoteAppChronicle chronicle = RemoteAppChronicle(deployedAddress);
        assertEq(chronicle.app(), address(0));
    }

    function test_deploy_withZeroChainUID() public {
        bytes32 zeroChainUID = bytes32(0);

        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, zeroChainUID, VERSION);

        assertTrue(deployedAddress.code.length > 0);
        RemoteAppChronicle chronicle = RemoteAppChronicle(deployedAddress);
        assertEq(chronicle.chainUID(), zeroChainUID);
    }

    function test_deploy_withMaxVersion() public {
        uint256 maxVersion = type(uint256).max;

        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, CHAIN_UID, maxVersion);

        assertTrue(deployedAddress.code.length > 0);
        RemoteAppChronicle chronicle = RemoteAppChronicle(deployedAddress);
        assertEq(chronicle.version(), maxVersion);
    }

    function test_deploy_withVersionZero() public {
        uint256 versionZero = 0;

        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, CHAIN_UID, versionZero);

        assertTrue(deployedAddress.code.length > 0);
        RemoteAppChronicle chronicle = RemoteAppChronicle(deployedAddress);
        assertEq(chronicle.version(), versionZero);
    }

    function test_deploy_withLongChainUID() public {
        bytes32 longChainUID = keccak256("very_long_chain_identifier_name_that_uses_full_bytes32_space");

        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, longChainUID, VERSION);

        assertTrue(deployedAddress.code.length > 0);
        RemoteAppChronicle chronicle = RemoteAppChronicle(deployedAddress);
        assertEq(chronicle.chainUID(), longChainUID);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployedChronicleWorksCorrectly() public {
        // Deploy a chronicle
        vm.prank(liquidityMatrix);
        address chronicleAddress = deployer.deploy(app, CHAIN_UID, VERSION);

        RemoteAppChronicle chronicle = RemoteAppChronicle(chronicleAddress);

        // Test basic functionality of the deployed chronicle
        assertEq(chronicle.liquidityMatrix(), liquidityMatrix);
        assertEq(chronicle.app(), app);
        assertEq(chronicle.chainUID(), CHAIN_UID);
        assertEq(chronicle.version(), VERSION);

        // Test initial state
        assertFalse(chronicle.isLiquiditySettled(1000));
        assertFalse(chronicle.isDataSettled(1000));
        assertFalse(chronicle.isFinalized(1000));
        assertEq(chronicle.getTotalLiquidityAt(1000), 0);
        assertEq(chronicle.getLiquidityAt(makeAddr("testAccount"), 1000), 0);
        assertEq(chronicle.getDataAt(keccak256("testkey"), 1000).length, 0);
    }

    function test_multipleDeployersIndependence() public {
        address matrix1 = makeAddr("matrix1");
        address matrix2 = makeAddr("matrix2");

        RemoteAppChronicleDeployer deployer1 = new RemoteAppChronicleDeployer(matrix1);
        RemoteAppChronicleDeployer deployer2 = new RemoteAppChronicleDeployer(matrix2);

        // Deploy from both deployers
        vm.prank(matrix1);
        address chronicle1 = deployer1.deploy(app, CHAIN_UID, VERSION);

        vm.prank(matrix2);
        address chronicle2 = deployer2.deploy(app, CHAIN_UID, VERSION);

        // Should be different addresses
        assertTrue(chronicle1 != chronicle2);

        // Each should have correct liquidityMatrix
        assertEq(RemoteAppChronicle(chronicle1).liquidityMatrix(), matrix1);
        assertEq(RemoteAppChronicle(chronicle2).liquidityMatrix(), matrix2);
    }

    function test_crossChainScenario() public {
        bytes32 ethereum = keccak256("ethereum");
        bytes32 polygon = keccak256("polygon");
        bytes32 arbitrum = keccak256("arbitrum");

        address dApp = makeAddr("dApp");
        uint256 currentVersion = 1;

        vm.startPrank(liquidityMatrix);

        // Deploy chronicles for the same dApp on different chains
        address ethChronicle = deployer.deploy(dApp, ethereum, currentVersion);
        address polyChronicle = deployer.deploy(dApp, polygon, currentVersion);
        address arbChronicle = deployer.deploy(dApp, arbitrum, currentVersion);

        vm.stopPrank();

        // All should be different addresses
        assertTrue(ethChronicle != polyChronicle);
        assertTrue(ethChronicle != arbChronicle);
        assertTrue(polyChronicle != arbChronicle);

        // All should be properly initialized
        assertEq(RemoteAppChronicle(ethChronicle).chainUID(), ethereum);
        assertEq(RemoteAppChronicle(polyChronicle).chainUID(), polygon);
        assertEq(RemoteAppChronicle(arbChronicle).chainUID(), arbitrum);

        // All should have same app and version
        assertEq(RemoteAppChronicle(ethChronicle).app(), dApp);
        assertEq(RemoteAppChronicle(polyChronicle).app(), dApp);
        assertEq(RemoteAppChronicle(arbChronicle).app(), dApp);

        assertEq(RemoteAppChronicle(ethChronicle).version(), currentVersion);
        assertEq(RemoteAppChronicle(polyChronicle).version(), currentVersion);
        assertEq(RemoteAppChronicle(arbChronicle).version(), currentVersion);
    }

    /*//////////////////////////////////////////////////////////////
                            GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gasUsage_deploy() public {
        uint256 gasBefore = gasleft();

        vm.prank(liquidityMatrix);
        deployer.deploy(app, CHAIN_UID, VERSION);

        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (less than 2.1M gas for contract creation)
        // Increased slightly due to isContract parameter addition
        assertTrue(gasUsed < 2_100_000);

        // Should use substantial gas due to contract creation
        assertTrue(gasUsed > 1_900_000);
    }

    function test_gasUsage_computeAddress() public view {
        uint256 gasBefore = gasleft();

        deployer.computeAddress(app, CHAIN_UID, VERSION);

        uint256 gasUsed = gasBefore - gasleft();

        // Address computation should be relatively cheap
        assertTrue(gasUsed < 50_000);
    }

    function test_gasUsage_multipleDeployments() public {
        vm.startPrank(liquidityMatrix);

        uint256 gasBefore1 = gasleft();
        deployer.deploy(app, CHAIN_UID, VERSION);
        uint256 firstDeployGas = gasBefore1 - gasleft();

        uint256 gasBefore2 = gasleft();
        deployer.deploy(app, keccak256("different_chain"), VERSION);
        uint256 secondDeployGas = gasBefore2 - gasleft();

        vm.stopPrank();

        // Gas usage should be similar for similar deployments
        uint256 gasDifference =
            firstDeployGas > secondDeployGas ? firstDeployGas - secondDeployGas : secondDeployGas - firstDeployGas;

        // Should be within 10% of each other
        assertTrue(gasDifference < firstDeployGas / 10);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_versionUpgradeScenario() public {
        address dApp = makeAddr("dApp");
        bytes32 chainUID = keccak256("target_chain");

        vm.startPrank(liquidityMatrix);

        // Deploy chronicles for different versions of the same app on same chain
        address chronicleV1 = deployer.deploy(dApp, chainUID, 1);
        address chronicleV2 = deployer.deploy(dApp, chainUID, 2);
        address chronicleV3 = deployer.deploy(dApp, chainUID, 3);

        vm.stopPrank();

        // All should be different addresses
        assertTrue(chronicleV1 != chronicleV2);
        assertTrue(chronicleV1 != chronicleV3);
        assertTrue(chronicleV2 != chronicleV3);

        // All should have same app and chainUID but different versions
        assertEq(RemoteAppChronicle(chronicleV1).app(), dApp);
        assertEq(RemoteAppChronicle(chronicleV2).app(), dApp);
        assertEq(RemoteAppChronicle(chronicleV3).app(), dApp);

        assertEq(RemoteAppChronicle(chronicleV1).chainUID(), chainUID);
        assertEq(RemoteAppChronicle(chronicleV2).chainUID(), chainUID);
        assertEq(RemoteAppChronicle(chronicleV3).chainUID(), chainUID);

        assertEq(RemoteAppChronicle(chronicleV1).version(), 1);
        assertEq(RemoteAppChronicle(chronicleV2).version(), 2);
        assertEq(RemoteAppChronicle(chronicleV3).version(), 3);
    }

    function test_multiAppMultiChainScenario() public {
        address app1 = makeAddr("app1");
        address app2 = makeAddr("app2");
        bytes32 chain1 = keccak256("chain1");
        bytes32 chain2 = keccak256("chain2");
        uint256 version = 1;

        vm.startPrank(liquidityMatrix);

        // Create matrix of app/chain combinations
        address chronicle_app1_chain1 = deployer.deploy(app1, chain1, version);
        address chronicle_app1_chain2 = deployer.deploy(app1, chain2, version);
        address chronicle_app2_chain1 = deployer.deploy(app2, chain1, version);
        address chronicle_app2_chain2 = deployer.deploy(app2, chain2, version);

        vm.stopPrank();

        // All should be different addresses
        assertTrue(chronicle_app1_chain1 != chronicle_app1_chain2);
        assertTrue(chronicle_app1_chain1 != chronicle_app2_chain1);
        assertTrue(chronicle_app1_chain1 != chronicle_app2_chain2);
        assertTrue(chronicle_app1_chain2 != chronicle_app2_chain1);
        assertTrue(chronicle_app1_chain2 != chronicle_app2_chain2);
        assertTrue(chronicle_app2_chain1 != chronicle_app2_chain2);

        // Verify proper app/chain assignments
        assertEq(RemoteAppChronicle(chronicle_app1_chain1).app(), app1);
        assertEq(RemoteAppChronicle(chronicle_app1_chain1).chainUID(), chain1);

        assertEq(RemoteAppChronicle(chronicle_app1_chain2).app(), app1);
        assertEq(RemoteAppChronicle(chronicle_app1_chain2).chainUID(), chain2);

        assertEq(RemoteAppChronicle(chronicle_app2_chain1).app(), app2);
        assertEq(RemoteAppChronicle(chronicle_app2_chain1).chainUID(), chain1);

        assertEq(RemoteAppChronicle(chronicle_app2_chain2).app(), app2);
        assertEq(RemoteAppChronicle(chronicle_app2_chain2).chainUID(), chain2);
    }
}
