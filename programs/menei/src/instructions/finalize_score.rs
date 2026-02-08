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
    )]
    pub token_score: Account<'info, TokenScore>,
