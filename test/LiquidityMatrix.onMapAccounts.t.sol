// SPDX-License-Identifier: BUSL
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { LiquidityMatrix } from "src/LiquidityMatrix.sol";
import { LocalAppChronicleDeployer } from "src/chronicles/LocalAppChronicleDeployer.sol";
import { RemoteAppChronicleDeployer } from "src/chronicles/RemoteAppChronicleDeployer.sol";
import { ILiquidityMatrix } from "src/interfaces/ILiquidityMatrix.sol";
import { ILiquidityMatrixHook } from "src/interfaces/ILiquidityMatrixHook.sol";

contract AppWithHook is ILiquidityMatrixHook {
    struct MapAccountsCall {
        bytes32 chainUID;
        address[] remoteAccounts;
        address[] localAccounts;
    }

    MapAccountsCall[] internal mapAccountsCalls;
    address public immutable liquidityMatrix;

    constructor(address _liquidityMatrix) {
        liquidityMatrix = _liquidityMatrix;
    }

    function getMapAccountsCallCount() external view returns (uint256) {
        return mapAccountsCalls.length;
    }

    function getMapAccountsCall(uint256 index) external view returns (bytes32, address[] memory, address[] memory) {
        MapAccountsCall memory call = mapAccountsCalls[index];
        return (call.chainUID, call.remoteAccounts, call.localAccounts);
    }

    function onMapAccounts(bytes32 chainUID, address[] memory remoteAccounts, address[] memory localAccounts)
        external
        override
    {
        require(msg.sender == liquidityMatrix, "Only LiquidityMatrix can call");
        mapAccountsCalls.push(MapAccountsCall(chainUID, remoteAccounts, localAccounts));
    }

    function onSettleLiquidity(bytes32, uint256, uint64, address) external override { }
    function onSettleTotalLiquidity(bytes32, uint256, uint64) external override { }
    function onSettleData(bytes32, uint256, uint64, bytes32) external override { }

    // ILiquidityMatrixAccountMapper implementation
    function shouldMapAccounts(bytes32, address, address) external pure virtual returns (bool) {
        return true; // Always approve mapping for this test
    }
}

