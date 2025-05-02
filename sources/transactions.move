module tcpbridge::transactions;

use std::macros::range_do;
use sui::address::from_bytes;
use sui::bcs;

const EInvalidTxid: u64 = 0;

const TXID_LENGTH: u64 = 32;
const INDEX_LENGTH: u64 = 4;
const PEGOUT_POSITION: u64 = 5; // PegOut is the first input
const ADDRESS_POSITION: u64 = 36; // Address position counting from last byte of Tx
const ADDRESS_LENGTH: u64 = 32;

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

/// === Outpoint methods ===

public(package) fun new_outpoint(txid: TxID, index: u32): OutPoint {
    OutPoint { txid, index }
}

public(package) fun serialise(outpoint: OutPoint): vector<u8> {
    vector::flatten(vector[outpoint.txid.bytes, bcs::to_bytes<u32>(&outpoint.index)])
}

/// === Tx methods ===

public(package) fun new_tx(tx: vector<u8>): Tx {
    Tx { bytes: tx }
}

public(package) fun tx_to_bytes(tx: Tx): vector<u8> {
    tx.bytes
}

public(package) fun extract_pegout_input(tx: Tx): vector<u8> {
    let mut pegout: vector<u8> = vector::empty();
    range_do!(PEGOUT_POSITION, PEGOUT_POSITION + TXID_LENGTH, |i| pegout.push_back(tx.bytes[i]));
    pegout.reverse();
    range_do!(
        PEGOUT_POSITION + TXID_LENGTH,
        PEGOUT_POSITION + TXID_LENGTH + INDEX_LENGTH,
        |i| pegout.push_back(tx.bytes[i]),
    );
    pegout
}

public(package) fun extract_address(tx: Tx): address {
    let address_relative_position = tx.bytes.length() - ADDRESS_POSITION;

    let mut address_bytes = vector::empty();
    range_do!(
        address_relative_position,
        address_relative_position + ADDRESS_LENGTH,
        |i| address_bytes.push_back(tx.bytes[i]),
    );

    from_bytes(address_bytes)
}
