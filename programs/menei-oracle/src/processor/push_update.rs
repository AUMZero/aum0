use anchor_lang::prelude::*;
use crate::state::*;

pub const FEED_SEED: &[u8] = b"oracle_feed";

#[derive(Accounts)]
pub struct PushUpdate<'info> {
    pub authority: Signer<'info>,

    #[account(
        mut,
        has_one = authority,
    )]
    pub feed: Account<'info, OracleFeed>,
}

pub fn handler(ctx: Context<PushUpdate>, value: i64, confidence: u8) -> Result<()> {
    let feed = &mut ctx.accounts.feed;
    let clock = Clock::get()?;

    require!(
        clock.unix_timestamp - feed.latest_timestamp >= feed.min_update_interval,
        ErrorCode::ConstraintRaw
    );

    feed.latest_value = value;
    feed.latest_timestamp = clock.unix_timestamp;
    feed.confidence = confidence;
    feed.update_count = feed.update_count.saturating_add(1);
    Ok(())
}
// updated: 2026-02-24
