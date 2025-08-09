# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

### Building
- `make build` - Build the entire project
- `make build ARGS="src/"` - Build only contracts in src/
- `make build ARGS="src/MyContract.sol"` - Build specific contract
- `make clean` - Clean build artifacts
- `make fmt` - Format code using forge fmt
- `make fmt ARGS="src/"` - Format only files in src/

### Testing
- `make test` - Run all tests
- `make test ARGS="test/MyTest.t.sol"` - Run specific test file
- `make test ARGS="--match-test testFoo"` - Run tests matching pattern
- `make test ARGS="--match-contract Foo"` - Run tests for specific contract
- `make test-v` - Run tests with verbosity (-vv)
- `make test-v ARGS="--match-test testFoo"` - Run specific tests with verbosity
- `make test-gas` - Run tests with gas reporting
- `make test-gas ARGS="--match-test testFoo"` - Run specific tests with gas report

### Deployment
- `make deploy-local` - Deploy to local network

### Development Setup
- `make setup` - Setup development environment (installs git hooks)
- `make install-hooks` - Install git pre-commit hooks

## Architecture Overview

### Core Components

**LiquidityMatrix**: Central accounting system that tracks cross-chain liquidity for all tokens. It maintains:
- Local liquidity per token/account
- Merkle roots of remote chain states
- Settler whitelist for authorized liquidity updates
- Integration with Synchronizer for cross-chain state updates

**Synchronizer**: Handles cross-chain state synchronization using LayerZero OApp pattern:
- Aggregates liquidity roots from remote chains
- Validates and updates LiquidityMatrix with remote state
- Configurable confirmations per chain for security

**ERC20xD**: Cross-chain token implementation that:
- Extends BaseERC20xD for core cross-chain functionality
- Integrates with LiquidityMatrix for balance tracking
- Uses LayerZeroGateway for cross-chain reads
- Supports hooks for extensibility

**LayerZeroGateway**: Registration-based gateway for cross-chain operations:
- Apps register as "readers" with unique cmdLabels
- Manages read targets (remote contract addresses per chain)
- Implements LayerZero's read protocol with lzReduce for aggregation
- Handles cross-chain callbacks via onRead pattern

### Key Design Patterns

**Registration-Based Gateway System**:
```solidity
// Apps must register with gateway to get cmdLabel
gateway.registerReader(address(app));

// Apps set their read targets per chain
app.updateReadTarget(chainUID, targetAddress);

// Gateway routes reads through LayerZero
gateway.read(callData, extra, lzOptions);
```

**Hook System**: Extensible pattern for token functionality:
- Hooks implement IERC20xDHook interface
- Registered via `addHook(address hook)`
- Called on transfers: `beforeTransfer`, `afterTransfer`
- Example: DividendDistributorHook, ERC7540Hook

**Reduce Pattern for Cross-Chain Aggregation**:
- Gateway calls `lzReduce` with responses from all chains
- App implements `reduce` to aggregate responses
- Results passed to `onRead` callback for final processing

**Pending Transfer Mechanism**: Handles cross-chain transfer race conditions:
- Transfers create pending state if insufficient local balance
- Cross-chain reads aggregate available balance
- Transfer completes when total balance sufficient

### Test Infrastructure

**BaseERC20xDTestHelper**: Foundation for multi-chain tests
- Sets up 8 chains with full infrastructure per chain
- Handles gateway registration and read target configuration
- Provides `_executeRead` helper for simulating cross-chain reads
- Manages synchronization and settlement workflows

**Test Pattern for Cross-Chain Operations**:
```solidity
// Execute cross-chain read (simulates LayerZero flow)
_executeRead(
    address(reader),          // The app initiating read
    readersArray,             // Target contracts on each chain
    callData,                 // Function to call
    expectedError            // Optional error expectation
);
```

### Critical Workflows

**Adding a New Hook**:
1. Implement BaseERC20xDHook
2. Register with gateway if needs cross-chain reads
3. Set read targets for each chain
4. Add hook to token via `addHook()`

**Setting Up Cross-Chain Communication**:
1. Register app with gateway: `gateway.registerReader(app)`
2. Configure read targets: `app.updateReadTarget(eid, target)`
3. Implement `reduce()` for response aggregation
4. Implement `onRead()` for callback handling

**Gateway Read Flow**:
1. App calls `gateway.read()` with callData
2. Gateway sends LayerZero read requests to all chains
3. Responses aggregated via `lzReduce` calling app's `reduce()`
4. Result passed to app's `onRead()` callback

### Important Notes

- All cross-chain operations use LayerZero v2 protocol
- Gateway registration is owner-only, one-time operation
- Read targets must be set for all chains before reads work
- Hooks can modify transfer behavior but must respect pending transfers
- LiquidityMatrix updates require authorized settler or synchronizer