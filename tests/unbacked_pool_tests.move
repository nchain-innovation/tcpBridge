#[test_only]
module tcpbridge::unbacked_pool_tests;

use std::unit_test::assert_eq;
use sui::clock::{Clock, create_for_testing, share_for_testing, increment_for_testing};
use sui::test_scenario;
use tcpbridge::admin::{BridgeAdmin, new_admin_cap};
use tcpbridge::transactions::{new_txid, new_outpoint};
use tcpbridge::unbacked_pool::{
    UnbackedPool,
    new,
    add,
    is_valid_couple,
    get_pegout,
    is_genesis_elapsed,
    drop_elapsed
};

const DUMMY_ADDRESS: address = @0xCAFE;
const DUMMY_TXID: vector<u8> = vector[
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];
const DUMMY_TXID_2: vector<u8> = vector[
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
];
const DUMMY_PEGOUT: vector<u8> = vector[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    14, 15, 16,
];
const DUMMY_PEGOUT_2: vector<u8> = vector[
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
];

#[test]
fun test_unbacked_pool() {
    // Create AdminCap, UnbackedPool, Clock
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    {
        new_admin_cap(scenario.ctx());
        let unbacked_pool = new(scenario.ctx());
        let clock = create_for_testing(scenario.ctx());
        transfer::public_share_object(unbacked_pool);
        share_for_testing(clock);
    };

    // Add a couple to the UnbackedPool and check its validity
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let admin_cap = test_scenario::take_from_address<BridgeAdmin>(&scenario, DUMMY_ADDRESS);
        let mut unbacked_pool = test_scenario::take_shared<UnbackedPool>(&scenario);
        let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
        let pegout = new_outpoint(new_txid(DUMMY_PEGOUT), 0);
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );
        assert_eq!(is_valid_couple(&unbacked_pool, genesis, pegout), true);
        test_scenario::return_shared(clock);
        test_scenario::return_to_address(DUMMY_ADDRESS, admin_cap);
        test_scenario::return_shared(unbacked_pool);
    };

    // Add another couple to the UnbackedPool, retrive pegout, remove elapsed
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let mut clock = test_scenario::take_shared<Clock>(&scenario);
        let admin_cap = test_scenario::take_from_address<BridgeAdmin>(&scenario, DUMMY_ADDRESS);
        let mut unbacked_pool = test_scenario::take_shared<UnbackedPool>(&scenario);
        let genesis = new_outpoint(new_txid(DUMMY_TXID_2), 0);
        let pegout = new_outpoint(new_txid(DUMMY_PEGOUT_2), 4);

        // Add new couple
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );

        // Retrive pegout for DUMMY_TXID
        let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
        let pegout = get_pegout(&unbacked_pool, genesis);
        assert_eq!(pegout, new_outpoint(new_txid(DUMMY_PEGOUT), 0));

        // Test validity of <Genesis: (PegOut, _)>
        assert_eq!(
            is_valid_couple(&unbacked_pool, genesis, new_outpoint(new_txid(DUMMY_PEGOUT), 4)),
            false,
        );
        assert_eq!(
            is_valid_couple(&unbacked_pool, genesis, new_outpoint(new_txid(DUMMY_PEGOUT_2), 0)),
            false,
        );

        // Move clock forward
        increment_for_testing(&mut clock, 10 * 60 * 1000  + 1);
        assert_eq!(is_genesis_elapsed(&unbacked_pool, genesis, &clock), true);

        // Remove elapsed
        drop_elapsed(&admin_cap, &mut unbacked_pool, genesis, &clock);

        // Check that elapsed genesis is removed
        assert_eq!(is_valid_couple(&unbacked_pool, genesis, pegout), false);

        // Return objects
        test_scenario::return_shared(clock);
        test_scenario::return_to_address(DUMMY_ADDRESS, admin_cap);
        test_scenario::return_shared(unbacked_pool);
    };

    scenario.end();
}
