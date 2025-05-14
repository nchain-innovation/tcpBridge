use std::str::FromStr;

use sui_jsonrpc::client::SUI_COIN_TYPE;
use sui_sdk::{
    SuiClient,
    types::{
        Identifier, SUI_CLOCK_OBJECT_ID, SUI_CLOCK_OBJECT_SHARED_VERSION, TypeTag,
        programmable_transaction_builder::ProgrammableTransactionBuilder,
        transaction::{ObjectArg, TransactionKind::ProgrammableTransaction},
    },
    wallet_context::WalletContext,
};

use crate::{
    cli::{BridgeEntry, ElapsedBridgeEntry, Pegin, Pegout},
    configs::{oracle_config, wallet_config},
    utils::{execute_transaction, get_coin},
};

const BRIDGE_IDENTIFIER: &str = "tcpbridge";

pub(crate) async fn add(
    client: SuiClient,
    new_bridge_entry: BridgeEntry,
) -> Result<(), anyhow::Error> {
    let (bridge_admin_ref, bridge_obj_arg, bridge_package_id) =
        crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call add
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge_admin = builder.obj(ObjectArg::ImmOrOwnedObject(bridge_admin_ref))?;
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(new_bridge_entry.genesis_txid)?)?;
    let genesis_index = builder.pure(new_bridge_entry.genesis_index)?;

    let pegout_txid = builder.pure(hex::decode(new_bridge_entry.pegout_txid)?)?;
    let pegout_index = builder.pure(new_bridge_entry.pegout_index)?;

    let clock = builder.obj(ObjectArg::SharedObject {
        id: SUI_CLOCK_OBJECT_ID,
        initial_shared_version: SUI_CLOCK_OBJECT_SHARED_VERSION,
        mutable: false,
    })?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("add")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![
            bridge_admin,
            bridge,
            genesis_txid,
            genesis_index,
            pegout_txid,
            pegout_index,
            clock,
        ],
    );

    // Execute the transaction
    let tx_kind =
        sui_sdk::types::transaction::TransactionKind::ProgrammableTransaction(builder.finish());
    let _response =
        crate::utils::execute_transaction(client, &wallet, active_address, vec![], tx_kind).await?;

    // Print transaction response
    //println!("Transaction executed successfully: {:?}", response);

    Ok(())
}

pub(crate) async fn is_valid_for_pegin(
    client: SuiClient,
    new_bridge_entry: BridgeEntry,
) -> Result<bool, anyhow::Error> {
    let (_, bridge_obj_arg, bridge_package_id) = crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call is_valid_for_pegin
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(new_bridge_entry.genesis_txid)?)?;
    let genesis_index = builder.pure(new_bridge_entry.genesis_index)?;

    let pegout_txid = builder.pure(hex::decode(new_bridge_entry.pegout_txid)?)?;
    let pegout_index = builder.pure(new_bridge_entry.pegout_index)?;

    let clock = builder.obj(ObjectArg::SharedObject {
        id: SUI_CLOCK_OBJECT_ID,
        initial_shared_version: SUI_CLOCK_OBJECT_SHARED_VERSION,
        mutable: false,
    })?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("is_valid_for_pegin")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![
            bridge,
            genesis_txid,
            genesis_index,
            pegout_txid,
            pegout_index,
            clock,
        ],
    );

    // Execute the transaction
    let tx_kind =
        sui_sdk::types::transaction::TransactionKind::ProgrammableTransaction(builder.finish());
    let response =
        crate::utils::execute_transaction(client, &wallet, active_address, vec![], tx_kind).await?;

    Ok(response.events.unwrap().data[0].parsed_json["is_valid"]
        .as_bool()
        .unwrap())
}

