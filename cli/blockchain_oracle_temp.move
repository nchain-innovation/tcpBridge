module blockchain_oracle::blockchain_oracle;

use blockchain_oracle::block_header::{{
    BlockHeader,
    deserialise_block_header,
    compute_block_hash,
    get_target
}};
use std::macros::range_do;
use sui::bcs;

const GENESIS_BLOCK: vector<u8> = vector{genesis_block};
const GENESIS_HASH: vector<u8> = vector{genesis_hash};
const GENESIS_HEIGHT: u64 = {genesis_height}; // TEMPORARY - DEPENDS ON WHERE THE ORACLE STARTS
const GENESIS_CHAIN_WORK: u256 = {geesis_chain_work}; // TEMPORARY - DEPENDS ON WHERE THE ORACLE STARTS

/// Error codes
const EInvalidBlockHeader: u64 = 0;
const EInvalidForkIndex: u64 = 1;
const EInvalidBlockHeight: u64 = 2;

public struct HeaderChain has key, store {{
    id: UID,
    genesis_height: u64,
    headers: vector<BlockHeader>,
    hashes: vector<vector<u8>>,
    chain_work: vector<u256>,
}}

/// === Private functions ====

fun init(ctx: &mut TxContext) {{
    let initial_block: BlockHeader = deserialise_block_header(GENESIS_BLOCK);
    let headers: vector<BlockHeader> = vector[initial_block];
    let hashes: vector<vector<u8>> = vector[GENESIS_HASH];
    let chain_work: vector<u256> = vector[GENESIS_CHAIN_WORK];

    transfer::share_object(HeaderChain {{
        id: object::new(ctx),
        genesis_height: GENESIS_HEIGHT,
        headers,
        hashes,
        chain_work,
    }});
}}

fun validate_candidate_block_header(
    tip_block_header: &BlockHeader,
    tip_block_hash: vector<u8>,
    candidate_block_header: &BlockHeader,
): (u256, vector<u8>, bool) {{
    // Assert new block is on top of previous one
    let is_built_on_top = tip_block_hash == candidate_block_header.get_hash_prev_block();
    // Assert hash is smaller than target
    let target = get_target(candidate_block_header);
    let block_hash = compute_block_hash(candidate_block_header);
    let is_block_hash_below_target = bcs::new(block_hash).peel_u256() < target;
    // Assert target is within bounds
    let prev_target = get_target(tip_block_header);
    let is_target_within_bounds = (prev_target / 2 <= target) && (target <= prev_target * 2);

    (target, block_hash, is_built_on_top && is_block_hash_below_target && is_target_within_bounds)
}}

fun pop_back(header_chain: &mut HeaderChain) {{
    header_chain.headers.pop_back();
    header_chain.hashes.pop_back();
    header_chain.chain_work.pop_back();
}}

/// === Public functions ===

public fun get_chain_height(header_chain: &HeaderChain): u64 {{
    header_chain.headers.length() + header_chain.genesis_height - 1
}}

public fun get_best_block_header(header_chain: &HeaderChain): BlockHeader {{
    header_chain.headers[header_chain.headers.length()-1]
}}

public fun get_best_block_hash(header_chain: &HeaderChain): vector<u8> {{
    header_chain.hashes[header_chain.hashes.length()-1]
}}

public fun get_block_header(header_chain: &HeaderChain, block_height: u64): BlockHeader {{
    assert!(block_height >= header_chain.genesis_height, EInvalidBlockHeight);
    let block_height = block_height - header_chain.genesis_height;
    header_chain.headers[block_height]
}}

public fun get_block_hash(header_chain: &HeaderChain, block_height: u64): vector<u8> {{
    assert!(block_height >= header_chain.genesis_height, EInvalidBlockHeight);
    let block_height = block_height - header_chain.genesis_height;
    header_chain.hashes[block_height]
}}

