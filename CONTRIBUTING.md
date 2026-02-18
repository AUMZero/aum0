# Contributing to menei-oracle

## Development Setup

1. Install Rust 1.75+ and Solana CLI 1.17+
2. Install Anchor 0.29.0
3. Clone this repository
4. Run `cargo build` to verify the toolchain
5. Run `cd sdk && npm install` for the TypeScript SDK
6. Run `cd engine && npm install` for the analysis engine

## Project Structure

- `programs/menei/` — on-chain scoring program (Anchor/Rust)
- `programs/menei-oracle/` — oracle data feed program
- `sdk/` — TypeScript client SDK
- `engine/` — off-chain analysis engine

## Pull Request Process

- Fork the repository and create a feature branch
- Write tests for any new functionality
- Ensure `cargo clippy` passes
- Ensure `cd sdk && npm test` passes
- Ensure `cd engine && npx tsc --noEmit` passes
- Submit a PR with a clear description of changes

## Code Style

- Rust: Follow standard rustfmt conventions
- TypeScript: Strict mode, no `any` types
- Commit messages: imperative mood, concise







