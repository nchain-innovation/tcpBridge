module tcpbridge::txid;

public struct TxID has copy, drop, store {
    bytes: vector<u8>
}

public fun new(txid: vector<u8>): TxID {
    if (txid.length() != 64) {
        abort(0)
    };
    TxID { bytes: txid }
}