#[test_only]
module tcpbridge::backed_pool_tests;

use blockchain_oracle::blockchain_oracle::{new_header_chain, HeaderChain};
use blockchain_oracle::spv::{MerkleProof, new as new_merkle_proof};
use std::macros::range_do;
use std::unit_test::assert_eq;
use sui::clock::{Clock, create_for_testing, share_for_testing, increment_for_testing};
use sui::coin::{Coin, mint_for_testing, from_balance};
use sui::hex::decode;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use tcpbridge::admin::{BridgeAdmin, new_admin_cap};
use tcpbridge::backed_pool::{
    BackedPool,
    new as new_backed_pool,
    is_valid_genesis,
    is_valid_genesis_with_chunks,
    is_valid_couple as is_valid_couple_in_backed,
    is_valid_couple_with_chunks,
    pegin,
    pegin_with_chunks,
    pegout_for_test,
    pegout_with_chunks_for_test,
    get_coin_value,
    get_coin_value_with_chunks,
    update_chunks
};
use tcpbridge::transactions::{new_txid, new_tx, new_outpoint, OutPoint, Tx};
use tcpbridge::unbacked_pool::{
    UnbackedPool,
    new as new_unbacked_pool,
    add,
    is_valid_couple as is_valid_couple_in_unbacked
};

const DUMMY_ADDRESS: address = @0xCAFE;
const DUMMY_TXID: vector<u8> = vector[
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];
const DUMMY_PEGOUT: vector<u8> = vector[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    14, 15, 16,
];

/// Constants generated in regtest
const HEADER_SERIALISATION: vector<u8> =
    b"0000002004cb4b91a317b4babfacd2f4118431c383ff652b67bda8277f3062fc77a84f75ed6b67f888a5cc7888db0534bd0d2379ff5c4e630cd63b5622fd2981712ff18d0ccb1468ffff7f2006000000";
const HEADER_CHAIN_WORK: u256 = 0x16e;
const TX_SERIALISATION: vector<u8> =
    b"01000000031f8f95028358060d751b9dc66b800f4518c4ea7a196925df9cb49d5507f53a99000000006b483045022100b084e9c8f2f7490e17bde4a12287e70c0d4c177b8c038d8e05959af3d0239c3b0220407037a722dacd1d979fda6a56c116f7c1f2b98b8cc8d6efc23ae5962f8c09bb412103ecf8c9f7b1e840514726022ea6782ed2f7f809f209ec0249a3769e0bc3dea8e0000000009de98f6e47ee3c4fca3a12dee81e0a8ee84b9e38dc51d8846fb471ea2229b6be000000006b483045022100e75c0f605a2e34d10d1586292dbf8ff578d4da3d145959ab5170374f384a3b150220393e13a50f4da7249c0ad8b408910ac054a68806c2a64517e97fc21308cd20b3412103ecf8c9f7b1e840514726022ea6782ed2f7f809f209ec0249a3769e0bc3dea8e000000000f356aa93859eeb02d401c3bc7caa43a9fb71b695e6fcfc12d88b64ed1646b843000000006b4830450221008ec2e3f23e4b9092480d242cb85c2875f533525e47fe9407ef2279493b7cbfa702201ca622653f3226e5e39d613ee2e614e9845e42a3f70c26942ba3154edade5a05412103ecf8c9f7b1e840514726022ea6782ed2f7f809f209ec0249a3769e0bc3dea8e00000000001000000000000000023006a20000000000000000000000000000000000000000000000000000000000000cafe00000000";
const PEGOUT: vector<u8> = b"993af507559db49cdf2569197aeac418450f806bc69d1b750d06588302958f1f";
const PEGOUT_INDEX: u32 = 0;

/// === Helper functions ===

/// Initialise objects for the tests
fun initialise_test(sui_value: u64, scenario: &mut Scenario) {
    new_admin_cap(scenario.ctx());
    let unbacked_pool = new_unbacked_pool(scenario.ctx());
    let backed_pool = new_backed_pool<SUI>(scenario.ctx());
    let clock = create_for_testing(scenario.ctx());
    // Mint SUI to dummy address
    let minted_sui = mint_for_testing<SUI>(sui_value, scenario.ctx());
    // HeaderChain
    let header_chain = new_header_chain(
        0,
        decode(HEADER_SERIALISATION),
        HEADER_CHAIN_WORK,
        scenario.ctx(),
    );

    // Transfers
    transfer::public_transfer(minted_sui, DUMMY_ADDRESS);
    transfer::public_share_object(unbacked_pool);
    transfer::public_share_object(backed_pool);
    transfer::public_share_object(header_chain);
    share_for_testing(clock);
}

