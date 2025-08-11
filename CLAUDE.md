# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

The xD protocol implements a cross-chain liquidity and state management system with a chronicle-based versioning system for reorg protection.

### Core Components

#### 1. LiquidityMatrix
The central ledger contract that manages liquidity and data state across all chains:
- **Hierarchical Merkle Trees**: Maintains top-level liquidity and data trees that aggregate app-specific trees
- **Chronicle System**: Uses versioned chronicles (LocalAppChronicle, RemoteAppChronicle) for reorg protection
- **App Registration**: Apps register with the matrix to track their liquidity and data
- **Settler System**: Authorized settlers can process cross-chain state updates
- **Gateway Integration**: Connects to a gateway (e.g., LayerZeroGateway) for cross-chain communication
- **Version Management**: Tracks versions starting at 1, new versions created on reorgs

Key features:
- Each version has its own set of chronicles and state
- Supports account mapping between chains
- Implements IGatewayApp for cross-chain read operations
- Uses `bytes32 chainUID` for chain identification

#### 2. Chronicle System
Three types of chronicles manage versioned state:

**AppChronicle** (base contract):
- Stores snapshots of liquidity and data
- Maintains Merkle trees for efficient verification

**LocalAppChronicle**:
- Manages local chain state for an app at a specific version
- Tracks account liquidity and arbitrary key-value data
- Updates trigger parent LiquidityMatrix tree updates
- Access controlled: `onlyAppOrLiquidityMatrix` modifier for updates
- Created during app registration: `new LocalAppChronicle{salt: bytes32(version)}(...)`

**RemoteAppChronicle**: 
- Manages remote chain state for an app at a specific version
- Processes settlements from remote chains
- Tracks finalization status (liquidity settled + data settled = finalized)
- Implements trust-based settlement (no proof verification currently)
- Must be created for each remote chain an app interacts with

#### 3. Gateway System

**LayerZeroGateway**:
- Implements LayerZero OApp pattern for cross-chain messaging
- Manages app registration and read targets
- Routes cross-chain reads through LayerZero's read protocol
- Converts between `bytes32 chainUID` and LayerZero's `uint32 eid`

**IGateway Interface**:
- Abstracts cross-chain communication
- Supports multiple implementations (LayerZero, others)
- Provides read/send message capabilities
- Uses generic `bytes32 chainUID` for chain identification

#### 4. Token Implementations

**BaseERC20xD**:
- Abstract cross-chain ERC20 implementation
- Integrates with LiquidityMatrix for balance tracking
- Supports pending transfers for cross-chain operations
- Extensible hook system for custom functionality
- Implements ILiquidityMatrixHook for settlement callbacks
- Constructor requires whitelisted settler parameter

**ERC20xD**:
- Concrete implementation of BaseERC20xD
- Standard cross-chain token with mint/burn capabilities
- Constructor: `(name, symbol, decimals, liquidityMatrix, gateway, owner, settler)`

**WrappedERC20xD**:
- Wraps existing ERC20 tokens for cross-chain functionality
- Supports wrap/unwrap operations
- Compatible with hook system for vault integrations
- Constructor: `(underlying, name, symbol, decimals, liquidityMatrix, gateway, owner, settler)`

**NativexD**:
- Wraps native assets (ETH, etc.) for cross-chain transfers
- Similar to WrappedERC20xD but for native tokens
- Constructor: `(name, symbol, decimals, liquidityMatrix, gateway, owner, settler)`

#### 5. Hook System

**IERC20xDHook Interface**:
- Extensibility mechanism for tokens
- Callbacks for: transfer events, global availability reads, account mapping, settlement
- Enables custom logic like dividends, vaults, etc.

**ILiquidityMatrixHook Interface**:
- Implemented by apps that need settlement notifications
- Methods: `onSettleLiquidity`, `onSettleTotalLiquidity`, `onSettleData`
- Called when remote state is settled

### Key Design Patterns

#### Registration Flow
1. Settler must be whitelisted in LiquidityMatrix: `updateSettlerWhitelisted(settler, true)`
2. App registers with LiquidityMatrix: `registerApp(syncMappedAccountsOnly, useHook, settler)`
3. LocalAppChronicle automatically created for current version
4. App can start tracking liquidity/data

#### Chronicle Creation
- **Local**: Created automatically during app registration
- **Remote**: Must be created explicitly for each remote chain:
  ```solidity
  // Settler creates RemoteAppChronicle for app on remote chain
  RemoteAppChronicle chronicle = new RemoteAppChronicle(
    liquidityMatrix, app, chainUID, version
  );
  // Register it in LiquidityMatrix (needs implementation)
  ```

#### Cross-Chain Read Flow
1. App initiates read through Gateway: `gateway.read()`
2. Gateway sends read requests to all configured chains
3. Responses aggregated via `reduce()` function
4. Result passed to app's `onRead()` callback

#### Settlement Flow
1. Sync operation fetches roots from remote chains: `sync()`
2. Roots stored in LiquidityMatrix via `onReceiveRoots()`
3. Settler processes roots via RemoteAppChronicle:
   - `settleLiquidity(SettleLiquidityParams)`
   - `settleData(SettleDataParams)`
