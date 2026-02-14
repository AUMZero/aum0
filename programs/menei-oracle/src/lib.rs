use anchor_lang::prelude::*;

pub mod state;
pub mod processor;

use processor::*;

declare_id!("MnE1KkEHCmZMscGxHCkYbKof1PBjRDWHSH6KqVu4diR");

#[program]
pub mod menei_oracle {
    use super::*;

    pub fn register_feed(ctx: Context<RegisterFeed>, feed_config: FeedConfig) -> Result<()> {
        processor::register_feed::handler(ctx, feed_config)
    }

    pub fn push_update(ctx: Context<PushUpdate>, value: i64, confidence: u8) -> Result<()> {
        processor::push_update::handler(ctx, value, confidence)
    }
}
// updated: 2026-02-17

// Program version: 0.1.0