/// Retrieve standard objects
fun retrive_objects(scenario: &Scenario): (Clock, BridgeAdmin, UnbackedPool, BackedPool<SUI>) {
    let clock = test_scenario::take_shared<Clock>(scenario);
    let admin_cap = test_scenario::take_from_address<BridgeAdmin>(scenario, DUMMY_ADDRESS);
    let unbacked_pool = test_scenario::take_shared<UnbackedPool>(scenario);
    let backed_pool = test_scenario::take_shared<BackedPool<SUI>>(scenario);

    (clock, admin_cap, unbacked_pool, backed_pool)
}

/// Return objects to inventory
fun return_to_inventory(
    clock: Clock,
    admin_cap: BridgeAdmin,
    unbacked_pool: UnbackedPool,
    backed_pool: BackedPool<SUI>,
) {
    test_scenario::return_shared<Clock>(clock);
    test_scenario::return_shared<UnbackedPool>(unbacked_pool);
    test_scenario::return_shared<BackedPool<SUI>>(backed_pool);
    test_scenario::return_to_address<BridgeAdmin>(DUMMY_ADDRESS, admin_cap);
}

/// Initialise and PegIn
fun initialise_and_pegin(genesis: OutPoint, pegout: OutPoint, scenario: &mut Scenario) {
    // Create AdminCap, UnbackedPool, BackedPool, Clock, Mint SUI
    {
        initialise_test(10, scenario);
    };

    // Add a couple to the UnBackedPool and fail PegIn
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, mut unbacked_pool, mut backed_pool) = retrive_objects(scenario);

        // Add to unbacked pool
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );

        // PegIn
        let coin = test_scenario::take_from_address<Coin<SUI>>(scenario, DUMMY_ADDRESS);
        pegin(&mut backed_pool, &mut unbacked_pool, genesis, coin, &clock);

        // Check unbacked pool
        assert_eq!(is_valid_couple_in_unbacked(&unbacked_pool, genesis, pegout), false);

        // Check backed pool
        assert_eq!(is_valid_couple_in_backed(&backed_pool, genesis, pegout), true);

        // Check value of coin
        assert_eq!(get_coin_value(&backed_pool, genesis), 10);

        // Return objects
        return_to_inventory(clock, admin_cap, unbacked_pool, backed_pool);
    };
}

/// Initialise and PegIn
fun initialise_and_pegin_with_chunks(genesis: OutPoint, pegout: OutPoint, scenario: &mut Scenario) {
    // Create AdminCap, UnbackedPool, BackedPool, Clock, Mint SUI
    {
        initialise_test(10, scenario);
    };

    // Add a couple to the UnBackedPool and fail PegIn
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, mut unbacked_pool, mut backed_pool) = retrive_objects(scenario);

        // Add to unbacked pool
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );

        // PegIn
        let coin = test_scenario::take_from_address<Coin<SUI>>(scenario, DUMMY_ADDRESS);
        pegin_with_chunks(
            &mut backed_pool,
            &mut unbacked_pool,
            genesis,
            coin,
            &clock,
            scenario.ctx(),
        );

        // Check unbacked pool
        assert_eq!(is_valid_couple_in_unbacked(&unbacked_pool, genesis, pegout), false);

        // Check backed pool
        assert_eq!(is_valid_couple_with_chunks(&backed_pool, genesis, pegout), true);

        // Check value of coin
        assert_eq!(get_coin_value_with_chunks(&backed_pool, genesis), 10);

        // Return objects
        return_to_inventory(clock, admin_cap, unbacked_pool, backed_pool);
    };
}

/// Failed PegOut
fun failed_pegout(
    genesis: OutPoint,
    burning_tx: Tx,
    merkle_proof: MerkleProof,
    block_height: u64,
    pegout_delay: u64,
    sender: address,
) {
    let correct_genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let correct_pegout = new_outpoint(new_txid(decode(PEGOUT)), PEGOUT_INDEX);

    // Create AdminCap, UnbackedPool, BackedPool, Clock, Mint SUI, HeaderChain
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    initialise_and_pegin(correct_genesis, correct_pegout, &mut scenario);

    // PegOut
    scenario.next_tx(sender);
    {
        let (clock, admin_cap, unbacked_pool, mut backed_pool) = retrive_objects(&scenario);
        let header_chain = test_scenario::take_shared<HeaderChain>(&scenario);

        // Failed PegOut
        let balance = pegout_for_test(
            &mut backed_pool,
            genesis,
            burning_tx,
            &header_chain,
            merkle_proof,
            block_height,
            pegout_delay,
            scenario.ctx(),
        );

        // Return objects
        return_to_inventory(clock, admin_cap, unbacked_pool, backed_pool);
        test_scenario::return_shared<HeaderChain>(header_chain);
        transfer::public_transfer(from_balance(balance, scenario.ctx()), DUMMY_ADDRESS)
    };

    scenario.end();
}

