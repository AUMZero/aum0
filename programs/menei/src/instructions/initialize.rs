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

    pub system_program: Program<'info, System>,
}

pub fn handler(ctx: Context<Initialize>, config: InitConfig) -> Result<()> {
    require!(config.fee_basis_points <= FEE_DENOMINATOR, ProtocolError::InvalidFee);

    let state = &mut ctx.accounts.protocol_state;
    state.authority = ctx.accounts.authority.key();
    state.oracle = config.oracle;
    state.fee_basis_points = config.fee_basis_points;
    state.treasury = ctx.accounts.authority.key();
    state.version = 1;
    state.bump = ctx.bumps.protocol_state;

    emit!(ProtocolInitialized {
        authority: state.authority,
        oracle: state.oracle,
        fee_basis_points: state.fee_basis_points,
    });

    Ok(())
}
// updated: 2026-02-26






