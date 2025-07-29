# Git Hooks

This directory contains git hooks for the project.

## Pre-commit Hook

The pre-commit hook automatically:
1. Runs `forge fmt` to format all Solidity files
2. Adds any formatting changes to the current commit
3. Runs `forge build` to ensure the code compiles

## Installation

To install the git hooks, run:

```bash
make setup
```

Or manually:

```bash
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Skipping Hooks

If you need to skip the pre-commit hook for a specific commit, use:

```bash
git commit --no-verify -m "your message"
```

## Troubleshooting

- If `forge fmt` is not found, ensure Foundry is installed and in your PATH
- If the build fails, fix compilation errors before committing
- The hook only stages files that were already staged before formatting