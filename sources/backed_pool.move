module tcpbridge::backed_pool;

use blockchain_oracle::blockchain_oracle::{HeaderChain, get_chain_length};
use blockchain_oracle::spv::{MerkleProof, verify_spv};
use sui::clock::Clock;
use sui::table::{Table, new as new_table};
use tcpbridge::transactions::{Tx, OutPoint, tx_to_bytes, serialise, extract_pegout_input};
use tcpbridge::unbacked_pool::{UnbackedPool, get_pegout, is_genesis_elapsed, remove};

const TOKEN_VALUE: u64 = 10; // TEMPORARY VALUE
const MIN_PEGOUT_DELAY: u64 = 10; // TEMPORARY VALUE

// Error codes
const EInvalidGenesis: u64 = 0;
const EInvalidTokenValue: u64 = 1;
const EInvalidPegoutTime: u64 = 2;
const EInvalidMerkleProof: u64 = 3;
const EInvalidPegoutInput: u64 = 4;

public struct PegOutEntry has drop, store {
    pegout: OutPoint,
    token_value: u64, // TEMPORARY - It should be the Token itself
}

public struct BackedPool has key, store {
    id: UID,
    entry: Table<OutPoint, PegOutEntry>, // Genesis -> (PegOut, TokenValue)
}

public(package) fun new(ctx: &mut TxContext): BackedPool {
    BackedPool { id: object::new(ctx), entry: new_table(ctx) }
}

/// PegIn against a given `genesis` in the `unbacked_pool`
public(package) fun pegin(
    backed_pool: &mut BackedPool,
    unbacked_pool: &mut UnbackedPool,
    genesis: OutPoint,
    token_value: u64,
    clock: &Clock,
) {
    assert!(token_value >= TOKEN_VALUE, EInvalidTokenValue);
    assert!(is_genesis_elapsed(unbacked_pool, genesis, clock), EInvalidGenesis);

    // Update backed pool
    backed_pool
        .entry
        .add(genesis, PegOutEntry { pegout: get_pegout(unbacked_pool, genesis), token_value });

    // Update unbacked pool
    remove(unbacked_pool, genesis);
}

/// PegOut against a given `genesis` in the `backed_pool`
public(package) fun pegout(
    backed_pool: &mut BackedPool,
    genesis: OutPoint,
    burning_tx: Tx,
    header_chain: &HeaderChain,
    merkle_proof: MerkleProof,
    block_count: u64,
): u64 {
    // Validate pegout time
    assert!(get_chain_length(header_chain) - block_count >= MIN_PEGOUT_DELAY, EInvalidPegoutTime);
    // Validate spv
    assert!(
        verify_spv(tx_to_bytes(burning_tx), merkle_proof, block_count, header_chain),
        EInvalidMerkleProof,
    );
    // Validate input
    assert!(backed_pool.entry.contains(genesis), EInvalidGenesis);
    assert!(
        serialise(backed_pool.entry[genesis].pegout) == extract_pegout_input(burning_tx),
        EInvalidPegoutInput,
    );
    // Extract token
    let token_value = backed_pool.entry[genesis].token_value;
    // Update backed pool
    backed_pool.entry.remove(genesis);
    // Return token
    token_value
}

/// Get token value wrapped in `genesis`
public(package) fun get_token_value(backed_pool: &BackedPool, genesis: OutPoint): u64 {
    backed_pool.entry[genesis].token_value
}