pub(crate) async fn is_valid_for_pegout(
    client: SuiClient,
    new_bridge_entry: BridgeEntry,
) -> Result<bool, anyhow::Error> {
    let (_, bridge_obj_arg, bridge_package_id) = crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call is_valid_for_pegout
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(new_bridge_entry.genesis_txid)?)?;
    let genesis_index = builder.pure(new_bridge_entry.genesis_index)?;

    let pegout_txid = builder.pure(hex::decode(new_bridge_entry.pegout_txid)?)?;
    let pegout_index = builder.pure(new_bridge_entry.pegout_index)?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("is_valid_for_pegout")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![
            bridge,
            genesis_txid,
            genesis_index,
            pegout_txid,
            pegout_index,
        ],
    );

    // Execute the transaction
    let tx_kind =
        sui_sdk::types::transaction::TransactionKind::ProgrammableTransaction(builder.finish());
    let response =
        crate::utils::execute_transaction(client, &wallet, active_address, vec![], tx_kind).await?;

    Ok(response.events.unwrap().data[0].parsed_json["is_valid"]
        .as_bool()
        .unwrap())
}

pub(crate) async fn drop_elapsed(
    client: SuiClient,
    elapsed_bridge_entry: ElapsedBridgeEntry,
) -> Result<(), anyhow::Error> {
    let (bridge_admin_ref, bridge_obj_arg, bridge_package_id) =
        crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call drop_elapsed
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge_admin = builder.obj(ObjectArg::ImmOrOwnedObject(bridge_admin_ref))?;
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(elapsed_bridge_entry.genesis_txid)?)?;
    let genesis_index = builder.pure(elapsed_bridge_entry.genesis_index)?;

    let clock = builder.obj(ObjectArg::SharedObject {
        id: SUI_CLOCK_OBJECT_ID,
        initial_shared_version: SUI_CLOCK_OBJECT_SHARED_VERSION,
        mutable: false,
    })?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("drop_elapsed")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![bridge_admin, bridge, genesis_txid, genesis_index, clock],
    );

    // Execute the transaction
    let tx_kind =
        sui_sdk::types::transaction::TransactionKind::ProgrammableTransaction(builder.finish());
    let _response =
        crate::utils::execute_transaction(client, &wallet, active_address, vec![], tx_kind).await?;

    Ok(())
}

pub(crate) async fn pegin(client: SuiClient, pegin: Pegin) -> Result<(), anyhow::Error> {
    let (_, bridge_obj_arg, bridge_package_id) = crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call pegout
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(pegin.genesis_txid)?)?;
    let genesis_index = builder.pure(pegin.genesis_index)?;

    let pegin_amount = builder.pure(pegin.pegin_amount)?;
    let coin = get_coin(&wallet, &active_address, pegin.pegin_amount).await?;
    let coin_arg = builder.obj(ObjectArg::ImmOrOwnedObject(coin))?;

    let clock = builder.obj(ObjectArg::SharedObject {
        id: SUI_CLOCK_OBJECT_ID,
        initial_shared_version: SUI_CLOCK_OBJECT_SHARED_VERSION,
        mutable: false,
    })?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("pegin")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![
            bridge,
            genesis_txid,
            genesis_index,
            coin_arg,
            pegin_amount,
            clock,
        ],
    );

    // Execute the transaction
    let tx_kind = ProgrammableTransaction(builder.finish());
    let _response =
        execute_transaction(client, &wallet, active_address, vec![coin.0], tx_kind).await?;

    Ok(())
}

