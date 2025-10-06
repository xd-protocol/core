# Solidity Coding Conventions

This document outlines comprehensive coding conventions and development patterns for Solidity projects. Following these conventions ensures consistency, maintainability, and code quality across any Solidity codebase.

## Table of Contents

1. [File Organization](#file-organization)
2. [Solidity Code Structure](#solidity-code-structure)
3. [Interface Design Patterns](#interface-design-patterns)
4. [Implementation File Patterns](#implementation-file-patterns)
5. [Testing Conventions](#testing-conventions)
6. [Documentation Standards](#documentation-standards)
7. [Build & Development Commands](#build--development-commands)
8. [Naming Conventions](#naming-conventions)
9. [Security & Access Control Patterns](#security--access-control-patterns)

## File Organization

### Directory Structure

```
src/
├── interfaces/           # All contract interfaces
├── mixins/              # Abstract base contracts
├── libraries/          # Utility libraries

test/
├── mocks/              # Mock contracts for testing
├── helpers/            # Test helper contracts
└── *.t.sol            # Test files (unit tests)
└── *.integration.t.sol # Integration test files
```

### File Naming Conventions

1. **Contract Files**: `ContractName.sol`
2. **Interface Files**: `IContractName.sol`
3. **Test Files**: 
   - Unit tests: `ContractName.t.sol`
   - Integration tests: `ContractName.integration.t.sol`
   - Specific feature tests: `ContractName.featureName.t.sol`
4. **Mock Files**: `ContractNameMock.sol`
5. **Helper Files**: `ContractNameHelper.sol`

## Solidity Code Structure

### License and Pragma

```solidity
// SPDX-License-Identifier: BUSL  // or MIT for interfaces
pragma solidity ^0.8.28;
```

### Import Organization

Group imports in this order:
1. External libraries (OpenZeppelin, Solmate, LayerZero)
2. Internal interfaces
3. Internal libraries
4. Internal mixins/base contracts

```solidity
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { IMyContract } from "./interfaces/IMyContract.sol";
import { MathLib } from "./libraries/MathLib.sol";
import { BaseContract } from "./mixins/BaseContract.sol";
```

### Using Statements

Place `using` statements immediately after contract declaration:

```solidity
contract MyContract is ReentrancyGuard, Ownable, IMyContract {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
```

## Interface Design Patterns

### Standard Section Order for Interface Files

```solidity
interface IContractName {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    
    // Structs, enums used by interface functions
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    // All custom errors for the contract
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    // All events emitted by the contract
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    // Subdivided by category based on your contract's functionality:
    // - CORE VIEW FUNCTIONS
    // - CONFIGURATION VIEW FUNCTIONS
    // - STATE VIEW FUNCTIONS
    
    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/
    
    // State-changing functions subdivided by category:
    // - CORE LOGIC
    // - CONFIGURATION LOGIC
    // - ADMINISTRATIVE LOGIC
}
```

### Interface Patterns

- All events and errors should be defined in interfaces, not implementation files
- Functions should be grouped by logical functionality
- Include comprehensive NatSpec documentation
- Use consistent naming: `VIEW FUNCTIONS` for read-only, `LOGIC` for state-changing

## Implementation File Patterns

### Standard Section Order for Implementation Files

```solidity
contract ContractName is BaseContracts, Interfaces {
    using LibraryName for Type;
    
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    
    // Structs, enums, and custom types
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    // State variables, constants, immutables grouped logically
    
    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    // Access control and validation modifiers
    
    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    // Contract initialization
    
    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    // Often subdivided by category based on functionality:
    // - CORE VIEW FUNCTIONS
    // - CONFIGURATION VIEW FUNCTIONS
    // - STATE VIEW FUNCTIONS
    
    /*//////////////////////////////////////////////////////////////
                                LOGIC
    //////////////////////////////////////////////////////////////*/
    
    // State-changing functions often subdivided by category:
    // - CORE LOGIC
    // - CONFIGURATION LOGIC
    // - ADMINISTRATIVE LOGIC
    
    /*//////////////////////////////////////////////////////////////
                        INTERFACE IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/
    
    // Functions implementing specific interfaces:
    // - ICallback IMPLEMENTATION
    // - IHook IMPLEMENTATION
}
```

### Implementation Patterns

- Events and errors should be defined in interfaces, not implementation files
- Public functions should be external unless used internally
- Functions prefixed with `_` should be internal/private
- State variables should be grouped logically in STORAGE section
- Constructor must handle all required initialization

## Testing Conventions

### Test File Structure

Test files follow a consistent organizational pattern using comment blocks:

```solidity
contract ContractNameTest is TestHelper {
    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public override {
        // Test setup logic
    }
    
    /*//////////////////////////////////////////////////////////////
                        functionName() TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_functionName() public {
        // Basic functionality test
    }
    
    function test_functionName_specificScenario() public {
        // Specific scenario or edge case
    }
    
    function test_functionName_revertCondition() public {
        // Tests for revert conditions
    }
    
    function testFuzz_functionName(params) public {
        // Fuzz tests
    }
}
```

### Test Organization Patterns

1. **Unit Tests** (`ContractName.t.sol`):
   - Grouped by individual function tests
   - Each section tests a specific contract function
   - Includes both success and failure cases

2. **Integration Tests** (`ContractName.integration.t.sol`):
   - Grouped by feature or scenario
   - Tests complex interactions between multiple components
   - Example sections: `PRODUCTION SCENARIO TESTS`, `EDGE CASE TESTS`

3. **Feature-Specific Tests** (`ContractName.feature.t.sol`):
   - Focus on specific features like callbacks, events, etc.

### Test Naming Conventions

- `test_functionName()` - Basic test case
- `test_functionName_specificScenario()` - Specific scenario or edge case
- `test_functionName_revertCondition()` - Tests for revert conditions
- `testFuzz_functionName(params)` - Fuzz tests

### Test Structure Within Sections

Each test section typically includes:
1. Basic functionality test
2. Edge cases
3. Revert conditions (prefixed with `test_functionName_revert`)
4. Fuzz tests when applicable

### Test Helper Patterns

- Helper functions placed at the end under `INTERNAL FUNCTIONS`
- Prefixed with underscore (e.g., `_setupTestEnvironment()`)
- Shared setup logic in dedicated helper contracts

## Documentation Standards

### NatSpec Documentation

All public/external functions must include comprehensive NatSpec:

```solidity
/**
 * @title ContractName
 * @notice Brief description of what the contract does
 * @dev Detailed implementation notes, architecture explanations
 * 
 * ## Architecture Overview:
 * - Bullet point explanations
 * - Key relationships
 * 
 * ## ASCII Diagrams:
 * Include when helpful for understanding complex relationships
 * 
 * ## Key Functionalities:
 * 1. **Feature Name**: Description
 * 2. **Another Feature**: Description
 */
```

### Function Documentation

```solidity
/**
 * @notice Brief description of what the function does
 * @dev Implementation details, side effects, requirements
 * @param paramName Description of the parameter
 * @return Description of return value
 */
function functionName(Type paramName) external returns (ReturnType) {
    // Implementation
}
```

### Architectural Documentation

Major contracts should include:
- ASCII diagrams showing relationships
- Detailed architecture explanations
- Key functionalities breakdown
- Usage patterns and flows

## Build & Development Commands

### Building

```bash
# Build all contracts
make build

# Build specific contracts or directories
make build ARGS="src/"
make build ARGS="src/MyContract.sol"

# Clean build artifacts
make clean

# Format code using forge fmt
make fmt
make fmt ARGS="src/"
```

### Testing

```bash
# Run all tests
make test

# Run tests with verbosity (-vv)
make test-v

# Run tests with gas reporting
make test-gas

# Run specific test file
make test ARGS="test/MyTest.t.sol"

# Run tests matching pattern
make test ARGS="--match-test testFoo"
make test ARGS="--match-contract Foo"

# Run specific tests with verbosity
make test-v ARGS="--match-test testFoo"

# Run specific tests with gas report
make test-gas ARGS="--match-test testFoo"
```

### Development Setup

```bash
# Setup development environment (installs git hooks)
make setup

# Install git pre-commit hooks
make install-hooks

# Deploy to local network
make deploy-local
```

## Naming Conventions

### Variables and Functions

- **camelCase** for function names and local variables
- **snake_case** for private/internal storage variables with leading underscore
- **UPPER_SNAKE_CASE** for constants
- **PascalCase** for contract names, structs, enums

### Specific Patterns

```solidity
// Storage variables (internal/private)
mapping(address => bool) internal _isAuthorized;
uint256[] internal _items;

// Constants
uint8 constant STATUS_ACTIVE = 1;
uint16 internal constant MAX_ITEMS = 1000;

// Function parameters and local variables
function updateBalance(address account, uint256 amount) external {
    uint256 currentBalance = _getCurrentBalance(account);
}
```

### Access Control Naming

- Functions with access control: clear verb indicating the action
- Modifiers: `onlyOwner`, `onlyAdmin`, `onlyAuthorized`
- Boolean variables: `is`, `has`, `can`, `should` prefixes


## Security & Access Control Patterns

### Access Control Implementation

```solidity
// Modifier pattern
modifier onlyAuthorized() {
    if (!_isAuthorized[msg.sender]) revert Unauthorized();
    _;
}

// Whitelisting pattern
mapping(address => bool) internal _isAuthorized;

function updateAuthorization(address account, bool authorized) external onlyOwner {
    _isAuthorized[account] = authorized;
    emit AuthorizationUpdated(account, authorized);
}
```

### Constructor Best Practices

Ensure constructors handle all required initialization:

```solidity
constructor(
    string memory _name,
    address _registry,
    address _owner,
    address _admin  // Must be authorized
) Ownable(_owner) {
    name = _name;
    registry = _registry;
    
    // Initialize with required admin
    _isAuthorized[_admin] = true;
    emit AuthorizationUpdated(_admin, true);
}
```

### Error Handling

- Custom errors defined in interfaces
- Meaningful error names: `Unauthorized`, `InvalidInput`, `InsufficientBalance`
- Consistent error handling patterns


## Additional Development Patterns

### Hook/Callback System Implementation

```solidity
// Hook failures are caught and emitted as events, don't revert main transaction
try ICallback(callback).onAction(from, to, amount, data) {
    // Callback executed successfully
} catch (bytes memory reason) {
    emit CallbackFailed(callback, reason);
}
```

### Library Usage Patterns

```solidity
// Consistent library usage
using SafeMath for uint256;
using Address for address;
using EnumerableSet for EnumerableSet.AddressSet;
using Strings for uint256;
```

### Test Setup Patterns

```solidity
// Consistent test setup requirements
function setUp() public override {
    super.setUp();
    
    // 1. Deploy contracts
    // 2. Set up initial state
    // 3. Configure permissions
    // 4. Initialize test data
    // 5. Set up mocks and helpers
}
```

### Common Issues and Solutions

- `Unauthorized`: Check access control and permissions
- `InvalidInput`: Validate input parameters and ranges
- `InsufficientBalance`: Ensure adequate balance before operations
- `ContractNotInitialized`: Complete initialization before usage
- `OperationNotAllowed`: Verify contract state and conditions

---

## Summary

Following these conventions ensures:
- **Consistency**: Uniform code structure across the entire codebase
- **Maintainability**: Clear organization makes code easier to understand and modify
- **Security**: Established patterns for access control and error handling
- **Testing**: Comprehensive test coverage with consistent organization
- **Documentation**: Clear architectural understanding through standardized documentation

All developers working on Solidity projects should adhere to these conventions to maintain code quality and team productivity.
