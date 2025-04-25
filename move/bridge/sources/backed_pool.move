module tcpbridge::backed_pool;

use blockchain_oracle::blockchain_oracle::{HeaderChain, get_chain_height};
use blockchain_oracle::spv::{MerkleProof, verify_spv};
use std::macros::range_do;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::coin::{Coin, into_balance};
use sui::table::{Table, new as new_table, drop};
use tcpbridge::transactions::{
    Tx,
    OutPoint,
    tx_to_bytes,
    new_tx,
    serialise,
    extract_pegout_input,
    extract_address
};
use tcpbridge::unbacked_pool::{UnbackedPool, get_pegout, is_genesis_elapsed, remove};

const COIN_VALUE: u64 = 10; // TEMPORARY VALUE
const MIN_PEGOUT_DELAY: u64 = 0; // TEMPORARY VALUE
const N_CHUNKS_BURNING_TX: u64 = 4;

/// Error codes
const EInvalidGenesis: u64 = 0;
const EInvalidCoinValue: u64 = 1;
const EInvalidPegoutTime: u64 = 2;
const EInvalidMerkleProof: u64 = 3;
const EInvalidPegoutInput: u64 = 4;
const EInvalidTxSender: u64 = 5;

public struct PegOutEntry<phantom T> has store {
    pegout: OutPoint,
    coin: Balance<T>,
}

// PegOut entry with chunks of the burning tx
// Used to work around the size limit of pure arguments, to be removed when the
// burning tx goes down to a small size
public struct PegOutEntryWithChunks<phantom T> has store {
    pegout: OutPoint,
    coin: Balance<T>,
    burning_tx_chunks: Table<u64, vector<u8>>, // Split the tx into chunks of 100KB, 100KB, 100KB, remaining
}

public struct BackedPool<phantom T> has key, store {
    id: UID,
    entry: Table<OutPoint, PegOutEntry<T>>, // Genesis -> (PegOut, TokenValue)
    entry_with_chunks: Table<OutPoint, PegOutEntryWithChunks<T>>, // Genesis -> (PegOut, TokenValue, BurningTxChunks)
}

public(package) fun new<T>(ctx: &mut TxContext): BackedPool<T> {
    BackedPool { id: object::new(ctx), entry: new_table(ctx), entry_with_chunks: new_table(ctx) }
}

/// PegIn against a given `genesis` in the `unbacked_pool`
public(package) fun pegin<T>(
    backed_pool: &mut BackedPool<T>,
    unbacked_pool: &mut UnbackedPool,
    genesis: OutPoint,
    coin: Coin<T>,
    clock: &Clock,
) {
    assert!(coin.value() >= COIN_VALUE, EInvalidCoinValue);
    assert!(!is_genesis_elapsed(unbacked_pool, genesis, clock), EInvalidGenesis);

    // Update backed pool
    backed_pool
        .entry
        .add(
            genesis,
            PegOutEntry { pegout: get_pegout(unbacked_pool, genesis), coin: into_balance(coin) },
        );

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
    block_height: u64,
    ctx: &TxContext,
): Balance<T> {
    // Validate pegout time
    assert!(get_chain_height(header_chain) - block_height >= MIN_PEGOUT_DELAY, EInvalidPegoutTime);
    // Validate spv
    assert!(
        verify_spv(tx_to_bytes(burning_tx), merkle_proof, block_height, header_chain),
        EInvalidMerkleProof,
    );
    // Validate input
    assert!(backed_pool.entry.contains(genesis), EInvalidGenesis);
    assert!(
        serialise(backed_pool.entry[genesis].pegout) == extract_pegout_input(burning_tx),
        EInvalidPegoutInput,
    );
    // Validate transaction sender
    assert!(extract_address(burning_tx) == ctx.sender(), EInvalidTxSender);
    // Update unbacked pool and return the balance
    let PegOutEntry { pegout: _, coin } = backed_pool.entry.remove(genesis);
    coin
}

