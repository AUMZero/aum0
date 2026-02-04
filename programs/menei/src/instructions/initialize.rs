use anchor_lang::prelude::*;
use crate::state::*;
use crate::errors::ProtocolError;
use crate::events::ProtocolInitialized;
use crate::constants::*;

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        init,
        payer = authority,
        space = ProtocolState::LEN,
        seeds = [PROTOCOL_SEED],
        bump,
    )]
    pub protocol_state: Account<'info, ProtocolState>,

