module tcpbridge::tcpbridge;

use blockchain_oracle::blockchain_oracle::HeaderChain;
use blockchain_oracle::spv::new as new_merkle_proof;
use sui::clock::Clock;
use sui::coin::{Coin, from_balance, split};
use sui::event;
use sui::sui::SUI;
use tcpbridge::admin::BridgeAdmin;
use tcpbridge::backed_pool::{
    BackedPool,
    is_valid_couple as is_valid_couple_backed_pool,
    is_valid_couple_with_chunks,
    new as new_backed_pool,
    pegin as pegin_backed_pool,
    pegin_with_chunks as pegin_with_chunks_backed_pool,
    pegout as pegout_backed_pool,
    pegout_with_chunks as pegout_with_chunks_backed_pool,
    get_coin_value as get_coin_value_backed_pool,
    get_coin_value_with_chunks as get_coin_value_backed_pool_with_chunks,
    update_chunks as update_chunks_backed_pool
};
use tcpbridge::transactions::{new_tx, new_txid, new_outpoint, serialise};
use tcpbridge::unbacked_pool::{
    UnbackedPool,
    new as new_unbacked_pool,
    add as add_to_unbacked_pool,
    drop_elapsed as drop_elapsed_from_unbacked_pool,
    is_valid_couple as is_valid_couple_unbacked_pool,
    is_genesis_elapsed,
    get_pegout as get_pegout_unbacked_pool
};

const HEADER_CHAIN_ADDRESS: address =
    @0xca071c9725f9332c85bba033b30663050bd25bd68d97605bafcb33f88d62164e; // TEMPORARY VALUE - TO BE FILLED IN ONCE THE HEADER CHAIN HAS BEEN CREATED
const EInvalidHeaderChain: u64 = 0;

public struct IsValidGenesisEvent has copy, drop {
    is_valid: bool,
}

public struct PegOutEvent has copy, drop {
    pegout_serialisation: vector<u8>,
}

public struct CoinValueEvent has copy, drop {
    coin_value: u64,
}

public struct Bridge<phantom T> has key, store {
    id: UID,
    header_chain_id: ID,
    unbacked_pool: UnbackedPool,
    backed_pool: BackedPool<T>,
}

fun init(ctx: &mut TxContext) {
    let unbacked_pool = new_unbacked_pool(ctx);
    let backed_pool = new_backed_pool<SUI>(ctx);
    let bridge = Bridge {
        id: object::new(ctx),
        header_chain_id: object::id_from_address(HEADER_CHAIN_ADDRESS),
        unbacked_pool,
        backed_pool,
    };
    transfer::share_object(bridge);
}

/// === Unbacked pool methods ====

/// Add a new <Genesis: (PegOut, Time)> couple to the unbacked pool of the bridge
public entry fun add<T>(
    admin_cap: &BridgeAdmin,
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    pegout_txid: vector<u8>,
    pegout_index: u32,
    clock: &Clock,
) {
    add_to_unbacked_pool(
        admin_cap,
        &mut bridge.unbacked_pool,
        new_outpoint(new_txid(genesis_txid), genesis_index),
        new_outpoint(new_txid(pegout_txid), pegout_index),
        clock,
    );
}

/// Remove entries <Genesis: (PegOut, Time)> for which the PegIn time has elapsed
public entry fun drop_elapsed<T>(
    admin_cap: &BridgeAdmin,
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    clock: &Clock,
) {
    drop_elapsed_from_unbacked_pool(
        admin_cap,
        &mut bridge.unbacked_pool,
        new_outpoint(new_txid(genesis_txid), genesis_index),
        clock,
    );
}

/// Query the validity of <Genesis: (PegOut, Time)> in the unbacked pool
public entry fun is_valid_for_pegin<T>(
    bridge: &Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    pegout_txid: vector<u8>,
    pegout_index: u32,
    clock: &Clock,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let pegout = new_outpoint(new_txid(pegout_txid), pegout_index);
    let is_valid =
        is_valid_couple_unbacked_pool(
        &bridge.unbacked_pool,
        genesis,
        pegout,
    ) && !is_genesis_elapsed(
        &bridge.unbacked_pool,
        genesis,
        clock,
    );

    event::emit(IsValidGenesisEvent {
        is_valid,
    });
}

/// Retrive PegOut for <Genesis: (PegOut, _)>
public entry fun get_pegout<T>(bridge: &Bridge<T>, genesis_txid: vector<u8>, genesis_index: u32) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    event::emit(PegOutEvent {
        pegout_serialisation: serialise(get_pegout_unbacked_pool(&bridge.unbacked_pool, genesis)),
    });
}

/// ==== Backed pool methods ====

/// Query the validity of <Genesis: (PegOut, Time)> in the backed pool
public entry fun is_valid_for_pegout<T>(
    bridge: &Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    pegout_txid: vector<u8>,
    pegout_index: u32,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let pegout = new_outpoint(new_txid(pegout_txid), pegout_index);
    let is_valid = is_valid_couple_backed_pool(
        &bridge.backed_pool,
        genesis,
        pegout,
    );

    event::emit(IsValidGenesisEvent {
        is_valid,
    });
}

