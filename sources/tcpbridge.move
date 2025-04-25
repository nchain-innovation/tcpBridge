module tcpbridge::tcpbridge;

use blockchain_oracle::blockchain_oracle::HeaderChain;
use blockchain_oracle::spv::new as new_merkle_proof;
use sui::clock::Clock;
use tcpbridge::admin::BridgeAdmin;
use tcpbridge::backed_pool::{
    BackedPool,
    new as new_backed_pool,
    pegin as pegoin_backed_pool,
    pegout as pegout_backed_pool,
    get_token_value as get_token_value_backed_pool
};
use tcpbridge::transactions::{new_tx, new_txid, new_outpoint, serialise};
use tcpbridge::unbacked_pool::{
    UnbackedPool,
    new as new_unbacked_pool,
    add as add_to_unbacked_pool,
    drop_elapsed as drop_elapsed_from_unbacked_pool,
    is_valid_couple,
    is_genesis_elapsed,
    get_pegout as get_pegout_unbacked_pool
};

const HEADER_CHAIN_ADDRESS: address = @0x1; // TEMPORARY VALUE - TO BE FILLED IN ONCE THE HEADER CHAIN HAS BEEN CREATED
const EInvalidHeaderChain: u64 = 0;

public struct Bridge has key, store {
    id: UID,
    header_chain_id: ID,
    unbacked_pool: UnbackedPool,
    backed_pool: BackedPool,
}

fun init(ctx: &mut TxContext) {
    let unbacked_pool = new_unbacked_pool(ctx);
    let backed_pool = new_backed_pool(ctx);
    let bridge = Bridge {
        id: object::new(ctx),
        header_chain_id: object::id_from_address(HEADER_CHAIN_ADDRESS),
        unbacked_pool,
        backed_pool,
    };
    transfer::share_object(bridge);
}

/// Unbacked pool methods

/// Add a new <Genesis: (PegOut, Time)> couple to the unbacked pool of the bridge
public entry fun add(
    admin_cap: &BridgeAdmin,
    bridge: &mut Bridge,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    pegout_txid: vector<u8>,
    pegout_index: u32,
    clock: &Clock,
    _ctx: &mut TxContext,
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
public entry fun drop_elapsed(
    adming_cap: &BridgeAdmin,
    bridge: &mut Bridge,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    drop_elapsed_from_unbacked_pool(
        adming_cap,
        &mut bridge.unbacked_pool,
        new_outpoint(new_txid(genesis_txid), genesis_index),
        clock,
    );
}

/// Query the validity of <Genesis: (PegOut, Time)> in the unbacked pool
public entry fun is_valid(
    bridge: &Bridge,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    pegout_txid: vector<u8>,
    pegout_index: u32,
    clock: &Clock,
    _ctx: &mut TxContext,
): bool {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    let pegout = new_outpoint(new_txid(pegout_txid), pegout_index);
    is_valid_couple(
        &bridge.unbacked_pool,
        genesis,
        pegout,
    ) && !is_genesis_elapsed(
        &bridge.unbacked_pool,
        genesis,
        clock,
    )
}

/// Retrive PegOut for <Genesis: (PegOut, _)>
public entry fun get_pegout(
    bridge: &Bridge,
    genesis_txid: vector<u8>,
    genesis_index: u32,
): vector<u8> {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    serialise(get_pegout_unbacked_pool(&bridge.unbacked_pool, genesis))
}

/// Backed pool methods

/// PegIn against a given `genesis` in the `unbacked_pool`
public entry fun pegin(
    bridge: &mut Bridge,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    token_value: u64,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    pegoin_backed_pool(
        &mut bridge.backed_pool,
        &mut bridge.unbacked_pool,
        genesis,
        token_value,
        clock,
    );
}

/// PegOut against a given `genesis` in the `backed_pool`
public entry fun pegout(
    bridge: &mut Bridge,
    genesis_txid: vector<u8>,
    genesis_index: u32,
    burning_tx: vector<u8>,
    header_chain: &HeaderChain,
    merkle_proof_positions: vector<bool>,
    merkle_proof_hashes: vector<vector<u8>>,
    block_count: u64,
    ctx: &mut TxContext, // THIS IS MEANT TO BE USED TO RETURN THE TOKENS TO THE SENDER
) {
    // Validate HeaderChain
    let header_chain_address = object::id(header_chain);
    assert!(header_chain_address == bridge.header_chain_id, EInvalidHeaderChain);
    // Execute pegout
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    pegout_backed_pool(
        &mut bridge.backed_pool,
        genesis,
        new_tx(burning_tx),
        header_chain,
        new_merkle_proof(merkle_proof_positions, merkle_proof_hashes),
        block_count,
    );
}

/// Get value of the token wrapped in `genesis`
public entry fun get_token_value(
    bridge: &mut Bridge,
    genesis_txid: vector<u8>,
    genesis_index: u32,
): u64 {
    let genesis = new_outpoint(new_txid(genesis_txid), genesis_index);
    get_token_value_backed_pool(&bridge.backed_pool, genesis)
}
