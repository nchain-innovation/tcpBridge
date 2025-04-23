module tcpbridge::backed_pool;

use sui::table::Table;
use tcpbridge::txid::TxID;
use tcpbridge::unbacked_pool::UnbackedPool;
use tcpbridge::unbacked_pool::get_pegout;
use tcpbridge::unbacked_pool::is_valid_genesis;
use tcpbridge::unbacked_pool::remove;
use sui::clock::Clock;

const TOKEN_VALUE: u64 = 10; // TEMPORARY VALUE

// Error codes
const EInvalidTokenValue: u64 = 0;
const EInvalidGenesis: u64 = 1;

public struct BackedPool has key, store {
    id: UID,
    pegout: Table<TxID, TxID>, // Genesis -> Peg-out
    token: Table<TxID, u64> // Genesis -> Token
}

public fun pegin(
    backed_pool: &mut BackedPool,
    unbacked_pool: &mut UnbackedPool,
    genesis: TxID,
    token: u64,
    clock: &Clock,
    _ctx: &mut TxContext
) {
    assert!(token == TOKEN_VALUE, EInvalidTokenValue);
    assert!(is_valid_genesis(unbacked_pool, genesis, clock), EInvalidGenesis);

    // Update backed pool
    backed_pool.pegout.add(genesis, get_pegout(unbacked_pool, genesis));
    backed_pool.token.add(genesis, token);

    // Update unbacked pool
    remove(unbacked_pool, genesis);
}