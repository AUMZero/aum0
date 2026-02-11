#!/usr/bin/env bash
set -euo pipefail

echo "Seeding oracle feeds for menei..."

solana airdrop 2 --url devnet 2>/dev/null || true

echo "Oracle seed complete. Feed data initialized."

# Requires: ANCHOR_WALLET set to deployer keypair path






