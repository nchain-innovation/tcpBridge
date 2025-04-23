module tcpbridge::unbacked_pool;

use sui::table::Table;
use tcpbridge::admin::BridgeAdmin;
use sui::clock::Clock;
use tcpbridge::txid::TxID;

const PEGIN_TIME: u64 = 10 * 60 * 1000; // 10 minutes

public struct UnbackedPool has key, store {
    id: UID,
    pegout: Table<TxID, TxID>, // Genesis -> Peg-out
    time: Table<TxID, u64> // Genesis -> Time
}

/// Add a new <Genesis, Peg-out> couple to the unbacked pool
public fun add(_: &BridgeAdmin, unbacked_pool: &mut UnbackedPool, genesis: TxID, pegout: TxID, clock: &Clock) {
    unbacked_pool.pegout.add(genesis, pegout);
    unbacked_pool.time.add(genesis, clock.timestamp_ms());
}

/// Remove entries <Genesis, Peg-out> for which the peg-in time has elapsed
public fun drop_elapsed(_: &BridgeAdmin, unbacked_pool: &mut UnbackedPool, genesis: TxID, clock: &Clock) {
    let genesis_clock = unbacked_pool.time[genesis];
    if (clock.timestamp_ms() - genesis_clock > PEGIN_TIME) {
        unbacked_pool.pegout.remove(genesis);
        unbacked_pool.time.remove(genesis);
    };
}

/// Remove entries <Genesis, Peg-out>
public(package) fun remove(unbacked_pool: &mut UnbackedPool, genesis: TxID) {
    unbacked_pool.pegout.remove(genesis);
    unbacked_pool.time.remove(genesis);
}

/// Query unbacked pool for <Genesis, Peg-out>
public fun is_valid_couple(unbacked_pool: &UnbackedPool, genesis: TxID, pegout: TxID): bool {
    // Validate pegout table
    let mut is_pegout_valid = unbacked_pool.pegout.contains(genesis);
    is_pegout_valid = is_pegout_valid && (unbacked_pool.pegout[genesis] == pegout);
    // Validate time table
    let is_time_valid = unbacked_pool.time.contains(genesis);

    is_pegout_valid && is_time_valid
}

/// Validate genesis
public fun is_valid_genesis(unbacked_pool: &UnbackedPool, genesis: TxID, clock: &Clock): bool {
    unbacked_pool.pegout.contains(genesis) && unbacked_pool.time.contains(genesis) && clock.timestamp_ms() - unbacked_pool.time[genesis] <= PEGIN_TIME
}

/// Retrive pegout
public(package) fun get_pegout(unbacked_pool: &UnbackedPool, genesis: TxID): TxID {
    unbacked_pool.pegout[genesis]
}