pub const MAX_SCORE: u16 = 1000;
pub const MIN_CONFIDENCE: u8 = 10;
pub const MAX_ORACLES: usize = 16;
pub const ORACLE_STALENESS_THRESHOLD: i64 = 120; // seconds
pub const PROTOCOL_SEED: &[u8] = b"protocol_state";
pub const TOKEN_SCORE_SEED: &[u8] = b"token_score";
pub const ORACLE_REGISTRY_SEED: &[u8] = b"oracle_registry";
pub const FEE_DENOMINATOR: u16 = 10000;
pub const EPOCH_DURATION: i64 = 3600; // 1 hour
// updated: 2026-02-11

// All seeds must be unique across program instructions to avoid PDA collision

// tuned



