SOLX := $(HOME)/.local/bin/solx

.PHONY: all setup install-hooks build test fmt clean help

# Default target
all: build

# Setup development environment
setup: install-hooks
	@echo "✅ Development environment setup complete!"

# Install git hooks
install-hooks:
	@echo "Installing git hooks..."
	@cp scripts/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "✅ Pre-commit hook installed successfully!"

# Build the project
build:
	@echo "Building project..."
	@FOUNDRY_SOLC_VERSION=$(SOLX) EVM_DISABLE_MEMORY_SAFE_ASM_CHECK=1 forge build

# Run tests
test:
	@echo "Running tests..."
	@FOUNDRY_SOLC_VERSION=$(SOLX) EVM_DISABLE_MEMORY_SAFE_ASM_CHECK=1 forge test

# Run tests with verbosity
test-v:
	@FOUNDRY_SOLC_VERSION=$(SOLX) EVM_DISABLE_MEMORY_SAFE_ASM_CHECK=1 forge test -vv

# Run tests with gas reporting
test-gas:
	@FOUNDRY_SOLC_VERSION=$(SOLX) EVM_DISABLE_MEMORY_SAFE_ASM_CHECK=1 forge test --gas-report

# Format code
fmt:
	@echo "Formatting code..."
	@FOUNDRY_SOLC_VERSION=$(SOLX) EVM_DISABLE_MEMORY_SAFE_ASM_CHECK=1 forge fmt

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@forge clean

# Deploy to local network
deploy-local:
	@echo "Deploying to local network..."
	@FOUNDRY_SOLC_VERSION=$(SOLX) EVM_DISABLE_MEMORY_SAFE_ASM_CHECK=1 forge script script/Deploy.s.sol --rpc-url localhost --broadcast

# Show help
help:
	@echo "Available commands:"
	@echo "  make setup          - Setup development environment (install git hooks)"
	@echo "  make install-hooks  - Install git pre-commit hooks"
	@echo "  make build          - Build the project"
	@echo "  make test           - Run tests"
	@echo "  make test-v         - Run tests with verbosity"
	@echo "  make test-gas       - Run tests with gas reporting"
	@echo "  make fmt            - Format code using forge fmt"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make deploy-local   - Deploy to local network"
	@echo "  make help           - Show this help message"
