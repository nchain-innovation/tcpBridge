#[test_only]
module tcpbridge::transactions_tests;

use std::macros::range_do;
use std::unit_test::assert_eq;
use sui::hex::decode;

const DUMMY_TXID: vector<u8> = vector[
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];
const DUMMY_PEGOUT: vector<u8> = vector[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    14, 15, 16,
];

#[test]
fun test_outpoint_serialisation() {
    use tcpbridge::transactions::{new_txid, new_outpoint, serialise};
    let target_serialisation = decode(
        b"000000000000000000000000000000000000000000000000000000000000000004000000",
    );

    let outpoint = new_outpoint(new_txid(DUMMY_TXID), 4);
    assert_eq!(serialise(outpoint), target_serialisation);
}

#[test]
fun test_pegout_extraction() {
    use tcpbridge::transactions::{extract_pegout_input, new_tx};
    let mut reversed_pegout = DUMMY_PEGOUT;
    reversed_pegout.reverse();

    let mut dummy_tx: vector<u8> = vector::empty();
    dummy_tx.append(vector[1, 0, 0, 0, 1]); // Version, inputs
    dummy_tx.append(reversed_pegout);
    dummy_tx.append(vector[2, 0, 0, 0]); // Index
    range_do!(0, 40, |i| dummy_tx.push_back(i)); // Random entries

    assert_eq!(
        extract_pegout_input(new_tx(dummy_tx)),
        vector::flatten(vector[DUMMY_PEGOUT, vector[2, 0, 0, 0]]),
    );
}