/// === Tests ====

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidGenesis)]
fun test_elapsed_pegin() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let pegout = new_outpoint(new_txid(DUMMY_PEGOUT), 0);

    // Create AdminCap, UnbackedPool, BackedPool, Clock, Mint SUI
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    {
        initialise_test(10, &mut scenario);
    };

    // Add a couple to the UnBackedPool and fail PegIn
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (mut clock, admin_cap, mut unbacked_pool, mut backed_pool) = retrive_objects(&scenario);

        // Add to unbacked pool
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );

        // Move clock
        increment_for_testing(&mut clock, 10 * 60 * 1000 + 1);

        // Failed PegIn because elapsed time
        let coin = test_scenario::take_from_address<Coin<SUI>>(&scenario, DUMMY_ADDRESS);
        pegin(&mut backed_pool, &mut unbacked_pool, genesis, coin, &clock);

        // Return objects
        return_to_inventory(clock, admin_cap, unbacked_pool, backed_pool);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidCoinValue)]
fun test_low_value_pegin() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let pegout = new_outpoint(new_txid(DUMMY_PEGOUT), 0);

    // Create AdminCap, UnbackedPool, BackedPool, Clock, Mint SUI
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    {
        initialise_test(9, &mut scenario);
    };

    // Add a couple to the UnBackedPool and fail PegIn
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, mut unbacked_pool, mut backed_pool) = retrive_objects(&scenario);

        // Add to unbacked pool
        add(
            &admin_cap,
            &mut unbacked_pool,
            genesis,
            pegout,
            &clock,
        );

        // Failed PegIn because of low value
        let coin = test_scenario::take_from_address<Coin<SUI>>(&scenario, DUMMY_ADDRESS);
        pegin(&mut backed_pool, &mut unbacked_pool, genesis, coin, &clock);

        // Return objects
        return_to_inventory(clock, admin_cap, unbacked_pool, backed_pool);
    };

    scenario.end();
}

#[test]
fun test_pegin_pegout() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let pegout = new_outpoint(new_txid(decode(PEGOUT)), PEGOUT_INDEX);

    // Create AdminCap, UnbackedPool, BackedPool, Clock, Mint SUI, HeaderChain
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    initialise_and_pegin(genesis, pegout, &mut scenario);

    // PegOut
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, unbacked_pool, mut backed_pool) = retrive_objects(&scenario);
        let header_chain = test_scenario::take_shared<HeaderChain>(&scenario);

        // PegOut
        let burning_tx = new_tx(decode(TX_SERIALISATION));
        let positions = vector[true];
        let hashes = vector[
            decode(b"f77209250e07087f098d3397772a8fa1b63ac475d1c32e7196653c5e42cc80e2"),
        ];
        let balance = pegout_for_test(
            &mut backed_pool,
            genesis,
            burning_tx,
            &header_chain,
            new_merkle_proof(positions, hashes),
            0,
            0,
            scenario.ctx(),
        );
        assert_eq!(balance.value(), 10);

        // Check backed pool
        assert_eq!(is_valid_genesis(&backed_pool, genesis), false);
        assert_eq!(is_valid_couple_in_backed(&backed_pool, genesis, pegout), false);

        // Return objects
        return_to_inventory(clock, admin_cap, unbacked_pool, backed_pool);
        test_scenario::return_shared<HeaderChain>(header_chain);
        transfer::public_transfer(from_balance(balance, scenario.ctx()), DUMMY_ADDRESS)
    };

    scenario.end();
}