/// PegIn against a given `genesis` in the `unbacked_pool`
public entry fun pegin<T>(
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    coin: &mut Coin<T>,
    pegin_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let pegin_coin = coin.split(pegin_amount, ctx);

    pegin_backed_pool(
        &mut bridge.backed_pool,
        &mut bridge.unbacked_pool,
        genesis,
        pegin_coin,
        clock,
    );
}

/// PegOut against a given `genesis` in the `backed_pool`
public entry fun pegout<T>(
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    burning_tx: vector<u8>,
    header_chain: &HeaderChain,
    merkle_proof_positions: vector<bool>,
    merkle_proof_hashes: vector<vector<u8>>,
    block_height: u64,
    ctx: &mut TxContext,
) {
    // Validate HeaderChain
    let header_chain_address = object::id(header_chain);
    assert!(header_chain_address == bridge.header_chain_id, EInvalidHeaderChain);
    // Retrieve PegOutEntry
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let balance = pegout_backed_pool(
        &mut bridge.backed_pool,
        genesis,
        new_tx(burning_tx),
        header_chain,
        new_merkle_proof(merkle_proof_positions, merkle_proof_hashes),
        block_height,
        ctx,
    );
    // Transfer coins to sender
    transfer::public_transfer(from_balance(balance, ctx), ctx.sender())
}

/// Get value of the coin wrapped in `genesis`
public entry fun get_coin_value<T>(
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    event::emit(CoinValueEvent {
        coin_value: get_coin_value_backed_pool(&bridge.backed_pool, genesis),
    });
}

/// ==== Backed pool methods with chunks ====

/// Query the validity of <Genesis: (PegOut, Time)> in the backed pool
public entry fun is_valid_for_pegout_with_chunks<T>(
    bridge: &Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    pegout_txid: vector<u8>,
    pegout_index: u32,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let pegout = new_outpoint(new_txid(pegout_txid), pegout_index);
    let is_valid = is_valid_couple_with_chunks(
        &bridge.backed_pool,
        genesis,
        pegout,
    );

    event::emit(IsValidGenesisEvent {
        is_valid,
    });
}

/// PegIn against a given `genesis` in the `unbacked_pool`
public entry fun pegin_with_chunks<T>(
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    coin: &mut Coin<T>,
    pegin_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let pegin_coin = coin.split(pegin_amount, ctx);

    pegin_with_chunks_backed_pool(
        &mut bridge.backed_pool,
        &mut bridge.unbacked_pool,
        genesis,
        pegin_coin,
        clock,
        ctx,
    );
}

/// PegOut against a given `genesis` in the `backed_pool`
public entry fun pegout_with_chunks<T>(
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    header_chain: &HeaderChain,
    merkle_proof_positions: vector<bool>,
    merkle_proof_hashes: vector<vector<u8>>,
    block_height: u64,
    ctx: &mut TxContext,
) {
    // Validate HeaderChain
    let header_chain_address = object::id(header_chain);
    assert!(header_chain_address == bridge.header_chain_id, EInvalidHeaderChain);
    // Retrieve PegOutEntry
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let balance = pegout_with_chunks_backed_pool(
        &mut bridge.backed_pool,
        genesis,
        header_chain,
        new_merkle_proof(merkle_proof_positions, merkle_proof_hashes),
        block_height,
        ctx,
    );
    // Transfer coins to sender
    transfer::public_transfer(from_balance(balance, ctx), ctx.sender())
}

/// Update burning_tx chunks for `genesis`
/// It overrides previous values
public entry fun update_chunks<T>(
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    chunk_one: vector<u8>,
    chunk_two: vector<u8>,
    chunk_three: vector<u8>,
    chunk_four: vector<u8>,
    chunk_five: vector<u8>,
    chunk_six: vector<u8>,
    chunk_seven: vector<u8>,
    chunk_eight: vector<u8>,
    chunk_nine: vector<u8>,
    chunk_ten: vector<u8>,
    chunks_index: u64,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let mut new_chunks = vector::empty();
    new_chunks.push_back(chunk_one);
    new_chunks.push_back(chunk_two);
    new_chunks.push_back(chunk_three);
    new_chunks.push_back(chunk_four);
    new_chunks.push_back(chunk_five);
    new_chunks.push_back(chunk_six);
    new_chunks.push_back(chunk_seven);
    new_chunks.push_back(chunk_eight);
    new_chunks.push_back(chunk_nine);
    new_chunks.push_back(chunk_ten);
    update_chunks_backed_pool(
        &mut bridge.backed_pool,
        genesis,
        new_chunks,
        chunks_index,
    );
}

/// Get value of the coin wrapped in `genesis`
public entry fun get_coin_value_with_chunks<T>(
    bridge: &mut Bridge<T>,
    genesis_txid: vector<u8>,
    genesis_index: u32,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    event::emit(CoinValueEvent {
        coin_value: get_coin_value_backed_pool_with_chunks(&bridge.backed_pool, genesis),
    });
}

/// ==== Test-code ====

#[test_only]
public(package) fun new_bridge_for_test(
    header_chain_address: address,
    ctx: &mut TxContext,
): Bridge<SUI> {
    let unbacked_pool = new_unbacked_pool(ctx);
    let backed_pool = new_backed_pool<SUI>(ctx);
    let bridge = Bridge {
        id: object::new(ctx),
        header_chain_id: object::id_from_address(header_chain_address),
        unbacked_pool,
        backed_pool,
    };
    bridge
}
