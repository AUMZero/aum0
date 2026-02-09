use anchor_lang::prelude::*;
use crate::state::*;
use crate::errors::ProtocolError;
use crate::events::OracleUpdated;
use crate::constants::*;

#[derive(Accounts)]
pub struct UpdateOracle<'info> {
    #[account(mut)]
    pub oracle: Signer<'info>,

    #[account(
        seeds = [PROTOCOL_SEED],
        bump = protocol_state.bump,
        has_one = oracle @ ProtocolError::InvalidOracle,
    )]
    pub protocol_state: Account<'info, ProtocolState>,
}

pub fn handler(ctx: Context<UpdateOracle>, data: OracleData) -> Result<()> {
