use anyhow::Context;
use sui_jsonrpc::client::MAX_GAS_BUDGET;
use sui_sdk::{
    SuiClient,
    rpc_types::{
        DryRunTransactionBlockResponse, SuiTransactionBlockEffectsAPI, SuiTransactionBlockResponse,
    },
    types::{
        base_types::{ObjectID, ObjectRef, SuiAddress},
        gas::GasCostSummary,
        transaction::{TransactionData, TransactionKind},
    },
    wallet_context::WalletContext,
};

pub async fn get_coin(
    wallet: &WalletContext,
    address: &SuiAddress,
    coin_value: u64,
) -> Result<ObjectRef, anyhow::Error> {
    let gas_objects = wallet.gas_objects(*address).await?;

    if gas_objects.is_empty() {
        return Err(anyhow::anyhow!("No gas objects found"));
    }

    let mut coin = None;

    for (value, o) in gas_objects.iter() {
        if *value >= coin_value {
            coin = Some((o.object_id, o.version, o.digest));
        }
    }

    coin.ok_or(anyhow::anyhow!("No gas object found with sufficient value"))
}

pub async fn get_gas_objects(
    wallet: &WalletContext,
    address: &SuiAddress,
    gas_budget: u64,
    skip: Vec<ObjectID>,
) -> Result<Vec<ObjectRef>, anyhow::Error> {
    let mut gas_objects = Vec::new();
    let mut current_amount = 0;

    for (value, coin) in wallet.gas_objects(*address).await?.iter() {
        if !skip.contains(&coin.object_id) {
            gas_objects.push(coin.object_ref());
            current_amount += value;
        }
        if current_amount >= gas_budget {
            break;
        }
    }
    if gas_objects.is_empty() {
        return Err(anyhow::anyhow!("No gas objects found"));
    }
    if current_amount < gas_budget {
        return Err(anyhow::anyhow!("Not enough gas objects found"));
    }

    Ok(gas_objects)
}

pub async fn gas_estimate(
    client: SuiClient,
    tx_kind: TransactionKind,
    sender: SuiAddress,
    gas_price: u64,
) -> Result<GasCostSummary, anyhow::Error> {
    let tx_data = client
        .transaction_builder()
        .tx_data_for_dry_run(sender, tx_kind, MAX_GAS_BUDGET, gas_price, None, None)
        .await;

    let DryRunTransactionBlockResponse { effects, .. } = client
        .read_api()
        .dry_run_transaction_block(tx_data.clone())
        .await
        .context("Error estimating gas budget")?;

    Ok(effects.gas_cost_summary().clone())
}

pub async fn execute_transaction(
    client: SuiClient,
    wallet: &WalletContext,
    address: SuiAddress,
    skipped_coins: Vec<ObjectID>,
    tx_kind: TransactionKind,
) -> Result<SuiTransactionBlockResponse, anyhow::Error> {
    // Estimate gas
    let gas_price = wallet.get_reference_gas_price().await?;
    let gas_cost_summary = gas_estimate(client, tx_kind.clone(), address, gas_price).await?;

    // Compute gas budget
    let overhead = 1000 * gas_price;
    let net_used = gas_cost_summary.net_gas_usage();
    let computation = gas_cost_summary.computation_cost;

    let gas_budget = overhead + (net_used.max(0) as u64).max(computation);

    // Retrieve gas objects
    let gas_objects = get_gas_objects(wallet, &address, gas_budget, skipped_coins).await?;

    // Execute the transaction
    let data = TransactionData::new_with_gas_coins(
        tx_kind,
        address,
        gas_objects,
        gas_budget,
        wallet.get_reference_gas_price().await?,
    );
    let tx = wallet.sign_transaction(&data);
    wallet.execute_transaction_may_fail(tx).await
}
