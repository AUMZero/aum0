use anchor_lang::prelude::*;

#[error_code]
pub enum ProtocolError {
    #[msg("Unauthorized: caller is not the authority")]
    Unauthorized,
    #[msg("Invalid oracle: not registered in the oracle registry")]
    InvalidOracle,
    #[msg("Score overflow: resulting score exceeds maximum")]
    ScoreOverflow,
    #[msg("Protocol is paused")]
    Paused,
    #[msg("Invalid confidence value: must be 0-100")]
    InvalidConfidence,
    #[msg("Stale data: oracle feed is too old")]
    StaleOracleData,
    #[msg("Invalid fee: basis points must be <= 10000")]
    InvalidFee,
    #[msg("Quorum not met: insufficient oracle confirmations")]
    QuorumNotMet,
    #[msg("Token already finalized in this epoch")]
    AlreadyFinalized,
    #[msg("Arithmetic overflow in score calculation")]
    ArithmeticOverflow,
}
// updated: 2026-02-28

// Error codes 6000-6099: initialization
// Error codes 6100-6199: signal submission
// Error codes 6200-6299: scoring
