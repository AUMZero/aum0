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
