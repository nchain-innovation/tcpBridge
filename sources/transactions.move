module tcpbridge::transactions;

use std::macros::range_do;
use sui::bcs;

const EInvalidTxid: u64 = 0;

const TXID_LENGTH: u64 = 32;
const PEGOUT_POSITION: u64 = 4; // The PegOut is the first input
const INPUT_LENGTH: u64 = 36;

public struct Tx has copy, drop, store {
    bytes: vector<u8>,
}

public struct TxID has copy, drop, store {
    bytes: vector<u8>,
}

public struct OutPoint has copy, drop, store {
    txid: TxID,
    index: u32,
}

public(package) fun new_txid(txid: vector<u8>): TxID {
    assert!(txid.length() == TXID_LENGTH, EInvalidTxid);
    TxID { bytes: txid }
}

public(package) fun new_outpoint(txid: TxID, index: u32): OutPoint {
    OutPoint { txid, index }
}

public(package) fun new_tx(tx: vector<u8>): Tx {
    Tx { bytes: tx }
}

public(package) fun tx_to_bytes(tx: Tx): vector<u8> {
    tx.bytes
}

public(package) fun extract_pegout_input(tx: Tx): vector<u8> {
    let mut pegout: vector<u8> = vector::empty();
    range_do!(PEGOUT_POSITION, PEGOUT_POSITION + INPUT_LENGTH, |i| pegout.push_back(tx.bytes[i]));
    pegout
}

public(package) fun serialise(outpoint: OutPoint): vector<u8> {
    vector::flatten(vector[outpoint.txid.bytes, bcs::to_bytes<u32>(&outpoint.index)])
}
