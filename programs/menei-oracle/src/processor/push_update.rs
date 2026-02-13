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