/// Get token value wrapped in `genesis`
public(package) fun get_coin_value<T>(backed_pool: &BackedPool<T>, genesis: OutPoint): u64 {
    backed_pool.entry[genesis].coin.value()
}

/// Check if a given `genesis` is valid in the `backed_pool`
public(package) fun is_valid_genesis<T>(backed_pool: &BackedPool<T>, genesis: OutPoint): bool {
    backed_pool.entry.contains(genesis)
}

/// Query the validity of <Genesis: (PegOut, _)>
public(package) fun is_valid_couple<T>(
    backed_pool: &BackedPool<T>,
    genesis: OutPoint,
    pegout: OutPoint,
): bool {
    // Validate `genesis` as a key
    if (backed_pool.entry.contains(genesis)) {
        backed_pool.entry[genesis].pegout == pegout
    } else {
        false
    }
}

/// === WithChunks methods ===

/// PegIn against a given `genesis` in the `unbacked_pool` using chunks
public(package) fun pegin_with_chunks<T>(
    backed_pool: &mut BackedPool<T>,
    unbacked_pool: &mut UnbackedPool,
    genesis: OutPoint,
    coin: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(coin.value() >= COIN_VALUE, EInvalidCoinValue);
    assert!(!is_genesis_elapsed(unbacked_pool, genesis, clock), EInvalidGenesis);

    // Update backed pool
    backed_pool
        .entry_with_chunks
        .add(
            genesis,
            PegOutEntryWithChunks {
                pegout: get_pegout(unbacked_pool, genesis),
                coin: into_balance(coin),
                burning_tx_chunks: new_table(ctx),
            },
        );

    // Update unbacked pool
    remove(unbacked_pool, genesis);
}

/// Update burning_tx chunks for `genesis`
/// It overrides previous values
public(package) fun update_chunks<T>(
    backed_pool: &mut BackedPool<T>,
    genesis: OutPoint,
    new_chunks: vector<vector<u8>>,
    chunks_index: u64,
) {
    // Validate input
    assert!(backed_pool.entry_with_chunks.contains(genesis), EInvalidGenesis);

    // Remove values
    if (backed_pool.entry_with_chunks[genesis].burning_tx_chunks.contains(chunks_index)) {
        backed_pool.entry_with_chunks[genesis].burning_tx_chunks.remove(chunks_index);
    };

    // Update chunks
    backed_pool
        .entry_with_chunks[genesis]
        .burning_tx_chunks
        .add(chunks_index, new_chunks.flatten());
}

/// PegOut against a given `genesis` in the `backed_pool`
public(package) fun pegout_with_chunks<T>(
    backed_pool: &mut BackedPool<T>,
    genesis: OutPoint,
    header_chain: &HeaderChain,
    merkle_proof: MerkleProof,
    block_height: u64,
    ctx: &TxContext,
): Balance<T> {
    // Validate genesis
    assert!(backed_pool.entry_with_chunks.contains(genesis), EInvalidGenesis);
    // Construct burning_tx
    let mut burning_tx_bytes = vector::empty<u8>();
    range_do!(
        0,
        N_CHUNKS_BURNING_TX,
        |i| burning_tx_bytes.append(backed_pool.entry_with_chunks[genesis].burning_tx_chunks[i]),
    );
    let burning_tx = new_tx(burning_tx_bytes);
    // Validate pegout time
    assert!(get_chain_height(header_chain) - block_height >= MIN_PEGOUT_DELAY, EInvalidPegoutTime);
    // Validate spv
    assert!(
        verify_spv(burning_tx_bytes, merkle_proof, block_height, header_chain),
        EInvalidMerkleProof,
    );
    // Validate input
    assert!(
        serialise(backed_pool.entry_with_chunks[genesis].pegout) == extract_pegout_input(burning_tx),
        EInvalidPegoutInput,
    );
    // Validate transaction sender
    assert!(extract_address(burning_tx) == ctx.sender(), EInvalidTxSender);
    // Update backed pool and return the balance
    let PegOutEntryWithChunks { pegout: _, coin, burning_tx_chunks } = backed_pool
        .entry_with_chunks
        .remove(genesis);
    drop(burning_tx_chunks);
    coin
}