#[test]
fun test_pegin_pegout_with_chunks() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let pegout = new_outpoint(new_txid(decode(PEGOUT)), PEGOUT_INDEX);

    // Create AdminCap, UnbackedPool, BackedPool, Clock, Mint SUI, HeaderChain
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    initialise_and_pegin_with_chunks(genesis, pegout, &mut scenario);

    // PegOut
    scenario.next_tx(DUMMY_ADDRESS);
    {
        let (clock, admin_cap, unbacked_pool, mut backed_pool) = retrive_objects(&scenario);
        let header_chain = test_scenario::take_shared<HeaderChain>(&scenario);

        // Create burning_tx chunks
        let burning_tx_bytes = decode(TX_SERIALISATION);
        // burning_tx_bytes.len() = 498
        // create 3 chunks of 166 bytes, each split in two parts of 83 bytes each
        // the last chunk is a dummy
        let mut burning_tx_chunks: vector<vector<vector<u8>>> = vector::empty();
        range_do!(0, 3, |i| {
            let mut chunks_to_add: vector<vector<u8>> = vector::empty();
            range_do!(0, 2, |j| {
                let mut new_chunk: vector<u8> = vector::empty();
                range_do!(0, 83, |k| new_chunk.push_back(burning_tx_bytes[166 * i + 83 * j + k]));
                chunks_to_add.push_back(new_chunk);
            });
            burning_tx_chunks.push_back(chunks_to_add);
        });
        burning_tx_chunks.push_back(vector::empty<vector<u8>>());

        // Update chunks
        update_chunks(
            &mut backed_pool,
            genesis,
            burning_tx_chunks[0],
            0,
        );

        // Update chunks
        update_chunks(
            &mut backed_pool,
            genesis,
            burning_tx_chunks[1],
            1,
        );

        // Update chunks
        update_chunks(
            &mut backed_pool,
            genesis,
            burning_tx_chunks[2],
            2,
        );

        // Update chunks
        update_chunks(
            &mut backed_pool,
            genesis,
            burning_tx_chunks[3],
            3,
        );

        // Pegout
        let positions = vector[true];
        let hashes = vector[
            decode(b"f77209250e07087f098d3397772a8fa1b63ac475d1c32e7196653c5e42cc80e2"),
        ];
        let balance = pegout_with_chunks_for_test(
            &mut backed_pool,
            genesis,
            &header_chain,
            new_merkle_proof(positions, hashes),
            0,
            0,
            scenario.ctx(),
        );
        assert_eq!(balance.value(), 10);

        // Check backed pool
        assert_eq!(is_valid_genesis_with_chunks(&backed_pool, genesis), false);
        assert_eq!(is_valid_couple_with_chunks(&backed_pool, genesis, pegout), false);

        // Return objects
        return_to_inventory(clock, admin_cap, unbacked_pool, backed_pool);
        test_scenario::return_shared<HeaderChain>(header_chain);
        transfer::public_transfer(from_balance(balance, scenario.ctx()), DUMMY_ADDRESS)
    };

    scenario.end();
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidMerkleProof)]
fun test_failed_pegout_spv() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let burning_tx = new_tx(decode(TX_SERIALISATION));
    let positions = vector[false]; // This should be true
    let hashes = vector[
        decode(b"f77209250e07087f098d3397772a8fa1b63ac475d1c32e7196653c5e42cc80e2"),
    ];
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        0,
        DUMMY_ADDRESS,
    );
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidPegoutTime)]
fun test_failed_pegout_min_delay() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let burning_tx = new_tx(decode(TX_SERIALISATION));
    let positions = vector[true];
    let hashes = vector[
        decode(b"f77209250e07087f098d3397772a8fa1b63ac475d1c32e7196653c5e42cc80e2"),
    ];
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        1,
        DUMMY_ADDRESS,
    );
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidGenesis)]
fun test_failed_pegout_wrong_genesis() {
    let genesis = new_outpoint(new_txid(DUMMY_PEGOUT), 0);
    let burning_tx = new_tx(decode(TX_SERIALISATION));
    let positions = vector[true];
    let hashes = vector[
        decode(b"f77209250e07087f098d3397772a8fa1b63ac475d1c32e7196653c5e42cc80e2"),
    ];
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        0,
        DUMMY_ADDRESS,
    );
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidPegoutInput)]
fun test_failed_pegout_wrong_pegout_input() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    // Coinbase Tx
    let burning_tx = new_tx(
        decode(
            b"02000000010000000000000000000000000000000000000000000000000000000000000000ffffffff0502b6000101ffffffff0111f902950000000023210333ef519090e353c5718218e56014066d116f6d1b89c9f529e17cf8de64ef473cac00000000",
        ),
    );
    let positions = vector[false];
    let hashes = vector[
        decode(b"0fed0f340647d10b7c4033ebb5a4d4223f1be64d03fb416bd9f3b7432c78bece"),
    ];
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        0,
        DUMMY_ADDRESS,
    );
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidTxSender)]
fun test_failed_pegout_wrong_sender() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let burning_tx = new_tx(decode(TX_SERIALISATION));
    let positions = vector[true];
    let hashes = vector[
        decode(b"f77209250e07087f098d3397772a8fa1b63ac475d1c32e7196653c5e42cc80e2"),
    ];
    let wrong_address: address = @0xEFAC;
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        0,
        wrong_address,
    );
}
