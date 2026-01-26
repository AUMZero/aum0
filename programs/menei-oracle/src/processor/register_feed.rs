use anchor_lang::prelude::*;
use crate::state::*;

pub const FEED_SEED: &[u8] = b"oracle_feed";

#[derive(Accounts)]
#[instruction(feed_config: FeedConfig)]
pub struct RegisterFeed<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        init,
        payer = authority,
        space = OracleFeed::LEN,
        seeds = [FEED_SEED, feed_config.feed_id.as_ref()],
        bump,
    )]
    pub feed: Account<'info, OracleFeed>,

    pub system_program: Program<'info, System>,
}

pub fn handler(ctx: Context<RegisterFeed>, feed_config: FeedConfig) -> Result<()> {
    let feed = &mut ctx.accounts.feed;
    feed.authority = ctx.accounts.authority.key();
    feed.feed_id = feed_config.feed_id;
    feed.min_update_interval = feed_config.min_update_interval;
    feed.bump = ctx.bumps.feed;
    Ok(())
}
// updated: 2026-03-02

// transfer



