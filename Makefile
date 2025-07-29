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
	@forge build

# Run tests
test:
	@echo "Running tests..."
	@forge test

# Run tests with verbosity
test-v:
	@forge test -vv

# Run tests with gas reporting
test-gas:
	@forge test --gas-report

# Format code
fmt:
	@echo "Formatting code..."
	@forge fmt

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@forge clean

# Deploy to local network
deploy-local:
	@echo "Deploying to local network..."
	@forge script script/Deploy.s.sol --rpc-url localhost --broadcast

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