contract LiquidityMatrixOnMapAccountsTest is Test {
    LiquidityMatrix public liquidityMatrix;
    LocalAppChronicleDeployer public localDeployer;
    RemoteAppChronicleDeployer public remoteDeployer;
    AppWithHook public app;

    address public owner = makeAddr("owner");
    address public settler = makeAddr("settler");

    function setUp() public {
        vm.startPrank(owner);

        // Deploy LiquidityMatrix and deployers
        liquidityMatrix = new LiquidityMatrix(owner, 1, address(0), address(0));
        localDeployer = new LocalAppChronicleDeployer(address(liquidityMatrix));
        remoteDeployer = new RemoteAppChronicleDeployer(address(liquidityMatrix));

        liquidityMatrix.updateLocalAppChronicleDeployer(address(localDeployer));
        liquidityMatrix.updateRemoteAppChronicleDeployer(address(remoteDeployer));

        // Whitelist settler
        liquidityMatrix.updateSettlerWhitelisted(settler, true);

        vm.stopPrank();

        // Deploy app with hook support
        app = new AppWithHook(address(liquidityMatrix));

        // Register app with hooks enabled
        vm.prank(address(app));
        liquidityMatrix.registerApp(false, true, settler); // useHook = true
    }

    function test_onMapAccounts_calledDuringAccountMapping() public {
        // Prepare mapping data
        bytes32 chainUID = bytes32(uint256(1));
        address[] memory remotes = new address[](3);
        address[] memory locals = new address[](3);

        remotes[0] = makeAddr("remote1");
        remotes[1] = makeAddr("remote2");
        remotes[2] = makeAddr("remote3");

        locals[0] = makeAddr("local1");
        locals[1] = makeAddr("local2");
        locals[2] = makeAddr("local3");

        // Call onReceiveMapRemoteAccountRequests as the contract itself (simulating internal call)
        vm.prank(address(liquidityMatrix));
        liquidityMatrix.onReceiveMapRemoteAccountRequests(chainUID, address(app), remotes, locals);

        // Verify onMapAccounts was called once with all mappings
        assertEq(app.getMapAccountsCallCount(), 1, "Should have called onMapAccounts once");

        // Verify the call had correct parameters
        (bytes32 callChainUID, address[] memory callRemotes, address[] memory callLocals) = app.getMapAccountsCall(0);
        assertEq(callChainUID, chainUID, "Chain UID mismatch");
        assertEq(callRemotes.length, 3, "Remote accounts array length mismatch");
        assertEq(callLocals.length, 3, "Local accounts array length mismatch");

        for (uint256 i = 0; i < 3; i++) {
            assertEq(callRemotes[i], remotes[i], "Remote account mismatch");
            assertEq(callLocals[i], locals[i], "Local account mismatch");
        }
    }

    function test_onMapAccounts_notCalledWhenHooksDisabled() public {
        // Register another app without hooks
        AppWithHook appNoHooks = new AppWithHook(address(liquidityMatrix));
        vm.prank(address(appNoHooks));
        liquidityMatrix.registerApp(false, false, settler); // useHook = false

        // Prepare mapping data
        bytes32 chainUID = bytes32(uint256(1));
        address[] memory remotes = new address[](1);
        address[] memory locals = new address[](1);

        remotes[0] = makeAddr("remote");
        locals[0] = makeAddr("local");

        // Call onReceiveMapRemoteAccountRequests
        vm.prank(address(liquidityMatrix));
        liquidityMatrix.onReceiveMapRemoteAccountRequests(chainUID, address(appNoHooks), remotes, locals);

        // Verify onMapAccounts was NOT called (hooks disabled)
        assertEq(appNoHooks.getMapAccountsCallCount(), 0, "Should not have called onMapAccounts");

        // Verify mapping still occurred
        assertEq(
            liquidityMatrix.getMappedAccount(address(appNoHooks), chainUID, remotes[0]),
            locals[0],
            "Mapping should still be created"
        );
    }

    function test_onMapAccounts_calledOnlyForApprovedMappings() public {
        // Deploy app that selectively approves mappings
        SelectiveAppWithHook selectiveApp = new SelectiveAppWithHook(address(liquidityMatrix));
        vm.prank(address(selectiveApp));
        liquidityMatrix.registerApp(false, true, settler); // useHook = true

        // Prepare mapping data - 4 mappings, only even indices approved
        bytes32 chainUID = bytes32(uint256(1));
        address[] memory remotes = new address[](4);
        address[] memory locals = new address[](4);

        for (uint256 i = 0; i < 4; i++) {
            remotes[i] = makeAddr(string(abi.encodePacked("remote", i)));
            locals[i] = makeAddr(string(abi.encodePacked("local", i)));
        }

        // Call onReceiveMapRemoteAccountRequests
        vm.prank(address(liquidityMatrix));
        liquidityMatrix.onReceiveMapRemoteAccountRequests(chainUID, address(selectiveApp), remotes, locals);

        // Count how many mappings should be approved (even last byte)
        uint256 expectedCallCount = 0;
        for (uint256 i = 0; i < 4; i++) {
            if (uint8(uint160(remotes[i])) % 2 == 0) {
                expectedCallCount++;
            }
        }

        // Verify onMapAccounts was called only for approved mappings
        assertEq(
            selectiveApp.getMapAccountsCallCount(),
            expectedCallCount,
            "Should have called onMapAccounts only for approved mappings"
        );

        // Verify the single call contains all approved mappings
        assertEq(selectiveApp.getMapAccountsCallCount(), 1, "Should have called onMapAccounts once");
        (bytes32 callChainUID, address[] memory callRemotes, address[] memory callLocals) =
            selectiveApp.getMapAccountsCall(0);

        assertEq(callChainUID, chainUID, "Chain UID mismatch");
        assertEq(callRemotes.length, expectedCallCount, "Remote accounts array length mismatch");
        assertEq(callLocals.length, expectedCallCount, "Local accounts array length mismatch");

        // Verify each mapping in the arrays was approved
        for (uint256 i = 0; i < callRemotes.length; i++) {
            assertTrue(uint8(uint160(callRemotes[i])) % 2 == 0, "Hook called for unapproved mapping");
            // Find the corresponding local
            bool found = false;
            for (uint256 j = 0; j < 4; j++) {
                if (remotes[j] == callRemotes[i]) {
                    assertEq(callLocals[i], locals[j], "Local account mismatch");
                    found = true;
                    break;
                }
            }
            assertTrue(found, "Hook called for unknown remote");
        }
    }
}

contract SelectiveAppWithHook is AppWithHook {
    constructor(address _liquidityMatrix) AppWithHook(_liquidityMatrix) { }

    // Override to only approve even-indexed mappings
    function shouldMapAccounts(bytes32, address remote, address) external pure override returns (bool) {
        // Simple logic: approve if last byte of remote address is even
        return uint8(uint160(remote)) % 2 == 0;
    }
}
