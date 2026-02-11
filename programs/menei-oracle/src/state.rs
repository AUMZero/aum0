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
