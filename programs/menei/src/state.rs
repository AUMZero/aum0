use anchor_lang::prelude::*;

#[account]
#[derive(Default)]
pub struct ProtocolState {
    pub authority: Pubkey,
    pub oracle: Pubkey,
    pub total_signals: u64,
    pub total_tokens_scored: u64,
    pub fee_basis_points: u16,
    pub treasury: Pubkey,
    pub paused: bool,
    pub version: u8,
    pub bump: u8,
}

impl ProtocolState {
    pub const LEN: usize = 8 + 32 + 32 + 8 + 8 + 2 + 32 + 1 + 1 + 1;
}

#[account]
pub struct TokenScore {
    pub mint: Pubkey,
    pub score: u16,
    pub signal_count: u32,
    pub last_updated: i64,
    pub bonding_progress: u16,
    pub social_flags: u8,
    pub verdict: u8,
    pub confidence: u8,
    pub bump: u8,
}

impl TokenScore {
    pub const LEN: usize = 8 + 32 + 2 + 4 + 8 + 2 + 1 + 1 + 1 + 1;

    pub fn verdict_label(&self) -> &str {
        match self.verdict {
            0 => "SKIP",
            1 => "NEUTRAL",