4. Settlement updates snapshots and triggers hooks
5. Finalization occurs when both liquidity and data settled

#### Version Management
- Versions track potential reorgs/forks
- New version triggered by: `addReorg(timestamp)`
- Current version: `currentVersion()` returns `_versions.length`
- Get version for timestamp: `getVersion(timestamp)`
- Apps/settlers can add chronicles for past versions

### Critical Functions

#### LiquidityMatrix
- `registerApp(syncMappedAccountsOnly, useHook, settler)`: Register new app
- `updateLocalLiquidity(account, liquidity)`: Update account liquidity
- `onReceiveRoots(chainUID, version, liquidityRoot, dataRoot, timestamp)`: Process roots
- `sync(data)`: Initiate cross-chain sync
- `updateSettlerWhitelisted(account, whitelisted)`: Manage settler whitelist
- `getCurrentLocalAppChronicle(app)`: Get current local chronicle
- `getCurrentRemoteAppChronicle(app, chainUID)`: Get current remote chronicle

#### LocalAppChronicle  
- `updateLiquidity(account, liquidity)`: Update account liquidity
- `updateData(key, value)`: Update key-value data
- Uses `onlyAppOrLiquidityMatrix` modifier for access control

#### RemoteAppChronicle
- `settleLiquidity(params)`: Process liquidity updates from remote chain
- `settleData(params)`: Process data updates from remote chain
- `getLastFinalizedTimestamp()`: Get latest fully settled timestamp
- `getLiquidityAt(account, timestamp)`: Get account liquidity at timestamp
- `getTotalLiquidityAt(timestamp)`: Get total liquidity at timestamp

#### BaseERC20xD
- `transfer(to, amount, callData, value, data)`: Cross-chain transfer
- `addHook(hook)`: Register hook for extensibility
- `removeHook(hook)`: Remove registered hook
- `onSettleLiquidity(...)`: Hook callback for liquidity settlement
- `onSettleTotalLiquidity(...)`: Hook callback for total liquidity settlement
- `onSettleData(...)`: Hook callback for data settlement

### Testing Patterns

#### Setup Requirements
1. Deploy LiquidityMatrix with owner
2. Whitelist settlers: `liquidityMatrix.updateSettlerWhitelisted(settler, true)`
3. Create settler contracts (e.g., SettlerMock)
4. Register apps with whitelisted settlers:
   ```solidity
   liquidityMatrix.registerApp(false, true, settler);
   ```
5. Create RemoteAppChronicles for each remote chain (TODO: needs implementation)
6. Configure gateway and read targets:
   ```solidity
   gateway.registerApp(app);
   app.updateReadTarget(chainUID, targetAddress);
   ```

#### Common Issues and Solutions
- `InvalidSettler`: Settler must be whitelisted before app registration
- `RemoteAppChronicleNotSet`: Need to create RemoteAppChronicle for remote chain
- `Forbidden`: Check access control - LocalAppChronicle needs `onlyAppOrLiquidityMatrix`
- `LocalAppChronicleNotSet`: App must be registered first
- `AppNotRegistered`: Call `registerApp()` before other operations

### Build & Test Commands

#### Building
- `make build` - Build the entire project
- `make build ARGS="src/"` - Build only contracts in src/
- `make build ARGS="src/MyContract.sol"` - Build specific contract
- `make clean` - Clean build artifacts
- `make fmt` - Format code using forge fmt
- `make fmt ARGS="src/"` - Format only files in src/

#### Testing
- `make test` - Run all tests
- `make test ARGS="test/MyTest.t.sol"` - Run specific test file
- `make test ARGS="--match-test testFoo"` - Run tests matching pattern
- `make test ARGS="--match-contract Foo"` - Run tests for specific contract
- `make test-v` - Run tests with verbosity (-vv)
- `make test-v ARGS="--match-test testFoo"` - Run specific tests with verbosity
- `make test-gas` - Run tests with gas reporting
- `make test-gas ARGS="--match-test testFoo"` - Run specific tests with gas report

#### Deployment
- `make deploy-local` - Deploy to local network

#### Development Setup
- `make setup` - Setup development environment (installs git hooks)
- `make install-hooks` - Install git pre-commit hooks

### Important Implementation Notes

1. **Chronicle Access Control**: LocalAppChronicle uses `onlyAppOrLiquidityMatrix` modifier to allow both the app and LiquidityMatrix to update state

2. **Settler Requirements**: All token constructors now require a `settler` parameter that must be whitelisted in LiquidityMatrix before deployment

3. **Version System**: Version starts at 1, not 0. The system tracks versions for reorg protection.

4. **Remote Chronicle Setup**: Currently needs manual creation for each app/chain pair - automation needed in test helpers

5. **Chain Identification**: Uses generic `bytes32 chainUID` throughout, with LayerZeroGateway converting to `uint32 eid` internally

6. **Hook Failures**: Hook failures are caught and emitted as events, they don't revert the main transaction

7. **Aggregation Functions**: LiquidityMatrix provides aggregated view functions that sum liquidity across local and all remote chains