/// Get token value wrapped in `genesis`
public(package) fun get_coin_value_with_chunks<T>(
    backed_pool: &BackedPool<T>,
    genesis: OutPoint,
): u64 {
    backed_pool.entry_with_chunks[genesis].coin.value()
}

/// Check if a given `genesis` is valid in the `backed_pool`
public(package) fun is_valid_genesis_with_chunks<T>(
    backed_pool: &BackedPool<T>,
    genesis: OutPoint,
): bool {
    backed_pool.entry_with_chunks.contains(genesis)
}

/// Query the validity of <Genesis: (PegOut, _)>
public(package) fun is_valid_couple_with_chunks<T>(
    backed_pool: &BackedPool<T>,
    genesis: OutPoint,
    pegout: OutPoint,
): bool {
    // Validate `genesis` as a key
    if (backed_pool.entry_with_chunks.contains(genesis)) {
        backed_pool.entry_with_chunks[genesis].pegout == pegout
    } else {
        false
    }
}

/// === Test code ===

/// PegOut against a given `genesis` in the `backed_pool`
public fun pegout_for_test<T>(
    backed_pool: &mut BackedPool<T>,
    genesis: OutPoint,
    burning_tx: Tx,
    header_chain: &HeaderChain,
    merkle_proof: MerkleProof,
    block_height: u64,
    pegout_delay: u64,
    ctx: &TxContext,
): Balance<T> {
    // Validate pegout time
    assert!(get_chain_height(header_chain) - block_height >= pegout_delay, EInvalidPegoutTime);
    // Validate spv
    assert!(
        verify_spv(tx_to_bytes(burning_tx), merkle_proof, block_height, header_chain),
        EInvalidMerkleProof,
    );
    // Validate input
    assert!(backed_pool.entry.contains(genesis), EInvalidGenesis);
    assert!(
        serialise(backed_pool.entry[genesis].pegout) == extract_pegout_input(burning_tx),
        EInvalidPegoutInput,
    );
    // Validate transaction sender
    assert!(extract_address(burning_tx) == ctx.sender(), EInvalidTxSender);
    // Update unbacked pool and return the balance
    let PegOutEntry { pegout: _, coin } = backed_pool.entry.remove(genesis);
    coin
}

/// PegOut against a given `genesis` in the `backed_pool`
public fun pegout_with_chunks_for_test<T>(
    backed_pool: &mut BackedPool<T>,
    genesis: OutPoint,
    header_chain: &HeaderChain,
    merkle_proof: MerkleProof,
    block_height: u64,
    pegout_delay: u64,
    ctx: &TxContext,
): Balance<T> {
    // Validate genesis
    assert!(backed_pool.entry_with_chunks.contains(genesis), EInvalidGenesis);
    // Construct burning_tx
    let mut burning_tx_bytes = vector::empty<u8>();
    range_do!(
        0,
        N_CHUNKS_BURNING_TX,
        |i| burning_tx_bytes.append(backed_pool.entry_with_chunks[genesis].burning_tx_chunks[i]),
    );
    let burning_tx = new_tx(burning_tx_bytes);
    // Validate pegout time
    assert!(get_chain_height(header_chain) - block_height >= pegout_delay, EInvalidPegoutTime);
    // Validate spv
    assert!(
        verify_spv(burning_tx_bytes, merkle_proof, block_height, header_chain),
        EInvalidMerkleProof,
    );
    // Validate input
    assert!(
        serialise(backed_pool.entry_with_chunks[genesis].pegout) == extract_pegout_input(burning_tx),
        EInvalidPegoutInput,
    );
    // Validate transaction sender
    assert!(extract_address(burning_tx) == ctx.sender(), EInvalidTxSender);
    // Update backed pool and return the balance
    let PegOutEntryWithChunks { pegout: _, coin, burning_tx_chunks } = backed_pool
        .entry_with_chunks
        .remove(genesis);
    drop(burning_tx_chunks);
    coin
}