pub(crate) async fn pegout(client: SuiClient, pegout: Pegout) -> Result<(), anyhow::Error> {
    let (header_chain_arg, _) = oracle_config(false);
    let (_, bridge_obj_arg, bridge_package_id) = crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call pegin
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(pegout.genesis_txid)?)?;
    let genesis_index = builder.pure(pegout.genesis_index)?;
    let burning_tx = builder.pure(hex::decode(pegout.burning_tx)?)?;

    let header_chain_obj = builder.obj(header_chain_arg)?;

    let merkle_proof_position = builder.pure(pegout.merkle_proof.positions)?;
    let merkle_proof_hashes = builder.pure(
        pegout
            .merkle_proof
            .hashes
            .iter()
            .map(|hash| hex::decode(hash).unwrap())
            .collect::<Vec<Vec<u8>>>(),
    )?;
    let block_height = builder.pure(pegout.block_height)?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("pegout")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![
            bridge,
            genesis_txid,
            genesis_index,
            burning_tx,
            header_chain_obj,
            merkle_proof_position,
            merkle_proof_hashes,
            block_height,
        ],
    );

    // Execute the transaction
    let tx_kind = ProgrammableTransaction(builder.finish());
    let _response = execute_transaction(client, &wallet, active_address, vec![], tx_kind).await?;

    Ok(())
}

pub(crate) async fn pegin_with_chunks(
    client: SuiClient,
    pegin: Pegin,
) -> Result<(), anyhow::Error> {
    let (_, bridge_obj_arg, bridge_package_id) = crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call pegin
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(pegin.genesis_txid)?)?;
    let genesis_index = builder.pure(pegin.genesis_index)?;

    let pegin_amount = builder.pure(pegin.pegin_amount)?;
    let coin = get_coin(&wallet, &active_address, pegin.pegin_amount).await?;
    let coin_arg = builder.obj(ObjectArg::ImmOrOwnedObject(coin))?;

    let clock = builder.obj(ObjectArg::SharedObject {
        id: SUI_CLOCK_OBJECT_ID,
        initial_shared_version: SUI_CLOCK_OBJECT_SHARED_VERSION,
        mutable: false,
    })?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("pegin_with_chunks")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![
            bridge,
            genesis_txid,
            genesis_index,
            coin_arg,
            pegin_amount,
            clock,
        ],
    );

    // Execute the transaction
    let tx_kind = ProgrammableTransaction(builder.finish());
    let _response =
        execute_transaction(client, &wallet, active_address, vec![coin.0], tx_kind).await?;

    Ok(())
}

pub(crate) async fn update_chunks(
    client: SuiClient,
    genesis_txid: String,
    genesis_index: u32,
    new_chunks: Vec<Vec<u8>>,
    chunks_index: u64,
) -> Result<(), anyhow::Error> {
    let (_, bridge_obj_arg, bridge_package_id) = crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Call pegin
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(genesis_txid)?)?;
    let genesis_index = builder.pure(genesis_index)?;
    let chunks_one = builder.pure(new_chunks[0].clone())?;
    let chunks_two = builder.pure(new_chunks[1].clone())?;
    let chunks_three = builder.pure(new_chunks[2].clone())?;
    let chunks_four = builder.pure(new_chunks[3].clone())?;
    let chunks_five = builder.pure(new_chunks[4].clone())?;
    let chunks_six = builder.pure(new_chunks[5].clone())?;
    let chunks_seven = builder.pure(new_chunks[6].clone())?;
    let chunks_eight = builder.pure(new_chunks[7].clone())?;
    let chunks_nine = builder.pure(new_chunks[8].clone())?;
    let chunks_ten = builder.pure(new_chunks[9].clone())?;
    let chunks_index = builder.pure(chunks_index)?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("update_chunks")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![
            bridge,
            genesis_txid,
            genesis_index,
            chunks_one,
            chunks_two,
            chunks_three,
            chunks_four,
            chunks_five,
            chunks_six,
            chunks_seven,
            chunks_eight,
            chunks_nine,
            chunks_ten,
            chunks_index,
        ],
    );

    // Execute the transaction
    let tx_kind = ProgrammableTransaction(builder.finish());
    let _response = execute_transaction(client, &wallet, active_address, vec![], tx_kind).await?;

    Ok(())
}

