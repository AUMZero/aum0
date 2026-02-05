use anchor_lang::prelude::*;
use crate::state::*;
use crate::errors::ProtocolError;
use crate::events::SignalSubmitted;
use crate::constants::*;

#[derive(Accounts)]
#[instruction(params: SignalParams)]
pub struct SubmitSignal<'info> {
    #[account(mut)]
    pub oracle: Signer<'info>,

    #[account(
        mut,
        seeds = [PROTOCOL_SEED],
        bump = protocol_state.bump,
    )]
    pub protocol_state: Account<'info, ProtocolState>,

    #[account(
        init_if_needed,
        payer = oracle,
        space = TokenScore::LEN,
        seeds = [TOKEN_SCORE_SEED, params.token_mint.as_ref()],
        bump,
    )]
    pub token_score: Account<'info, TokenScore>,

    pub system_program: Program<'info, System>,
}
