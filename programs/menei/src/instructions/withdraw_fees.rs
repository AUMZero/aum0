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
    pub treasury: AccountInfo<'info>,

    pub system_program: Program<'info, System>,
}

pub fn handler(ctx: Context<WithdrawFees>) -> Result<()> {
    let protocol_info = ctx.accounts.protocol_state.to_account_info();
    let rent = Rent::get()?;
    let min_balance = rent.minimum_balance(ProtocolState::LEN);
    let available = protocol_info.lamports()
        .checked_sub(min_balance)
        .ok_or(ProtocolError::ArithmeticOverflow)?;

    if available > 0 {
        **protocol_info.try_borrow_mut_lamports()? -= available;
        **ctx.accounts.treasury.try_borrow_mut_lamports()? += available;
    }

    Ok(())
}
// updated: 2026-02-21
