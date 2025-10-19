// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { LocalAppChronicleDeployer } from "../../src/chronicles/LocalAppChronicleDeployer.sol";
import { LocalAppChronicle } from "../../src/chronicles/LocalAppChronicle.sol";
import { ILocalAppChronicleDeployer } from "../../src/interfaces/ILocalAppChronicleDeployer.sol";

/**
 * @title LocalAppChronicleDeployerTest
 * @notice Comprehensive tests for LocalAppChronicleDeployer functionality
 * @dev Tests Create2 deployment, address computation, access control, and deterministic behavior
 */
contract LocalAppChronicleDeployerTest is Test {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    LocalAppChronicleDeployer deployer;
    address liquidityMatrix;
    address unauthorizedUser;
    address app;
    uint256 constant VERSION = 1;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        liquidityMatrix = makeAddr("liquidityMatrix");
        unauthorizedUser = makeAddr("unauthorizedUser");
        app = makeAddr("app");

        deployer = new LocalAppChronicleDeployer(liquidityMatrix);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor() public {
        LocalAppChronicleDeployer newDeployer = new LocalAppChronicleDeployer(liquidityMatrix);

        assertEq(newDeployer.liquidityMatrix(), liquidityMatrix);
    }

    function test_constructor_withDifferentAddress() public {
        address differentMatrix = makeAddr("differentMatrix");
        LocalAppChronicleDeployer newDeployer = new LocalAppChronicleDeployer(differentMatrix);

        assertEq(newDeployer.liquidityMatrix(), differentMatrix);
    }

    function test_constructor_zeroAddress() public {
        // Should allow zero address (no validation in constructor)
        LocalAppChronicleDeployer newDeployer = new LocalAppChronicleDeployer(address(0));

        assertEq(newDeployer.liquidityMatrix(), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        computeAddress() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_computeAddress() public view {
        address predictedAddress = deployer.computeAddress(app, VERSION);

        // Address should be non-zero
        assertTrue(predictedAddress != address(0));

        // Address should be valid contract address format
        assertTrue(predictedAddress > address(0x10)); // Above precompiles
    }

    function test_computeAddress_differentParams() public {
        address app1 = makeAddr("app1");
        address app2 = makeAddr("app2");
        uint256 version1 = 1;
        uint256 version2 = 2;

        address addr1 = deployer.computeAddress(app1, version1);
        address addr2 = deployer.computeAddress(app1, version2);
        address addr3 = deployer.computeAddress(app2, version1);

        // All addresses should be different
        assertTrue(addr1 != addr2);
        assertTrue(addr1 != addr3);
        assertTrue(addr2 != addr3);
    }

    function test_computeAddress_deterministicForSameParams() public view {
        address addr1 = deployer.computeAddress(app, VERSION);
        address addr2 = deployer.computeAddress(app, VERSION);

        // Same parameters should give same address
        assertEq(addr1, addr2);
    }

    function test_computeAddress_matchesCreate2Logic() public {
        bytes32 salt = keccak256(abi.encodePacked(app, VERSION));
        bytes memory bytecode =
            abi.encodePacked(type(LocalAppChronicle).creationCode, abi.encode(liquidityMatrix, app, VERSION));

        address expectedAddress = Create2.computeAddress(salt, keccak256(bytecode), address(deployer));
        address computedAddress = deployer.computeAddress(app, VERSION);

        assertEq(computedAddress, expectedAddress);
    }

    function testFuzz_computeAddress(address _app, uint256 _version) public view {
        vm.assume(_app != address(0));
        vm.assume(_version <= type(uint256).max);

        address predictedAddress = deployer.computeAddress(_app, _version);

        // Should always return a valid address
        assertTrue(predictedAddress != address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            deploy() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deploy() public {
        address predictedAddress = deployer.computeAddress(app, VERSION);

        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, VERSION);

        // Deployed address should match predicted address
        assertEq(deployedAddress, predictedAddress);

        // Should have deployed a LocalAppChronicle contract
        assertTrue(deployedAddress.code.length > 0);

        // Verify the deployed contract is correctly initialized
        LocalAppChronicle chronicle = LocalAppChronicle(deployedAddress);
        assertEq(chronicle.liquidityMatrix(), liquidityMatrix);
        assertEq(chronicle.app(), app);
        assertEq(chronicle.version(), VERSION);
    }

    function test_deploy_multipleWithDifferentParams() public {
        address app1 = makeAddr("app1");
        address app2 = makeAddr("app2");
        uint256 version1 = 1;
        uint256 version2 = 2;

        vm.startPrank(liquidityMatrix);

        address addr1 = deployer.deploy(app1, version1);
        address addr2 = deployer.deploy(app1, version2);
        address addr3 = deployer.deploy(app2, version1);

        vm.stopPrank();

        // All addresses should be different
        assertTrue(addr1 != addr2);
        assertTrue(addr1 != addr3);
        assertTrue(addr2 != addr3);

        // All should have contract code
        assertTrue(addr1.code.length > 0);
        assertTrue(addr2.code.length > 0);
        assertTrue(addr3.code.length > 0);

        // Verify correct initialization
        assertEq(LocalAppChronicle(addr1).app(), app1);
        assertEq(LocalAppChronicle(addr1).version(), version1);
        assertEq(LocalAppChronicle(addr2).app(), app1);
        assertEq(LocalAppChronicle(addr2).version(), version2);
        assertEq(LocalAppChronicle(addr3).app(), app2);
        assertEq(LocalAppChronicle(addr3).version(), version1);
    }

    function test_deploy_sameParamsTwice_shouldRevert() public {
        vm.startPrank(liquidityMatrix);

        // First deployment should succeed
        deployer.deploy(app, VERSION);

        // Second deployment with same parameters should revert (Create2 collision)
        vm.expectRevert();
        deployer.deploy(app, VERSION);

        vm.stopPrank();
    }

    function test_deploy_revertUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(ILocalAppChronicleDeployer.Forbidden.selector);
        deployer.deploy(app, VERSION);
    }

    function test_deploy_onlyLiquidityMatrixCanCall() public {
        // LiquidityMatrix should be able to deploy
        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, VERSION);
        assertTrue(deployedAddress.code.length > 0);

        // Different app/version for next test
        address differentApp = makeAddr("differentApp");

        // Unauthorized users should not be able to deploy
        vm.prank(unauthorizedUser);
        vm.expectRevert(ILocalAppChronicleDeployer.Forbidden.selector);
        deployer.deploy(differentApp, VERSION);

        vm.prank(app);
        vm.expectRevert(ILocalAppChronicleDeployer.Forbidden.selector);
        deployer.deploy(differentApp, VERSION + 1);
    }

    function testFuzz_deploy_onlyLiquidityMatrix(address caller, address _app, uint256 _version) public {
        vm.assume(caller != liquidityMatrix);
        vm.assume(_app != address(0));
        vm.assume(_version <= type(uint256).max);

        vm.prank(caller);
        vm.expectRevert(ILocalAppChronicleDeployer.Forbidden.selector);
        deployer.deploy(_app, _version);
    }

    /*//////////////////////////////////////////////////////////////
                        DETERMINISTIC BEHAVIOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deterministicDeployment() public {
        // Deploy with one deployer
        LocalAppChronicleDeployer deployer1 = new LocalAppChronicleDeployer(liquidityMatrix);

        // Deploy with another deployer (same liquidityMatrix)
        LocalAppChronicleDeployer deployer2 = new LocalAppChronicleDeployer(liquidityMatrix);

        // Predicted addresses should be different (different deployer contracts)
        address pred1 = deployer1.computeAddress(app, VERSION);
        address pred2 = deployer2.computeAddress(app, VERSION);
        assertTrue(pred1 != pred2);

        // But each should be deterministic
        assertEq(pred1, deployer1.computeAddress(app, VERSION));
        assertEq(pred2, deployer2.computeAddress(app, VERSION));
    }

    function test_saltGeneration() public {
        // Test that salt is generated correctly
        bytes32 expectedSalt = keccak256(abi.encodePacked(app, VERSION));

        // We can't directly access the salt, but we can verify through address computation
        bytes memory bytecode =
            abi.encodePacked(type(LocalAppChronicle).creationCode, abi.encode(liquidityMatrix, app, VERSION));

        address expectedAddress = Create2.computeAddress(expectedSalt, keccak256(bytecode), address(deployer));
        address computedAddress = deployer.computeAddress(app, VERSION);

        assertEq(computedAddress, expectedAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deploy_withZeroApp() public {
        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(address(0), VERSION);

        assertTrue(deployedAddress.code.length > 0);
        LocalAppChronicle chronicle = LocalAppChronicle(deployedAddress);
        assertEq(chronicle.app(), address(0));
    }

    function test_deploy_withMaxVersion() public {
        uint256 maxVersion = type(uint256).max;

        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, maxVersion);

        assertTrue(deployedAddress.code.length > 0);
        LocalAppChronicle chronicle = LocalAppChronicle(deployedAddress);
        assertEq(chronicle.version(), maxVersion);
    }

    function test_deploy_withVersionZero() public {
        uint256 versionZero = 0;

        vm.prank(liquidityMatrix);
        address deployedAddress = deployer.deploy(app, versionZero);

        assertTrue(deployedAddress.code.length > 0);
        LocalAppChronicle chronicle = LocalAppChronicle(deployedAddress);
        assertEq(chronicle.version(), versionZero);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployedChronicleWorksCorrectly() public {
        // Deploy a chronicle
        vm.prank(liquidityMatrix);
        address chronicleAddress = deployer.deploy(app, VERSION);

        LocalAppChronicle chronicle = LocalAppChronicle(chronicleAddress);

        // Test basic functionality of the deployed chronicle
        assertEq(chronicle.liquidityMatrix(), liquidityMatrix);
        assertEq(chronicle.app(), app);
        assertEq(chronicle.version(), VERSION);

        // Test initial state
        assertEq(chronicle.getTotalLiquidity(), 0);
        assertEq(chronicle.getLiquidity(makeAddr("testAccount")), 0);
        assertTrue(chronicle.getLiquidityRoot() != bytes32(0)); // Should have empty tree root
        assertTrue(chronicle.getDataRoot() != bytes32(0)); // Should have empty tree root
    }

    function test_multipleDeployersIndependence() public {
        address matrix1 = makeAddr("matrix1");
        address matrix2 = makeAddr("matrix2");

        LocalAppChronicleDeployer deployer1 = new LocalAppChronicleDeployer(matrix1);
        LocalAppChronicleDeployer deployer2 = new LocalAppChronicleDeployer(matrix2);

        // Deploy from both deployers
        vm.prank(matrix1);
        address chronicle1 = deployer1.deploy(app, VERSION);

        vm.prank(matrix2);
        address chronicle2 = deployer2.deploy(app, VERSION);

        // Should be different addresses
        assertTrue(chronicle1 != chronicle2);

        // Each should have correct liquidityMatrix
        assertEq(LocalAppChronicle(chronicle1).liquidityMatrix(), matrix1);
        assertEq(LocalAppChronicle(chronicle2).liquidityMatrix(), matrix2);
    }

    /*//////////////////////////////////////////////////////////////
                            GAS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gasUsage_deploy() public {
        uint256 gasBefore = gasleft();

        vm.prank(liquidityMatrix);
        deployer.deploy(app, VERSION);

        uint256 gasUsed = gasBefore - gasleft();

        // Updated static thresholds for current runtime size
        assertTrue(gasUsed < 2_300_000);
        assertTrue(gasUsed > 1_900_000); // Substantial due to contract creation
    }

    function test_gasUsage_computeAddress() public view {
        uint256 gasBefore = gasleft();

        deployer.computeAddress(app, VERSION);

        uint256 gasUsed = gasBefore - gasleft();

        // Address computation should be relatively cheap
        assertTrue(gasUsed < 50_000);
    }
}
