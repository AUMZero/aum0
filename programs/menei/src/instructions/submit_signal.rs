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

pub fn handler(ctx: Context<SubmitSignal>, params: SignalParams) -> Result<()> {
    let state = &ctx.accounts.protocol_state;
    require!(!state.paused, ProtocolError::Paused);
    require!(
        ctx.accounts.oracle.key() == state.oracle,
        ProtocolError::InvalidOracle
    );
    require!(params.confidence <= 100, ProtocolError::InvalidConfidence);

    let score = &mut ctx.accounts.token_score;
    score.mint = params.token_mint;

    let new_score = (score.score as i32)
        .checked_add(params.score_delta as i32)
        .ok_or(ProtocolError::ArithmeticOverflow)?;

    score.score = new_score.clamp(0, MAX_SCORE as i32) as u16;
    score.signal_count = score.signal_count.saturating_add(1);
    score.bonding_progress = params.bonding_progress;
