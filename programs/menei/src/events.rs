use anchor_lang::prelude::*;

#[event]
pub struct SignalSubmitted {
    pub oracle: Pubkey,
    pub token_mint: Pubkey,
    pub score_delta: i16,
    pub confidence: u8,
    pub timestamp: i64,
}

#[event]
pub struct ScoreFinalized {
    pub token_mint: Pubkey,
    pub final_score: u16,
    pub verdict: u8,
    pub signal_count: u32,
}

#[event]
pub struct OracleUpdated {
    pub oracle: Pubkey,
    pub feed_id: [u8; 32],
    pub value: i64,
}

#[event]
pub struct ProtocolInitialized {
    pub authority: Pubkey,
    pub oracle: Pubkey,
    pub fee_basis_points: u16,
}
// updated: 2026-03-05
