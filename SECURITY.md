# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in menei-oracle, please report it responsibly.

Send a detailed description to: security@menei.fun

Do NOT open a public GitHub issue for security vulnerabilities.

## Scope

- On-chain program logic (Anchor/Rust)
- Oracle data feed integrity and staleness protection
- Token scoring algorithm manipulation
- Signal submission authorization bypass
- SDK client-side deserialization vulnerabilities

## Response Timeline

- Acknowledgment: 24 hours
- Initial assessment: 72 hours
- Fix deployment: varies by severity

## Security Practices

- All oracle signals require authority validation
- Arithmetic operations use `checked_add` / `saturating_add`
- PDA derivation uses deterministic seeds with collision prevention
- Confidence bounds validated on-chain (`require!(confidence <= 100)`)





