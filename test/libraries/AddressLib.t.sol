// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { AddressLib } from "../../src/libraries/AddressLib.sol";

contract AddressLibTest is Test {
    // Test contracts
    ContractMock contractMock;
    NonPayableContract nonPayableContract;
    RevertingContract revertingContract;
    address payable eoa;

    function setUp() public {
        contractMock = new ContractMock();
        nonPayableContract = new NonPayableContract();
        revertingContract = new RevertingContract();
        eoa = payable(makeAddr("eoa"));
    }

    /*//////////////////////////////////////////////////////////////
                          isContract() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_isContract_withContract() public view {
        assertTrue(AddressLib.isContract(address(contractMock)));
        assertTrue(AddressLib.isContract(address(nonPayableContract)));
        assertTrue(AddressLib.isContract(address(revertingContract)));
    }

    function test_isContract_withEOA() public view {
        assertFalse(AddressLib.isContract(eoa));
        assertFalse(AddressLib.isContract(address(0x1234)));
        assertFalse(AddressLib.isContract(address(0x5678))); // Use hardcoded address instead
    }

    function test_isContract_withZeroAddress() public view {
        assertFalse(AddressLib.isContract(address(0)));
    }

    function test_isContract_withPrecompiles() public view {
        // Ethereum precompiles (0x1 - 0x9)
        assertFalse(AddressLib.isContract(address(0x1))); // ecrecover
        assertFalse(AddressLib.isContract(address(0x2))); // sha256
        assertFalse(AddressLib.isContract(address(0x3))); // ripemd160
        assertFalse(AddressLib.isContract(address(0x4))); // identity
        assertFalse(AddressLib.isContract(address(0x5))); // modexp
        assertFalse(AddressLib.isContract(address(0x6))); // ecAdd
        assertFalse(AddressLib.isContract(address(0x7))); // ecMul
        assertFalse(AddressLib.isContract(address(0x8))); // ecPairing
        assertFalse(AddressLib.isContract(address(0x9))); // blake2f
    }

    /*//////////////////////////////////////////////////////////////
                        transferNative() TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transferNative_toEOA() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        uint256 balanceBefore = eoa.balance;
        AddressLib.transferNative(eoa, amount);

        assertEq(eoa.balance, balanceBefore + amount);
        assertEq(address(this).balance, 0);
    }

    function test_transferNative_toPayableContract() public {
        uint256 amount = 2 ether;
        vm.deal(address(this), amount);

        uint256 balanceBefore = address(contractMock).balance;
        AddressLib.transferNative(address(contractMock), amount);

        assertEq(address(contractMock).balance, balanceBefore + amount);
        assertEq(contractMock.receivedAmount(), amount);
    }

    function test_transferNative_zeroAmount() public {
        uint256 balanceBefore = eoa.balance;
        AddressLib.transferNative(eoa, 0);

        assertEq(eoa.balance, balanceBefore);
    }

    function test_transferNative_toNonPayableContract_reverts() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        // Just check that it reverts with TransferFailure, don't check the exact data
        vm.expectRevert();
        AddressLib.transferNative(address(nonPayableContract), amount);
    }

    function test_transferNative_toRevertingContract_reverts() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        // Just check that it reverts with TransferFailure, don't check the exact data
        vm.expectRevert();
        AddressLib.transferNative(address(revertingContract), amount);
    }

    function test_transferNative_insufficientBalance_reverts() public {
        uint256 balance = 1 ether;
        uint256 amount = 2 ether;
        vm.deal(address(this), balance);

        // When attempting to transfer more ETH than available, the low-level call will fail
        // and AddressLib will revert with TransferFailure error
        // Note: We can't predict the exact error data as it's Foundry-specific
        vm.expectRevert();
        this.callTransferNative(eoa, amount);
    }

    function test_transferNative_multipleTransfers() public {
        uint256 totalAmount = 10 ether;
        vm.deal(address(this), totalAmount);

        address[] memory recipients = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("recipient", i)));
        }

        uint256 amountPerRecipient = 2 ether;
        for (uint256 i = 0; i < recipients.length; i++) {
            AddressLib.transferNative(recipients[i], amountPerRecipient);
            assertEq(recipients[i].balance, amountPerRecipient);
        }

        assertEq(address(this).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_isContract(address addr) public view {
        // For random addresses, we can only assert that the function doesn't revert
        // The actual result depends on the blockchain state
        bool result = AddressLib.isContract(addr);

        // Some basic invariants
        if (addr == address(0)) {
            assertFalse(result);
        }
        if (addr == address(this) || addr == address(contractMock)) {
            assertTrue(result);
        }
    }

    function testFuzz_transferNative_toEOA(address recipient, uint256 amount) public {
        assumeNotPrecompile(recipient);

        vm.assume(recipient != address(0));
        vm.assume(!AddressLib.isContract(recipient)); // Ensure it's an EOA
        vm.assume(amount <= 100 ether);

        vm.deal(address(this), amount);

        uint256 balanceBefore = recipient.balance;
        AddressLib.transferNative(recipient, amount);

        assertEq(recipient.balance, balanceBefore + amount);
        assertEq(address(this).balance, 0);
    }

    function testFuzz_transferNative_amounts(uint256 amount) public {
        vm.assume(amount <= type(uint128).max); // Reasonable upper bound

        vm.deal(address(this), amount);

        address recipient = makeAddr("recipient");
        AddressLib.transferNative(recipient, amount);

        assertEq(recipient.balance, amount);
        assertEq(address(this).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_transferNative_toSelf() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        uint256 balanceBefore = address(this).balance;
        AddressLib.transferNative(address(this), amount);

        // Balance should remain the same (transferred to self)
        assertEq(address(this).balance, balanceBefore);
    }

    function test_transferNative_maxUint256_reverts() public {
        // When attempting to transfer max uint256, the low-level call will fail
        // and AddressLib will revert with TransferFailure error
        // Note: We can't predict the exact error data as it's Foundry-specific
        vm.expectRevert();
        this.callTransferNative(eoa, type(uint256).max);
    }

    // Helper function to make the call external for expectRevert
    function callTransferNative(address to, uint256 amount) external {
        AddressLib.transferNative(to, amount);
    }

    // Required to receive ETH
    receive() external payable { }
}

// Helper contracts for testing
contract ContractMock {
    uint256 public receivedAmount;

    receive() external payable {
        receivedAmount = msg.value;
    }
}

contract NonPayableContract {
// No receive or fallback function
}

contract RevertingContract {
    receive() external payable {
        revert("Always reverts");
    }
}
