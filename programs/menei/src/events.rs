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
