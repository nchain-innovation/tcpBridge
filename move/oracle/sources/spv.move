module blockchain_oracle::spv;

use blockchain_oracle::blockchain_oracle::HeaderChain;
use std::macros::range_do;

const INVALID_TX_LENGTH: u64 = 64;
const EInvalidTxLength: u64 = 0;
/*
    positions: vector of booleans where positions[i] = index & (1 << i), where index is the position of data in the Merkle tree
    hashes: vector of hashes where hash[i] is the hash on the Merkle path (connecting data to the root) at level i (where level 0 is the leaf level)
*/
public struct MerkleProof has drop {
    positions: vector<bool>,
    hashes: vector<vector<u8>>,
}

public fun new(positions: vector<bool>, hashes: vector<vector<u8>>): MerkleProof {
    MerkleProof {
        positions,
        hashes,
    }
}

/*
    target: the Merkle root
*/
public(package) fun verify_merkle_proof(
    data: vector<u8>,
    merkle_proof: MerkleProof,
    target: vector<u8>,
): bool {
    // Hash of the initial data
    let mut hash = std::hash::sha2_256(std::hash::sha2_256(data));
    // Verify Merkle Proof
    range_do!(0, merkle_proof.hashes.length(), |i| {
        if (merkle_proof.positions[i]) {
            hash =
                std::hash::sha2_256(
                    std::hash::sha2_256(vector::flatten(vector[merkle_proof.hashes[i], hash])),
                );
        } else {
            hash =
                std::hash::sha2_256(
                    std::hash::sha2_256(vector::flatten(vector[hash, merkle_proof.hashes[i]])),
                );
        }
    });
    target == hash
}

public fun verify_spv(
    tx: vector<u8>,
    merkle_proof: MerkleProof,
    block_height: u64,
    header_chain: &HeaderChain,
): bool {
    // Prevent attack described here: https://bitslog.com/2018/06/09/leaf-node-weakness-in-bitcoin-merkle-tree-design/
    // TO DO: Replace this with coinbase Merkle inclusion path when calling update_chain; store the length of the Merkle inclusion
    // path; then check the stored length against the length of merkle_proof.hashes.
    assert!(tx.length() != INVALID_TX_LENGTH, EInvalidTxLength);

    verify_merkle_proof(
        tx,
        merkle_proof,
        header_chain.get_block_header(block_height).get_hash_merkle_root(),
    )
}
