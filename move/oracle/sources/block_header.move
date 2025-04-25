module blockchain_oracle::block_header;

use std::macros::range_do;
use sui::bcs;

const InvalidSerialisationLength: u64 = 0;

// BlockHeaderObject
public struct BlockHeader has copy, drop, store {
    version: u32,
    hash_prev_block: vector<u8>,
    hash_merkle_root: vector<u8>,
    time: u32,
    bits: vector<u8>,
    nonce: u32,
}

public fun serialise_block_header(block_header: &BlockHeader): vector<u8> {
    let mut serialisation = vector::empty<u8>();
    // BCS serialises in little-endian, so no need to reverse order
    serialisation.append(bcs::to_bytes(&block_header.version));
    serialisation.append(block_header.hash_prev_block);
    serialisation.append(block_header.hash_merkle_root);
    serialisation.append(bcs::to_bytes(&block_header.time));
    serialisation.append(block_header.bits);
    serialisation.append(bcs::to_bytes(&block_header.nonce));
    serialisation
}

public(package) fun deserialise_block_header(serialisation: vector<u8>): BlockHeader {
    assert!(serialisation.length() == 80, InvalidSerialisationLength);

    let mut version_bytes = vector::empty<u8>();
    range_do!(0, 4, |i| version_bytes.push_back(serialisation[i]));
    let mut hash_prev_block = vector::empty<u8>();
    range_do!(4, 36, |i| hash_prev_block.push_back(serialisation[i]));
    let mut hash_merkle_root = vector::empty<u8>();
    range_do!(36, 68, |i| hash_merkle_root.push_back(serialisation[i]));
    let mut time_bytes = vector::empty<u8>();
    range_do!(68, 72, |i| time_bytes.push_back(serialisation[i]));
    let mut bits = vector::empty<u8>();
    range_do!(72, 76, |i| bits.push_back(serialisation[i]));
    let mut nonce_bytes = vector::empty<u8>();
    range_do!(76, 80, |i| nonce_bytes.push_back(serialisation[i]));

    BlockHeader {
        version: bcs::new(version_bytes).peel_u32(),
        hash_prev_block,
        hash_merkle_root,
        time: bcs::new(time_bytes).peel_u32(),
        bits,
        nonce: bcs::new(nonce_bytes).peel_u32(),
    }
}

public fun compute_block_hash(block_header: &BlockHeader): vector<u8> {
    std::hash::sha2_256(std::hash::sha2_256(serialise_block_header(block_header)))
}

public fun get_hash_prev_block(block_header: &BlockHeader): vector<u8> {
    block_header.hash_prev_block
}

public fun get_hash_merkle_root(block_header: &BlockHeader): vector<u8> {
    block_header.hash_merkle_root
}

public(package) fun bits_to_target(bits: vector<u8>): u256 {
    // Compute 256^(bits[3] - 3)
    let order = std::u256::pow(0x100, bcs::new(vector[bits[3]]).peel_u8() - 3);
    // Compute mantissa
    let mut mantissa_vec: vector<u8> = vector::empty();
    range_do!(0, 3, |i| mantissa_vec.push_back(bits[i]));
    mantissa_vec.push_back(0);
    let mantissa = bcs::new(mantissa_vec).peel_u32();
    // Compute target
    order * (mantissa as u256)
}

public fun get_target(block_header: &BlockHeader): u256 {
    bits_to_target(block_header.bits)
}

/// === Test-code ===

#[test_only]
public fun new_block_header(
    version: u32,
    hash_prev_block: vector<u8>,
    hash_merkle_root: vector<u8>,
    time: u32,
    bits: vector<u8>,
    nonce: u32,
): BlockHeader {
    BlockHeader {
        version,
        hash_prev_block,
        hash_merkle_root,
        time,
        bits,
        nonce,
    }
}
