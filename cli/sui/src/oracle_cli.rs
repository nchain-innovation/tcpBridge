use std::str::FromStr;
use sui_sdk::SuiClient;
use sui_sdk::types::transaction::TransactionKind;
use sui_sdk::{
    types::{Identifier, programmable_transaction_builder::ProgrammableTransactionBuilder},
    wallet_context::WalletContext,
};

use crate::configs::{oracle_config, wallet_config};
use crate::utils::execute_transaction;

pub(crate) async fn update_chain(
    client: SuiClient,
    serialisation: Vec<u8>,
) -> Result<(), anyhow::Error> {
    let (header_chain_arg, blockchain_oracle_id) = oracle_config(true);
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call update_chain
    let mut builder = ProgrammableTransactionBuilder::new();
    let header_chain_obj = builder.obj(header_chain_arg)?;
    let block_header_serialisation = builder.pure(serialisation)?;

    builder.programmable_move_call(
        blockchain_oracle_id,
        Identifier::from_str("blockchain_oracle")?,
        Identifier::from_str("update_chain")?,
        vec![],
        vec![header_chain_obj, block_header_serialisation],
    );

    // Execute the transaction
    let tx_kind = TransactionKind::ProgrammableTransaction(builder.finish());
    let response = execute_transaction(client, &wallet, active_address, vec![], tx_kind)
        .await
        .expect("Failed executing transaction");

    // Print transaction response
    println!("Transaction executed successfully: {:?}", response);

    Ok(())
}
