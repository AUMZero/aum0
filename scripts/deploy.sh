#!/usr/bin/env bash
set -euo pipefail

CLUSTER="${1:-devnet}"
echo "Deploying menei to $CLUSTER..."

anchor build
anchor deploy --provider.cluster "$CLUSTER"

echo "Generating IDL..."
anchor idl init --filepath target/idl/menei.json \
    $(solana address -k target/deploy/menei-keypair.json) \
    --provider.cluster "$CLUSTER"

echo "Deployment complete."

# Usage: ./scripts/deploy.sh [devnet|mainnet-beta]







