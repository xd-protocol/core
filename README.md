# xD Protocol Core Contracts

**xD Protocol** is a cross-chain liquidity and state management protocol that enables universal omnichain token functionality with reorg protection and chronicle-based versioning. This repository contains the core smart contracts that power xD Protocol's cross-chain token operations, liquidity tracking, and settlement mechanisms.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Core Contracts](#core-contracts)
- [Key Components](#key-components)
- [Security Features](#security-features)
- [Development & Testing](#development--testing)
- [Audit Information](#audit-information)

## Architecture Overview

xD Protocol implements a hub-and-spoke architecture where:

- **LiquidityMatrix** acts as the central ledger managing liquidity and data state across all chains
- **Chronicle contracts** provide versioned state management with reorg protection
- **Gateway system** handles cross-chain communication via LayerZero
- **Cross-chain tokens** (ERC20xD, WrappedERC20xD, NativexD) enable seamless transfers between chains
- **Hook system** provides extensibility for custom logic (dividends, vaults, etc.) - **moved to periphery repository**

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Chain A       │    │   Chain B       │    │   Chain C       │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ERC20xD Token│ │    │ │ERC20xD Token│ │    │ │ERC20xD Token│ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │LiquidityMtrx│ │    │ │LiquidityMtrx│ │    │ │LiquidityMtrx│ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │   Gateway   │ │    │ │   Gateway   │ │    │ │   Gateway   │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                           LayerZero Network
```

## Core Contracts

### Primary Contracts (31 source files total)

#### Central Ledger
- **`LiquidityMatrix.sol`** - Core ledger managing cross-chain liquidity and data state
- **`ILiquidityMatrix.sol`** - Primary interface with comprehensive view and state functions

#### Token Implementations  
- **`BaseERC20xD.sol`** - Abstract cross-chain ERC20 with hook system and settlement callbacks
- **`BaseERC20.sol`** - Base ERC20 implementation (permit functionality removed for security)
- **`ERC20xD.sol`** - Standard cross-chain token with mint/burn capabilities
- **`WrappedERC20xD.sol`** - Cross-chain wrapper for existing ERC20 tokens
- **`NativexD.sol`** - Cross-chain wrapper for native assets (ETH, etc.)

#### Chronicle System (Version Management)
- **`LocalAppChronicle.sol`** - Manages local chain state for apps at specific versions
- **`RemoteAppChronicle.sol`** - Manages remote chain state with settlement tracking
- **Chronicle Deployers** - Factory contracts for deterministic chronicle deployment

#### Cross-Chain Communication
- **`LayerZeroGateway.sol`** - LayerZero-based gateway for cross-chain messaging and reads

#### Libraries
- **`MerkleTreeLib.sol`** - Optimized Merkle tree operations for state proofs
- **`SnapshotsLib.sol`** - Time-based state snapshots with binary search
- **`AddressLib.sol`** - Native asset transfer utilities
- **`ArrayLib.sol`** - Sorted array operations

#### Hook System
- **`BaseERC20xDHook.sol`** - Abstract base for implementing token hooks
- **`IERC20xDHook.sol`** - Interface for extensible token callbacks
- **Note**: Concrete hook implementations moved to separate periphery repository

## Key Components

### 1. LiquidityMatrix
The central ledger that maintains:
- **Hierarchical Merkle Trees**: Top-level trees aggregating app-specific trees
- **Chronicle Registry**: Maps apps to their local/remote chronicles by version
- **Settler Whitelist**: Controls who can process cross-chain settlements
- **Version Management**: Tracks blockchain reorgs and maintains isolated state
- **Account Mapping**: Maps accounts between chains for cross-chain operations
- **Remote Data Access**: Historical data queries with `getRemote*` prefix functions

**Critical Functions for Auditors:**
```solidity
// State modification - requires proper access control
function updateLocalLiquidity(address account, int256 liquidity) external;
function updateLocalData(bytes32 key, bytes memory value) external;

// Settlement functions - requires whitelisted settler
function settleLiquidity(SettleLiquidityParams calldata params) external;
function settleData(SettleDataParams calldata params) external;

// Version management - only owner
function addVersion(uint64 timestamp) external;

// Remote state queries - historical access across reorgs
function getRemoteLiquidityAt(address app, bytes32 chainUID, address account, uint64 timestamp) external view;
function getRemoteDataAt(address app, bytes32 chainUID, bytes32 key, uint64 timestamp) external view;
```

### 2. Chronicle System
Provides **reorg protection** through versioned state management:

- **LocalAppChronicle**: Manages local state, updates parent LiquidityMatrix trees
- **RemoteAppChronicle**: Processes settlements from remote chains, tracks finalization
- **Version Isolation**: Each version maintains separate chronicle contracts
- **Historical Access**: Queries automatically route to correct version based on timestamp

**Access Control Pattern:**
```solidity
modifier onlyAppOrLiquidityMatrix() {
    if (msg.sender != app && msg.sender != address(liquidityMatrix)) {
        revert Forbidden();
    }
    _;
}
```

### 3. Cross-Chain Tokens
All tokens inherit from `BaseERC20xD` which provides:

- **Cross-Chain Transfers**: Via `transfer()` with cross-chain parameters
- **Pending Transfer Management**: Tracks transfers awaiting settlement
- **Hook System**: Extensible callback system for custom logic
- **Settlement Callbacks**: Implements `ILiquidityMatrixHook` for state updates
- **Security Enhancement**: Removed EIP-2612 permit functionality to reduce attack surface

**Critical Transfer Logic:**
```solidity
function transfer(
    address to,
    uint256 amount,
    bytes calldata callData,
    uint256 value,
    bytes calldata data
) external payable;
```

### 4. Hook System
Provides extensibility through callback interfaces:

- **`IERC20xDHook`**: Token-level hooks for transfers, settlements, account mapping
- **`ILiquidityMatrixHook`**: Settlement notification hooks
- **Hook Failure Handling**: Failed hooks emit events but don't revert transactions
- **Separation of Concerns**: Concrete implementations moved to periphery repository

## Security Features

### 1. Reorg Protection
- **Chronicle Versioning**: Separate state containers for each potential chain fork
- **Timestamp-Based Isolation**: State queries automatically route to correct version
- **Historical Access**: Previous versions remain accessible after reorgs
- **Version-Aware Queries**: `getRemote*` functions support historical data access

### 2. Access Control
- **Settler Whitelist**: Only approved settlers can process cross-chain updates
- **App Registration**: Apps must register before tracking state
- **Owner Controls**: Critical functions (version management, settler whitelist) restricted to owner
- **Simplified Modifiers**: Removed unused `onlyAppOrMatrix` modifier for clarity

### 3. State Integrity
- **Merkle Tree Validation**: All state changes update cryptographic trees
- **Settlement Tracking**: Remote settlements tracked until both liquidity and data finalized
- **Atomic Operations**: State updates are atomic within each function call
- **Data Fetching**: Hook settlements now fetch data directly from LiquidityMatrix

### 4. Cross-Chain Security
- **Trust-Based Settlement**: Current implementation trusts whitelisted settlers (no proof verification)
- **Hook Failure Isolation**: Failed hook calls don't compromise core operations
- **Gateway Abstraction**: Pluggable gateway system allows multiple bridge providers
- **Reduced Attack Surface**: Removed permit functionality from base ERC20 implementation

## Development & Testing

### Build & Test Commands
```bash
# Build contracts
make build

# Run all tests (294 tests across 11 suites)
make test

# Run specific test patterns
make test ARGS="--match-test testFuzz_*"
make test ARGS="--match-contract LiquidityMatrix"

# Format code
make fmt

# Gas reporting
make test-gas
```

### Test Coverage
- **294 total tests** across core functionality - all passing
- **Integration tests** for multi-chain scenarios and reorg handling
- **Fuzz tests** for edge cases and invariants
- **Hook system tests** for extensibility and failure handling
- **Reorg scenario tests** for version management and historical access

### Key Test Files (24 test files total)
```
test/
├── LiquidityMatrix.t.sol              # Core ledger unit tests
├── LiquidityMatrix.integration.t.sol   # Multi-chain scenarios & reorg tests
├── ERC20xD.t.sol                      # Standard token tests  
├── WrappedERC20xD.t.sol              # Wrapper token tests
├── NativexD.t.sol                     # Native asset tests
├── mixins/BaseERC20xD.hooks.t.sol     # Hook system tests
└── libraries/                         # Library unit tests
    ├── MerkleTreeLib.t.sol           # Merkle tree operations
    ├── SnapshotsLib.t.sol            # Time-based snapshots
    ├── AddressLib.t.sol              # Native transfers
    └── ArrayLib.t.sol                # Sorted arrays
```

## Audit Information

### Audit Scope
**Primary contracts for security review:**
1. `LiquidityMatrix.sol` - Central ledger with settlement logic and historical access
2. `LocalAppChronicle.sol` - Local state management with access controls
3. `RemoteAppChronicle.sol` - Remote settlement processing and finalization
4. `BaseERC20xD.sol` - Cross-chain token base with hook integration
5. `LayerZeroGateway.sol` - Cross-chain communication layer

### Recent Security Improvements
- ✅ **Removed permit functionality** from BaseERC20 to reduce attack surface
- ✅ **Enhanced data fetching** in settlement hooks for consistency
- ✅ **Simplified access control** by removing unused modifiers
- ✅ **Improved function naming** with `getRemote*` prefix for clarity
- ✅ **Moved hook implementations** to separate periphery repository

### Critical Areas for Review

#### 1. Access Control & Authorization
- Settler whitelist management in LiquidityMatrix
- App registration and chronicle access controls
- Owner privileges and upgrade paths
- Simplified modifier usage (`onlyApp` vs removed `onlyAppOrMatrix`)

#### 2. State Management & Integrity
- Merkle tree update atomicity
- Chronicle version isolation and historical queries
- Settlement finalization logic with data consistency

#### 3. Cross-Chain Operations
- Transfer pending state management
- Settlement processing and validation
- Hook system security and failure handling
- Data fetching in `onSettleData` callbacks

#### 4. Economic Security
- Liquidity accounting across chains
- Settlement incentive mechanisms
- Protection against double-spending
- Reorg protection through versioning

#### 5. Version Management & Reorg Handling
- Version creation and isolation
- Historical state access correctness (`getRemote*` functions)
- Chronicle deployment determinism
- Timestamp-based query routing

### Known Limitations & Trust Assumptions
- **Trust-based settlements**: Current implementation trusts whitelisted settlers
- **No slashing mechanisms**: Malicious settlers not economically penalized
- **Gateway dependency**: Security depends on underlying LayerZero infrastructure
- **Hook failure isolation**: Failed hooks could indicate integration issues
- **Centralized version management**: Owner controls reorg version creation

### Architecture Decisions
- **Hook separation**: Moved concrete implementations to periphery for modularity
- **Permit removal**: Eliminated EIP-2612 to reduce complexity and attack surface
- **Function naming**: `getRemote*` prefix clarifies cross-chain data access
- **Data consistency**: Hooks fetch data from authoritative source (LiquidityMatrix)

### Development Status
- ✅ Core architecture implemented and battle-tested
- ✅ Full test suite (294 tests) with comprehensive coverage
- ✅ Reorg protection via chronicle system with historical access
- ✅ Security hardening (permit removal, access control simplification)
- ✅ Code organization (hook separation, clear naming conventions)
- 🔄 Security audits in progress
- 🔄 Formal verification planned

---

**Contact:** For security disclosures or audit inquiries: team@levx.io

**License:** BUSL (Business Source License)