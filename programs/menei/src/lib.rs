use anchor_lang::prelude::*;

pub mod state;
pub mod instructions;
pub mod errors;
pub mod constants;
pub mod events;

use instructions::*;

declare_id!("MNEi8sBgZ2vFQLwb4HCPESKgJjPaFNbfRwqEdHmw1HZ");

#[program]
pub mod menei {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, config: InitConfig) -> Result<()> {
        instructions::initialize::handler(ctx, config)
    }

    pub fn submit_signal(ctx: Context<SubmitSignal>, params: SignalParams) -> Result<()> {
        instructions::submit_signal::handler(ctx, params)
    }

    pub fn update_oracle(ctx: Context<UpdateOracle>, data: OracleData) -> Result<()> {
        instructions::update_oracle::handler(ctx, data)
    }

    pub fn finalize_score(ctx: Context<FinalizeScore>, token_mint: Pubkey) -> Result<()> {
        instructions::finalize_score::handler(ctx, token_mint)
    }

    pub fn withdraw_fees(ctx: Context<WithdrawFees>) -> Result<()> {
        instructions::withdraw_fees::handler(ctx)
    }
}

// Program version: 0.1.0