public entry fun update_chain(header_chain: &mut HeaderChain, serialisation: vector<u8>) {{
    let block_header = deserialise_block_header(serialisation);
    let (target, block_hash, valid_block) = validate_candidate_block_header(
        &header_chain.get_best_block_header(),
        header_chain.get_best_block_hash(),
        &block_header,
    );
    // Update chain - SHALL WE THROW AN ERROR HERE?
    if (valid_block) {{
        // Calculate chain work - follow https://github.com/bitcoin-sv/bitcoin-sv/blob/86eb5e8bdf5573c3cd844a1d81bd4fb151b909e0/src/block_index.cpp#L105
        let chain_work =
            header_chain.chain_work[header_chain.chain_work.length()-1] + (target.bitwise_not() / (target + 1) + 1);
        header_chain.headers.push_back(block_header);
        header_chain.hashes.push_back(block_hash);
        header_chain.chain_work.push_back(chain_work);
    }}
}}

public entry fun reorg_chain(
    header_chain: &mut HeaderChain,
    fork_index: u64,
    serialisations: vector<vector<u8>>,
) {{
    // Forking index must be less than the height of the chain
    assert!(fork_index < header_chain.get_chain_height(), EInvalidForkIndex);

    // Create forked chain
    let mut forked_headers = vector[header_chain.headers[fork_index - GENESIS_HEIGHT]];
    let mut forked_hashes = vector[header_chain.hashes[fork_index - GENESIS_HEIGHT]];
    let mut forked_chain_work = vector[header_chain.chain_work[fork_index - GENESIS_HEIGHT]];

    range_do!(0, serialisations.length(), |i| {{
        let block_header = deserialise_block_header(serialisations[i]);
        let (target, block_hash, valid_block) = validate_candidate_block_header(
            &forked_headers[i-1],
            forked_hashes[i-1],
            &block_header,
        );
        if (valid_block) {{
            let chain_work = forked_chain_work[i-1] + (target.bitwise_not() / (target + 1) + 1);
            forked_headers.push_back(block_header);
            forked_hashes.push_back(block_hash);
            forked_chain_work.push_back(chain_work);
        }} else {{
            assert!(false, EInvalidBlockHeader);
        }}
    }});

    // Check that the chain work of the forked chain is greater than the chain work of the active chain
    if (
        forked_chain_work[forked_chain_work.length()-1] > header_chain.chain_work[header_chain.chain_work.length()-1]
    ) {{
        // Remove old headers
        range_do!(
            fork_index - GENESIS_HEIGHT,
            header_chain.headers.length(),
            |_| header_chain.pop_back(),
        );
        // Add new headers
        range_do!(1, forked_headers.length(), |i| {{
            header_chain.headers.push_back(forked_headers[i]);
            header_chain.hashes.push_back(forked_hashes[i]);
            header_chain.chain_work.push_back(forked_chain_work[i]);
        }});
    }}
}}

/// === Test-code ===

#[test_only]
public fun new_header_chain(
    genesis_height: u64,
    genesis_block: vector<u8>,
    chain_work: u256,
    ctx: &mut TxContext,
): HeaderChain {{
    let initial_block: BlockHeader = deserialise_block_header(genesis_block);
    let headers: vector<BlockHeader> = vector[initial_block];
    let hashes: vector<vector<u8>> = vector[compute_block_hash(&initial_block)];
    let chain_work: vector<u256> = vector[chain_work];

    HeaderChain {{
        id: object::new(ctx),
        genesis_height,
        headers,
        hashes,
        chain_work,
    }}
}}

#[test_only]
public fun access_headers(header_chain: &HeaderChain, index: u64): BlockHeader {{
    header_chain.headers[index]
}}

#[test_only]
public fun access_hashes(header_chain: &HeaderChain, index: u64): vector<u8> {{
    header_chain.hashes[index]
}}

#[test_only]
public fun lengths(header_chain: &HeaderChain): (u64, u64) {{
    (header_chain.headers.length(), header_chain.hashes.length())
}}

#[test_only]
public fun batch_update_chain(header_chain: &mut HeaderChain, serialisations: vector<vector<u8>>) {{
    range_do!(0, serialisations.length(), |i| {{
        let serialisation = serialisations[i];
        update_chain(header_chain, serialisation);
    }});
}}
