use anchor_lang::prelude::*;
use crate::state::ProtocolState;
use crate::errors::ProtocolError;
use crate::constants::*;

#[derive(Accounts)]
pub struct WithdrawFees<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        mut,
        seeds = [PROTOCOL_SEED],
        bump = protocol_state.bump,
        has_one = authority @ ProtocolError::Unauthorized,
    )]
    pub protocol_state: Account<'info, ProtocolState>,

    /// CHECK: Treasury account validated by protocol state
    #[account(mut, address = protocol_state.treasury)]
