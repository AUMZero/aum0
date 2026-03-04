# Contributing to menei

## Development Setup

1. Install Rust 1.75+ and Solana CLI 1.17+
2. Install Anchor 0.29.0
3. Clone this repository
4. Run `cargo build` to verify the toolchain
5. Run `cd sdk && npm install` for the TypeScript SDK

## Pull Request Process

- Fork the repository and create a feature branch
- Write tests for any new functionality
- Ensure `cargo clippy` and `cargo fmt` pass
- Ensure `cd sdk && npm test` passes
- Submit a PR with a clear description of changes

## Code Style

- Rust: Follow standard rustfmt conventions
- TypeScript: Strict mode, no any types
- Commit messages: imperative mood, concise
<!-- updated: 2026-03-05 -->
