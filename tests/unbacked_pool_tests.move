#[test_only]
module tcpbridge::unbacked_pool_tests;

use std::unit_test::assert_eq;
use sui::clock::{Clock, create_for_testing, share_for_testing, increment_for_testing};
use sui::test_scenario::{Self, Scenario};
use tcpbridge::admin::{BridgeAdmin, new_admin_cap};
use tcpbridge::transactions::{new_txid, new_outpoint, OutPoint};
use tcpbridge::unbacked_pool::{
    UnbackedPool,
    add,
    is_valid_couple,
    get_pegout,
    is_genesis_elapsed,
    drop_elapsed,
    new as new_unbacked_pool
};

const DUMMY_ADDRESS: address = @0xCAFE;
const DUMMY_TXID: vector<u8> = vector[
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];
const DUMMY_PEGOUT: vector<u8> = vector[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    14, 15, 16,
];

/// === Helper functions ===

/// Initialise objects for the tests
fun initialise_test(scenario: &mut Scenario) {
    new_admin_cap(scenario.ctx());
    let unbacked_pool = new_unbacked_pool(scenario.ctx());
    let clock = create_for_testing(scenario.ctx());

    // Transfers
    transfer::public_share_object(unbacked_pool);
    share_for_testing(clock);
}

/// Retrieve standard objects
fun retrive_objects(scenario: &Scenario): (Clock, BridgeAdmin, UnbackedPool) {
    let clock = test_scenario::take_shared<Clock>(scenario);
    let admin_cap = test_scenario::take_from_address<BridgeAdmin>(scenario, DUMMY_ADDRESS);
    let unbacked_pool = test_scenario::take_shared<UnbackedPool>(scenario);

    (clock, admin_cap, unbacked_pool)
}

/// Return objects to inventory
fun return_to_inventory(clock: Clock, admin_cap: BridgeAdmin, unbacked_pool: UnbackedPool) {
    test_scenario::return_shared<Clock>(clock);
    test_scenario::return_shared<UnbackedPool>(unbacked_pool);
    test_scenario::return_to_address<BridgeAdmin>(DUMMY_ADDRESS, admin_cap);
}

fun test_is_genesis_elapsed_error(wrong_genesis: OutPoint) {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let pegout = new_outpoint(new_txid(DUMMY_PEGOUT), 0);

    // Create AdminCap, UnbackedPool, Clock
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    initialise_test(&mut scenario);

    // Add a couple to the UnbackedPool
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, mut unbacked_pool) = retrive_objects(&scenario);
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );
        is_genesis_elapsed(&unbacked_pool, wrong_genesis, &clock);

        return_to_inventory(clock, admin_cap, unbacked_pool);
    };

    scenario.end();
}

/// === Tests ===
#[test]
fun test_drop_elapsed() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let pegout = new_outpoint(new_txid(DUMMY_PEGOUT), 0);

    // Create AdminCap, UnbackedPool, Clock
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    initialise_test(&mut scenario);

    // Add a couple to the UnbackedPool and check its validity
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, mut unbacked_pool) = retrive_objects(&scenario);
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );
        assert_eq!(is_valid_couple(&unbacked_pool, genesis, pegout), true);
        return_to_inventory(clock, admin_cap, unbacked_pool);
    };

    // Move clock forward
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (mut clock, admin_cap, mut unbacked_pool) = retrive_objects(&scenario);
        increment_for_testing(&mut clock, 10 * 60 * 1000 + 1);

        // Check that genesis is elapsed
        assert_eq!(
            is_genesis_elapsed(&unbacked_pool, new_outpoint(new_txid(DUMMY_TXID), 0), &clock),
            true,
        );

        // Remove elapsed
        drop_elapsed(&admin_cap, &mut unbacked_pool, new_outpoint(new_txid(DUMMY_TXID), 0), &clock);

        // Check that elapsed genesis is removed
        assert_eq!(
            is_valid_couple(
                &unbacked_pool,
                new_outpoint(new_txid(DUMMY_TXID), 0),
                new_outpoint(new_txid(DUMMY_PEGOUT), 0),
            ),
            false,
        );

        return_to_inventory(clock, admin_cap, unbacked_pool);
    };

    scenario.end();
}

#[test]
fun test_drop_elapsed_invalid() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let pegout = new_outpoint(new_txid(DUMMY_PEGOUT), 0);

    // Create AdminCap, UnbackedPool, Clock
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    initialise_test(&mut scenario);

    // Add a couple to the UnbackedPool and check its validity
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, mut unbacked_pool) = retrive_objects(&scenario);
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );
        assert_eq!(is_valid_couple(&unbacked_pool, genesis, pegout), true);
        return_to_inventory(clock, admin_cap, unbacked_pool);
    };

    // Try to drop when time has not elapsed
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, mut unbacked_pool) = retrive_objects(&scenario);

        drop_elapsed(&admin_cap, &mut unbacked_pool, genesis, &clock);

        // Check that elapsed genesis is not removed
        assert_eq!(is_valid_couple(&unbacked_pool, genesis, pegout), true);

        // Return objects
        return_to_inventory(clock, admin_cap, unbacked_pool);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = ::tcpbridge::unbacked_pool::EInvalidGenesis)]
fun test_is_genesis_elapsed_error_one() {
    test_is_genesis_elapsed_error(new_outpoint(new_txid(DUMMY_PEGOUT), 0)) // Wrong TXID
}

#[test, expected_failure(abort_code = ::tcpbridge::unbacked_pool::EInvalidGenesis)]
fun test_is_genesis_elapsed_error_two() {
    test_is_genesis_elapsed_error(new_outpoint(new_txid(DUMMY_TXID), 1)) // Wrong index
}

#[test]
fun test_get_pegout() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let pegout = new_outpoint(new_txid(DUMMY_PEGOUT), 0);

    // Create AdminCap, UnbackedPool, Clock
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    initialise_test(&mut scenario);

    // Add a couple to the UnbackedPool and check its validity
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, mut unbacked_pool) = retrive_objects(&scenario);
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );

        // Retrive pegout for DUMMY_TXID
        assert_eq!(get_pegout(&unbacked_pool, genesis), pegout);

        return_to_inventory(clock, admin_cap, unbacked_pool);
    };

    scenario.end();
}
