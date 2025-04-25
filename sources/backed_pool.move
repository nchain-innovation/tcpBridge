module tcpbridge::backed_pool;

use blockchain_oracle::blockchain_oracle::{HeaderChain, get_chain_length};
use blockchain_oracle::spv::{MerkleProof, verify_spv};
use sui::balance::Balance;
use sui::clock::Clock;
use sui::table::{Table, new as new_table};
use tcpbridge::transactions::{Tx, OutPoint, tx_to_bytes, serialise, extract_pegout_input};
use tcpbridge::unbacked_pool::{UnbackedPool, get_pegout, is_genesis_elapsed, remove};

const COIN_VALUE: u64 = 10; // TEMPORARY VALUE
const MIN_PEGOUT_DELAY: u64 = 10; // TEMPORARY VALUE

// Error codes
const EInvalidGenesis: u64 = 0;
const EInvalidTokenValue: u64 = 1;
const EInvalidPegoutTime: u64 = 2;
const EInvalidMerkleProof: u64 = 3;
const EInvalidPegoutInput: u64 = 4;

public struct PegOutEntry<phantom T> has store {
    pegout: OutPoint,
    coin: Balance<T>, // TEMPORARY - It should be the Token itself
}

public struct BackedPool<phantom T> has key, store {
    id: UID,
    entry: Table<OutPoint, PegOutEntry<T>>, // Genesis -> (PegOut, TokenValue)
}

public(package) fun new<T>(ctx: &mut TxContext): BackedPool<T> {
    BackedPool { id: object::new(ctx), entry: new_table(ctx) }
}

/// PegIn against a given `genesis` in the `unbacked_pool`
public(package) fun pegin<T>(
    backed_pool: &mut BackedPool<T>,
    unbacked_pool: &mut UnbackedPool,
    genesis: OutPoint,
    coin: Balance<T>,
    clock: &Clock,
) {
    assert!(coin.value() >= COIN_VALUE, EInvalidTokenValue);
    assert!(is_genesis_elapsed(unbacked_pool, genesis, clock), EInvalidGenesis);

    // Update backed pool
    backed_pool
        .entry
        .add(genesis, PegOutEntry { pegout: get_pegout(unbacked_pool, genesis), coin });

    // Update unbacked pool
    remove(unbacked_pool, genesis);
}

/// PegOut against a given `genesis` in the `backed_pool`
public(package) fun pegout<T>(
    backed_pool: &mut BackedPool<T>,
    genesis: OutPoint,
    burning_tx: Tx,
    header_chain: &HeaderChain,
    merkle_proof: MerkleProof,
    block_count: u64,
): Balance<T> {
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
    // Update unbacked pool and return the balance
    let PegOutEntry { pegout: _, coin } = backed_pool.entry.remove(genesis);
    coin
}

/// Get token value wrapped in `genesis`
public(package) fun get_coin_value<T>(backed_pool: &BackedPool<T>, genesis: OutPoint): u64 {
    backed_pool.entry[genesis].coin.value()
}
