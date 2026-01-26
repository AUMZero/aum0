use anchor_lang::prelude::*;
use crate::state::*;
use crate::errors::ProtocolError;
use crate::events::ScoreFinalized;
use crate::constants::*;

#[derive(Accounts)]
#[instruction(token_mint: Pubkey)]
pub struct FinalizeScore<'info> {
    pub authority: Signer<'info>,

    #[account(
        mut,
        seeds = [PROTOCOL_SEED],
        bump = protocol_state.bump,
        has_one = authority @ ProtocolError::Unauthorized,
    )]
    pub protocol_state: Account<'info, ProtocolState>,

    #[account(
        mut,
        seeds = [TOKEN_SCORE_SEED, token_mint.as_ref()],
        bump = token_score.bump,
        constraint = token_score.mint == token_mint @ ProtocolError::InvalidMint,
    )]
    pub token_score: Account<'info, TokenScore>,
}

pub fn handler(ctx: Context<FinalizeScore>, _token_mint: Pubkey) -> Result<()> {
    let state = &mut ctx.accounts.protocol_state;
    let score = &mut ctx.accounts.token_score;

    score.verdict = match score.score {
        750..=1000 => 3, // PROPHECY_ALERT
        550..=749 => 2,  // WATCHING
        350..=549 => 1,  // NEUTRAL
        _ => 0,          // SKIP
    };

    state.total_tokens_scored = state.total_tokens_scored.saturating_add(1);

    emit!(ScoreFinalized {
        token_mint: score.mint,
        final_score: score.score,
        verdict: score.verdict,
        signal_count: score.signal_count,
    });

    Ok(())
}
// updated: 2026-03-11

// edge