pub(crate) async fn pegout_with_chunks(
    client: SuiClient,
    pegout: Pegout,
) -> Result<(), anyhow::Error> {
    let (header_chain_arg, _) = oracle_config(false);
    let (_, bridge_obj_arg, bridge_package_id) = crate::configs::bridge_config(&client, true).await;
    let mut wallet = WalletContext::new(wallet_config(), None, None)?;
    let active_address = wallet.active_address()?;

    // Create chunks
    // burning_tx is ~ 330, we split it in four chunks: 100KB, 100KB, 100KB, remaining (max tx size is 128KB)
    // and then we split the chunks into parts of 10KB (16KB is max pure argument size)
    let burning_tx_bytes = hex::decode(pegout.burning_tx)?;
    let burning_tx_len = burning_tx_bytes.len();
    // Safety check
    assert!(burning_tx_len >= 320000);

    let mut burning_tx_chunks: Vec<Vec<Vec<u8>>> = vec![];
    for i in 0..3 {
        let mut chunks_to_add: Vec<Vec<u8>> = vec![];
        for j in 0..10 {
            chunks_to_add.push(
                burning_tx_bytes[100000 * i + 10000 * j..100000 * i + 10000 * (j + 1)].to_vec(),
            );
        }
        burning_tx_chunks.push(chunks_to_add);
    }
    let mut last_chunk: Vec<Vec<u8>> = vec![];
    last_chunk.push(burning_tx_bytes[300000..310000].to_vec());
    last_chunk.push(burning_tx_bytes[310000..320000].to_vec());
    if burning_tx_len >= 330000 {
        last_chunk.push(burning_tx_bytes[320000..330000].to_vec());
    } else {
        last_chunk.push(burning_tx_bytes[320000..].to_vec());
    }
    for _i in 0..7 {
        last_chunk.push(vec![]);
    }

    // Update chunks
    update_chunks(
        client.clone(),
        pegout.genesis_txid.clone(),
        pegout.genesis_index,
        burning_tx_chunks[0].clone(),
        0,
    )
    .await?;
    update_chunks(
        client.clone(),
        pegout.genesis_txid.clone(),
        pegout.genesis_index,
        burning_tx_chunks[1].clone(),
        1,
    )
    .await?;
    update_chunks(
        client.clone(),
        pegout.genesis_txid.clone(),
        pegout.genesis_index,
        burning_tx_chunks[2].clone(),
        2,
    )
    .await?;
    update_chunks(
        client.clone(),
        pegout.genesis_txid.clone(),
        pegout.genesis_index,
        last_chunk,
        3,
    )
    .await?;

    // Call pegout
    let mut builder = ProgrammableTransactionBuilder::new();

    // Arguments
    let bridge = builder.obj(bridge_obj_arg)?;

    let genesis_txid = builder.pure(hex::decode(pegout.genesis_txid)?)?;
    let genesis_index = builder.pure(pegout.genesis_index)?;

    let header_chain_obj = builder.obj(header_chain_arg)?;

    let merkle_proof_position = builder.pure(pegout.merkle_proof.positions)?;
    let merkle_proof_hashes = builder.pure(
        pegout
            .merkle_proof
            .hashes
            .iter()
            .map(|hash| hex::decode(hash).unwrap())
            .collect::<Vec<Vec<u8>>>(),
    )?;
    let block_height = builder.pure(pegout.block_height)?;

    builder.programmable_move_call(
        bridge_package_id,
        Identifier::from_str(BRIDGE_IDENTIFIER)?,
        Identifier::from_str("pegout_with_chunks")?,
        vec![TypeTag::from_str(SUI_COIN_TYPE)?],
        vec![
            bridge,
            genesis_txid,
            genesis_index,
            header_chain_obj,
            merkle_proof_position,
            merkle_proof_hashes,
            block_height,
        ],
    );

    // Execute the transaction
    let tx_kind = ProgrammableTransaction(builder.finish());
    let _response = execute_transaction(client, &wallet, active_address, vec![], tx_kind).await?;

    Ok(())
}
