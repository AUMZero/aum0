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
            2 => "WATCHING",
            3 => "PROPHECY_ALERT",
            _ => "UNKNOWN",
        }
    }
}

#[account]
pub struct OracleRegistry {
    pub authority: Pubkey,
    pub oracles: Vec<Pubkey>,
    pub min_confidence: u8,
    pub quorum: u8,
    pub bump: u8,
}

impl OracleRegistry {
    pub fn space(max_oracles: usize) -> usize {
        8 + 32 + 4 + (32 * max_oracles) + 1 + 1 + 1
    }
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct InitConfig {
    pub fee_basis_points: u16,
    pub oracle: Pubkey,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct SignalParams {
    pub token_mint: Pubkey,
    pub score_delta: i16,
    pub bonding_progress: u16,
    pub social_flags: u8,
    pub confidence: u8,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct OracleData {
    pub feed_id: [u8; 32],
    pub value: i64,
    pub timestamp: i64,
    pub confidence: u8,
}
// updated: 2026-02-07

// Account size: 8 (discriminator) + 32 (authority) + 48 (weights) + 8 (epoch)
