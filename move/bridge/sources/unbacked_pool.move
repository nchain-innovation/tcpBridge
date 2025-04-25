module tcpbridge::unbacked_pool;

use sui::clock::Clock;
use sui::table::{Table, new as new_table};
use tcpbridge::admin::BridgeAdmin;
use tcpbridge::transactions::OutPoint;

const PEGIN_TIME: u64 = 10 * 60 * 1000; // 10 minutes

/// Error codes
const EInvalidGenesis: u64 = 0;

public struct PegOutEntry has drop, store {
    pegout: OutPoint,
    time: u64,
}

public struct UnbackedPool has key, store {
    id: UID,
    entry: Table<OutPoint, PegOutEntry>, // Genesis -> (PegOut, Time)
}

public(package) fun new(ctx: &mut TxContext): UnbackedPool {
    UnbackedPool { id: object::new(ctx), entry: new_table(ctx) }
}

/// Add a new <Genesis: (PegOut, Time)> couple to the unbacked pool
public(package) fun add(
    _: &BridgeAdmin,
    unbacked_pool: &mut UnbackedPool,
    genesis: OutPoint,
    pegout: OutPoint,
    clock: &Clock,
) {
    unbacked_pool.entry.add(genesis, PegOutEntry { pegout, time: clock.timestamp_ms() });
}

/// Remove entries <Genesis: (PegOut, Time)> for which the PegIn time has elapsed
public(package) fun drop_elapsed(
    _: &BridgeAdmin,
    unbacked_pool: &mut UnbackedPool,
    genesis: OutPoint,
    clock: &Clock,
) {
    // No check for `genesis` in `unbacked_pool.entry`, the BridgeAdmin is supposed to check this
    let genesis_clock = unbacked_pool.entry[genesis].time;
    if (clock.timestamp_ms() - genesis_clock > PEGIN_TIME) {
        unbacked_pool.entry.remove(genesis);
    };
}

/// Remove entries <Genesis: (PegOut, Time)>
public(package) fun remove(unbacked_pool: &mut UnbackedPool, genesis: OutPoint) {
    unbacked_pool.entry.remove(genesis);
}

/// Query the validity of <Genesis: (PegOut, _)>
public(package) fun is_valid_couple(
    unbacked_pool: &UnbackedPool,
    genesis: OutPoint,
    pegout: OutPoint,
): bool {
    // Validate `genesis` as a key
    if (unbacked_pool.entry.contains(genesis)) {
        unbacked_pool.entry[genesis].pegout == pegout
    } else {
        false
    }
}

/// Query whether <Genesis: (_, _)> is elapsed
public(package) fun is_genesis_elapsed(
    unbacked_pool: &UnbackedPool,
    genesis: OutPoint,
    clock: &Clock,
): bool {
    // Validate `genesis` as a key
    assert!(unbacked_pool.entry.contains(genesis), EInvalidGenesis);
    // Is PegIn time for `genesis` elapsed?
    clock.timestamp_ms() - unbacked_pool.entry[genesis].time > PEGIN_TIME
}

/// Retrive PegOut for <Genesis: (PegOut, _)>
public(package) fun get_pegout(unbacked_pool: &UnbackedPool, genesis: OutPoint): OutPoint {
    unbacked_pool.entry[genesis].pegout
}
