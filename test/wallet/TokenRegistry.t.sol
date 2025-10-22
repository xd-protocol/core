// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TokenRegistry } from "../../src/wallet/TokenRegistry.sol";
import { ITokenRegistry } from "../../src/interfaces/ITokenRegistry.sol";

contract TokenRegistryTest is Test {
    TokenRegistry public registry;

    address owner = makeAddr("owner");
    address token1 = makeAddr("token1");
    address token2 = makeAddr("token2");
    address attacker = makeAddr("attacker");
    address target1 = makeAddr("target1");
    address target2 = makeAddr("target2");

    event TokenRegistered(address indexed token, bool status);
    event BlacklistTargetSet(address indexed target, bool blacklisted);
    event BlacklistSelectorSet(bytes4 indexed selector, bool blacklisted);

    function setUp() public {
        registry = new TokenRegistry(owner);
    }

    /*//////////////////////////////////////////////////////////////
                        registerToken() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registerToken() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TokenRegistered(token1, true);
        registry.registerToken(token1, true);

        assertTrue(registry.isRegistered(token1));
        assertTrue(registry.registeredTokens(token1));
    }

    function test_registerToken_unregister() public {
        // Register first
        vm.prank(owner);
        registry.registerToken(token1, true);
        assertTrue(registry.isRegistered(token1));

        // Unregister
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TokenRegistered(token1, false);
        registry.registerToken(token1, false);

        assertFalse(registry.isRegistered(token1));
    }

    function test_registerToken_revertNotOwner() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.registerToken(token1, true);
    }

    /*//////////////////////////////////////////////////////////////
                    batchRegisterTokens() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_batchRegisterTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = attacker;

        bool[] memory statuses = new bool[](3);
        statuses[0] = true;
        statuses[1] = true;
        statuses[2] = false;

        vm.prank(owner);
        registry.batchRegisterTokens(tokens, statuses);

        assertTrue(registry.isRegistered(token1));
        assertTrue(registry.isRegistered(token2));
        assertFalse(registry.isRegistered(attacker));
    }

    function test_batchRegisterTokens_revertLengthMismatch() public {
        address[] memory tokens = new address[](2);
        bool[] memory statuses = new bool[](3);

        vm.prank(owner);
        vm.expectRevert(ITokenRegistry.LengthMismatch.selector);
        registry.batchRegisterTokens(tokens, statuses);
    }

    function test_batchRegisterTokens_revertNotOwner() public {
        address[] memory tokens = new address[](1);
        bool[] memory statuses = new bool[](1);

        vm.prank(attacker);
        vm.expectRevert();
        registry.batchRegisterTokens(tokens, statuses);
    }

    /*//////////////////////////////////////////////////////////////
                    setBlacklistedTargets() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setBlacklistedTargets() public {
        address[] memory targets = new address[](2);
        targets[0] = target1;
        targets[1] = target2;

        bool[] memory flags = new bool[](2);
        flags[0] = true;
        flags[1] = true;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BlacklistTargetSet(target1, true);
        vm.expectEmit(true, true, true, true);
        emit BlacklistTargetSet(target2, true);
        registry.setBlacklistedTargets(targets, flags);

        assertTrue(registry.isBlacklisted(target1, bytes4(0)));
        assertTrue(registry.isBlacklisted(target2, bytes4(0)));
    }

    function test_setBlacklistedTargets_unblacklist() public {
        // Blacklist first
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        vm.prank(owner);
        registry.setBlacklistedTargets(targets, flags);
        assertTrue(registry.isBlacklisted(target1, bytes4(0)));

        // Unblacklist
        flags[0] = false;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BlacklistTargetSet(target1, false);
        registry.setBlacklistedTargets(targets, flags);

        assertFalse(registry.isBlacklisted(target1, bytes4(0)));
    }

    function test_setBlacklistedTargets_revertLengthMismatch() public {
        address[] memory targets = new address[](2);
        bool[] memory flags = new bool[](3);

        vm.prank(owner);
        vm.expectRevert(ITokenRegistry.LengthMismatch.selector);
        registry.setBlacklistedTargets(targets, flags);
    }

    function test_setBlacklistedTargets_revertNotOwner() public {
        address[] memory targets = new address[](1);
        bool[] memory flags = new bool[](1);

        vm.prank(attacker);
        vm.expectRevert();
        registry.setBlacklistedTargets(targets, flags);
    }

    /*//////////////////////////////////////////////////////////////
                  setBlacklistedSelectors() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setBlacklistedSelectors() public {
        bytes4 selector1 = bytes4(keccak256("customFunction()"));
        bytes4 selector2 = bytes4(keccak256("anotherFunction()"));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = selector1;
        selectors[1] = selector2;

        bool[] memory flags = new bool[](2);
        flags[0] = true;
        flags[1] = true;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BlacklistSelectorSet(selector1, true);
        vm.expectEmit(true, true, true, true);
        emit BlacklistSelectorSet(selector2, true);
        registry.setBlacklistedSelectors(selectors, flags);

        assertTrue(registry.isBlacklisted(address(0), selector1));
        assertTrue(registry.isBlacklisted(address(0), selector2));
    }

    function test_setBlacklistedSelectors_unblacklist() public {
        bytes4 selector1 = bytes4(keccak256("customFunction()"));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector1;
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // Blacklist first
        vm.prank(owner);
        registry.setBlacklistedSelectors(selectors, flags);
        assertTrue(registry.isBlacklisted(address(0), selector1));

        // Unblacklist
        flags[0] = false;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BlacklistSelectorSet(selector1, false);
        registry.setBlacklistedSelectors(selectors, flags);

        assertFalse(registry.isBlacklisted(address(0), selector1));
    }

    function test_setBlacklistedSelectors_revertLengthMismatch() public {
        bytes4[] memory selectors = new bytes4[](2);
        bool[] memory flags = new bool[](3);

        vm.prank(owner);
        vm.expectRevert(ITokenRegistry.LengthMismatch.selector);
        registry.setBlacklistedSelectors(selectors, flags);
    }

    function test_setBlacklistedSelectors_revertNotOwner() public {
        bytes4[] memory selectors = new bytes4[](1);
        bool[] memory flags = new bool[](1);

        vm.prank(attacker);
        vm.expectRevert();
        registry.setBlacklistedSelectors(selectors, flags);
    }

    /*//////////////////////////////////////////////////////////////
                        isBlacklisted() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_isBlacklisted_target() public {
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        vm.prank(owner);
        registry.setBlacklistedTargets(targets, flags);

        // Any selector with blacklisted target should be blacklisted
        assertTrue(registry.isBlacklisted(target1, bytes4(0)));
        assertTrue(registry.isBlacklisted(target1, bytes4(keccak256("anyFunction()"))));
    }

    function test_isBlacklisted_selector() public {
        bytes4 selector1 = bytes4(keccak256("customFunction()"));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector1;
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        vm.prank(owner);
        registry.setBlacklistedSelectors(selectors, flags);

        // Any target with blacklisted selector should be blacklisted
        assertTrue(registry.isBlacklisted(address(0), selector1));
        assertTrue(registry.isBlacklisted(target1, selector1));
        assertTrue(registry.isBlacklisted(target2, selector1));
    }

    function test_isBlacklisted_both() public {
        // Setup blacklisted target
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bool[] memory targetFlags = new bool[](1);
        targetFlags[0] = true;

        // Setup blacklisted selector
        bytes4 selector1 = bytes4(keccak256("customFunction()"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector1;
        bool[] memory selectorFlags = new bool[](1);
        selectorFlags[0] = true;

        vm.startPrank(owner);
        registry.setBlacklistedTargets(targets, targetFlags);
        registry.setBlacklistedSelectors(selectors, selectorFlags);
        vm.stopPrank();

        // Both conditions trigger blacklist
        assertTrue(registry.isBlacklisted(target1, bytes4(0))); // target blacklisted
        assertTrue(registry.isBlacklisted(address(0), selector1)); // selector blacklisted
        assertTrue(registry.isBlacklisted(target1, selector1)); // both blacklisted
    }

    function test_isBlacklisted_notBlacklisted() public {
        // Nothing blacklisted
        assertFalse(registry.isBlacklisted(target1, bytes4(0)));
        assertFalse(registry.isBlacklisted(address(0), bytes4(keccak256("anyFunction()"))));
    }

    /*//////////////////////////////////////////////////////////////
                    DEFAULT BLACKLIST TESTS
    //////////////////////////////////////////////////////////////*/

    function test_defaultBlacklist_erc20Approvals() public {
        // ERC20 approval functions should be blacklisted by default
        assertTrue(registry.isBlacklisted(address(0), 0x095ea7b3)); // approve(address,uint256)
        assertTrue(registry.isBlacklisted(address(0), 0x39509351)); // increaseAllowance(address,uint256)
        assertTrue(registry.isBlacklisted(address(0), 0xa457c2d7)); // decreaseAllowance(address,uint256)
    }

    function test_defaultBlacklist_erc20Transfers() public {
        // ERC20 transfer functions should be blacklisted by default
        assertTrue(registry.isBlacklisted(address(0), 0xa9059cbb)); // transfer(address,uint256)
        assertTrue(registry.isBlacklisted(address(0), 0x23b872dd)); // transferFrom(address,address,uint256)
    }

    function test_defaultBlacklist_permits() public {
        // Permit functions should be blacklisted by default
        assertTrue(registry.isBlacklisted(address(0), 0xd505accf)); // permit(address,address,uint256,uint256,uint8,bytes32,bytes32)
        assertTrue(registry.isBlacklisted(address(0), 0x8fcbaf0c)); // DAI-style permit
    }

    function test_defaultBlacklist_eip3009() public {
        // EIP-3009 authorization functions should be blacklisted
        assertTrue(registry.isBlacklisted(address(0), 0xcf092995)); // transferWithAuthorization
        assertTrue(registry.isBlacklisted(address(0), 0x88b7ab63)); // receiveWithAuthorization
        assertTrue(registry.isBlacklisted(address(0), 0xb7b72899)); // cancelAuthorization
    }

    function test_defaultBlacklist_permit2() public {
        // Uniswap Permit2 functions should be blacklisted
        assertTrue(registry.isBlacklisted(address(0), 0x2b67b570)); // permit
        assertTrue(registry.isBlacklisted(address(0), 0x35f9eb42)); // permitBatch
        assertTrue(registry.isBlacklisted(address(0), 0x00089b7b)); // permitTransferFrom
    }

    function test_defaultBlacklist_erc721() public {
        // ERC721 functions should be blacklisted
        assertTrue(registry.isBlacklisted(address(0), 0xa22cb465)); // setApprovalForAll(address,bool)
        assertTrue(registry.isBlacklisted(address(0), 0x42842e0e)); // safeTransferFrom(address,address,uint256)
        assertTrue(registry.isBlacklisted(address(0), 0xb88d4fde)); // safeTransferFrom(address,address,uint256,bytes)
    }

    function test_defaultBlacklist_erc1155() public {
        // ERC1155 functions should be blacklisted
        assertTrue(registry.isBlacklisted(address(0), 0x2eb2c2d6)); // safeBatchTransferFrom
        assertTrue(registry.isBlacklisted(address(0), 0xf242432a)); // safeTransferFrom (ERC1155)
    }

    function test_defaultBlacklist_erc1363() public {
        // ERC1363 functions should be blacklisted
        assertTrue(registry.isBlacklisted(address(0), 0x1296ee62)); // transferAndCall(address,uint256)
        assertTrue(registry.isBlacklisted(address(0), 0x4000aea0)); // transferAndCall(address,uint256,bytes)
        assertTrue(registry.isBlacklisted(address(0), 0x3177029f)); // approveAndCall(address,uint256)
    }

    function test_defaultBlacklist_erc777() public {
        // ERC777 operator functions should be blacklisted
        assertTrue(registry.isBlacklisted(address(0), 0x959b8c3f)); // authorizeOperator(address)
        assertTrue(registry.isBlacklisted(address(0), 0xfad8b32a)); // revokeOperator(address)
        assertTrue(registry.isBlacklisted(address(0), 0x62ad1b83)); // operatorSend
    }

    function test_defaultBlacklist_multicall() public {
        // Multicall/aggregator functions should be blacklisted
        assertTrue(registry.isBlacklisted(address(0), 0xac9650d8)); // multicall(bytes[])
        assertTrue(registry.isBlacklisted(address(0), 0x5ae401dc)); // multicall(uint256,bytes[])
        assertTrue(registry.isBlacklisted(address(0), 0x252dba42)); // aggregate((address,bytes)[])
        assertTrue(registry.isBlacklisted(address(0), 0x82ad56cb)); // aggregate3
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_integration_blacklistOverridesRegistration() public {
        // Register a token
        vm.prank(owner);
        registry.registerToken(token1, true);
        assertTrue(registry.isRegistered(token1));

        // Blacklist the token address
        address[] memory targets = new address[](1);
        targets[0] = token1;
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        vm.prank(owner);
        registry.setBlacklistedTargets(targets, flags);

        // Token is still registered but blacklisted
        assertTrue(registry.isRegistered(token1));
        assertTrue(registry.isBlacklisted(token1, bytes4(0)));
    }

    function test_integration_canUnblacklistDefaultSelectors() public {
        // Default selector is blacklisted
        bytes4 approveSelector = 0x095ea7b3; // approve(address,uint256)
        assertTrue(registry.isBlacklisted(address(0), approveSelector));

        // Owner can unblacklist it
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = approveSelector;
        bool[] memory flags = new bool[](1);
        flags[0] = false;

        vm.prank(owner);
        registry.setBlacklistedSelectors(selectors, flags);

        // Now not blacklisted
        assertFalse(registry.isBlacklisted(address(0), approveSelector));
    }
}
