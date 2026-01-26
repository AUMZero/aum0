use anchor_lang::prelude::*;

#[account]
pub struct OracleFeed {
    pub authority: Pubkey,
    pub feed_id: [u8; 32],
    pub latest_value: i64,
    pub latest_timestamp: i64,
    pub confidence: u8,
    pub update_count: u64,
    pub min_update_interval: i64,
    pub bump: u8,
}

impl OracleFeed {
    pub const LEN: usize = 8 + 32 + 32 + 8 + 8 + 1 + 8 + 8 + 1;
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct FeedConfig {
    pub feed_id: [u8; 32],
    pub min_update_interval: i64,
}
// updated: 2026-02-25

// Ring buffer size: 32 data points per feed, overwritten on overflow

// 64




