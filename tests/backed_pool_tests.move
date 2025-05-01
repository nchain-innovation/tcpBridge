#[test_only]
module tcpbridge::backed_pool_tests;

use blockchain_oracle::blockchain_oracle::{new_header_chain, HeaderChain};
use blockchain_oracle::spv::{MerkleProof, new as new_merkle_proof};
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
    is_valid_couple as is_valid_couple_in_backed,
    pegin,
    pegout_for_test,
    get_coin_value
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

/// Constants taken from BSV Mainnet - Block 894437
const HEADER_SERIALISATION: vector<u8> =
    b"0000003621381cd7437a20225dda389eaa0a6b7ffb63d9858b67df0e000000000000000009d24ffd51f6a5a1622631091c10c55cc36c889f9576cf5dee5203ff5aa0183335630f68d75e13184db4ce01";
const HEADER_CHAIN_WORK: u256 = 0x100010001;
const TX_SERIALISATION: vector<u8> =
    b"0100000001371d897aaf7b1e437d85be167fb75928da8a7040fb623765ecf29d825d86b76f010000006a4730440220492d1e724008d8af5d63146035907228fdefc7aa21fb92ffc2029621fbec166e02205ed3b9c87adac5b3970897520c95cde6e8cb334364edd70370536b5730d4df1e412102db13cdc9989f118f6c865126d9b6e62886d214bdd9c190cb6062cb40642bc602ffffffff0200000000000000009b006a0e2054696d654f6654782e636f6d204c88516b6c464d514f717844726464595474575454647632336e4d492f6e58357268762b4c626b5a494f48756a55354c6646436c4e4248584f526474594c394244547351466b6f7844496643307264356464752b76624d667832586f51646e69753451747245496530447958515969533345514d614679476d6e7944416359474f775a4b6a2f7672513dd7090500000000001976a9149df0707f3f8e534441c055aca4bb816fbc1eadf488ac00000000";
const PEGOUT: vector<u8> = b"01371d897aaf7b1e437d85be167fb75928da8a7040fb623765ecf29d825d86b7";
const PEGOUT_INDEX: u32 = 367;

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

/// Failed PegOut
fun failed_pegout(
    genesis: OutPoint,
    burning_tx: Tx,
    merkle_proof: MerkleProof,
    block_height: u64,
    pegout_delay: u64,
) {
    let correct_genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let correct_pegout = new_outpoint(new_txid(decode(PEGOUT)), PEGOUT_INDEX);

    // Create AdminCap, UnbackedPool, BackedPool, Clock, Mint SUI, HeaderChain
    let mut scenario = test_scenario::begin(DUMMY_ADDRESS);
    initialise_and_pegin(correct_genesis, correct_pegout, &mut scenario);

    // PegOut
    scenario.next_tx(DUMMY_ADDRESS);
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
        let positions = vector[true, false, false, false, false, false, false, false, false, false];
        let hashes = vector[
            decode(b"d6ec1deb5dddfb6db243d1c0d00c7a1b4d1f0552da3c2f0e4afe3b952c066145"),
            decode(b"fc148be6812955156f0843687e9ee05911861c42369d8983bcd6f0722c9fbc9f"),
            decode(b"a4821559d834d1335c2d80a89af7961d9304d216fed588edbabbc78126c757ed"),
            decode(b"5ce37e575cb31479aeec906b07eed5ed7cb778ba06b83c6b374f9b4cfa835027"),
            decode(b"0603b2002fabf88886f91029b7a6680898ce0ea30a64ff56413e3629479a394b"),
            decode(b"9f575bc39f27c4201a1b5d7a35233ca71340fa80a8a66426cf538b3e3dedf945"),
            decode(b"42ee2cce00bd4acf655923136ed0a073a6a3e7f8128eba6601c7d4cb6ae6ff92"),
            decode(b"d8d2461bc1f4de9a798267f9602e0f1c596fb35a448d128c3d34d35c37f22ec1"),
            decode(b"0faebc0f55f1d427dadc41c46ad13de75e498158eb4b65be70893d3f7fd72578"),
            decode(b"49ec00f2af38ebb5fdd08d62149d031b6d81a269d5e4adc21d2b54d0929758b1"),
        ];
        let balance = pegout_for_test(
            &mut backed_pool,
            genesis,
            burning_tx,
            &header_chain,
            new_merkle_proof(positions, hashes),
            0,
            0,
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

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidMerkleProof)]
fun test_failed_pegout_spv() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let burning_tx = new_tx(decode(TX_SERIALISATION));
    let positions = vector[true, false, false, false, false, false, false, false, false, false];
    let hashes = vector[
        decode(b"d6ec1deb5dddfb6db243d1c0d00c7a1b4d1f0552da3c2f0e4afe3b952c066145"),
        decode(b"fc148be6812955156f0843687e9ee05911861c42369d8983bcd6f0722c9fbc9f"),
        decode(b"a4821559d834d1335c2d80a89af7961d9304d216fed588edbabbc78126c757ed"),
        decode(b"5ce37e575cb31479aeec906b07eed5ed7cb778ba06b83c6b374f9b4cfa835027"),
        decode(b"0603b2002fabf88886f91029b7a6680898ce0ea30a64ff56413e3629479a394b"),
        decode(b"9f575bc39f27c4201a1b5d7a35233ca71340fa80a8a66426cf538b3e3dedf945"),
        decode(b"42ee2cce00bd4acf655923136ed0a073a6a3e7f8128eba6601c7d4cb6ae6ff92"),
        decode(b"d8d2461bc1f4de9a798267f9602e0f1c596fb35a448d128c3d34d35c37f22ec1"),
        decode(b"49ec00f2af38ebb5fdd08d62149d031b6d81a269d5e4adc21d2b54d0929758b1"), // This one and the one below are swapped
        decode(b"0faebc0f55f1d427dadc41c46ad13de75e498158eb4b65be70893d3f7fd72578"),
    ];
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        0,
    );
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidPegoutTime)]
fun test_failed_pegout_min_delay() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    let burning_tx = new_tx(decode(TX_SERIALISATION));
    let positions = vector[true, false, false, false, false, false, false, false, false, false];
    let hashes = vector[
        decode(b"d6ec1deb5dddfb6db243d1c0d00c7a1b4d1f0552da3c2f0e4afe3b952c066145"),
        decode(b"fc148be6812955156f0843687e9ee05911861c42369d8983bcd6f0722c9fbc9f"),
        decode(b"a4821559d834d1335c2d80a89af7961d9304d216fed588edbabbc78126c757ed"),
        decode(b"5ce37e575cb31479aeec906b07eed5ed7cb778ba06b83c6b374f9b4cfa835027"),
        decode(b"0603b2002fabf88886f91029b7a6680898ce0ea30a64ff56413e3629479a394b"),
        decode(b"9f575bc39f27c4201a1b5d7a35233ca71340fa80a8a66426cf538b3e3dedf945"),
        decode(b"42ee2cce00bd4acf655923136ed0a073a6a3e7f8128eba6601c7d4cb6ae6ff92"),
        decode(b"d8d2461bc1f4de9a798267f9602e0f1c596fb35a448d128c3d34d35c37f22ec1"),
        decode(b"0faebc0f55f1d427dadc41c46ad13de75e498158eb4b65be70893d3f7fd72578"),
        decode(b"49ec00f2af38ebb5fdd08d62149d031b6d81a269d5e4adc21d2b54d0929758b1"),
    ];
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        1,
    );
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidGenesis)]
fun test_failed_pegout_wrong_genesis() {
    let genesis = new_outpoint(new_txid(DUMMY_PEGOUT), 0);
    let burning_tx = new_tx(decode(TX_SERIALISATION));
    let positions = vector[true, false, false, false, false, false, false, false, false, false];
    let hashes = vector[
        decode(b"d6ec1deb5dddfb6db243d1c0d00c7a1b4d1f0552da3c2f0e4afe3b952c066145"),
        decode(b"fc148be6812955156f0843687e9ee05911861c42369d8983bcd6f0722c9fbc9f"),
        decode(b"a4821559d834d1335c2d80a89af7961d9304d216fed588edbabbc78126c757ed"),
        decode(b"5ce37e575cb31479aeec906b07eed5ed7cb778ba06b83c6b374f9b4cfa835027"),
        decode(b"0603b2002fabf88886f91029b7a6680898ce0ea30a64ff56413e3629479a394b"),
        decode(b"9f575bc39f27c4201a1b5d7a35233ca71340fa80a8a66426cf538b3e3dedf945"),
        decode(b"42ee2cce00bd4acf655923136ed0a073a6a3e7f8128eba6601c7d4cb6ae6ff92"),
        decode(b"d8d2461bc1f4de9a798267f9602e0f1c596fb35a448d128c3d34d35c37f22ec1"),
        decode(b"0faebc0f55f1d427dadc41c46ad13de75e498158eb4b65be70893d3f7fd72578"),
        decode(b"49ec00f2af38ebb5fdd08d62149d031b6d81a269d5e4adc21d2b54d0929758b1"),
    ];
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        0,
    );
}

#[test, expected_failure(abort_code = ::tcpbridge::backed_pool::EInvalidPegoutInput)]
fun test_failed_pegout_wrong_pegout_input() {
    let genesis = new_outpoint(new_txid(DUMMY_TXID), 0);
    // Coinbase Tx
    let burning_tx = new_tx(
        decode(
            b"01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff1a03e5a50d2f7461616c2e636f6d2fc64d1336b0bec2aea10a0600ffffffff018729a112000000001976a914522cf9e7626d9bd8729e5a1398ece40dad1b6a2f88ac00000000",
        ),
    );
    let positions = vector[false, false, false, false, false, false, false, false, false, false];
    let hashes = vector[
        decode(b"963369cc95862f5f1552a8c6d51f880f7d2aa13ebc0422a2ef4b9a5cc6980358"),
        decode(b"fc148be6812955156f0843687e9ee05911861c42369d8983bcd6f0722c9fbc9f"),
        decode(b"a4821559d834d1335c2d80a89af7961d9304d216fed588edbabbc78126c757ed"),
        decode(b"5ce37e575cb31479aeec906b07eed5ed7cb778ba06b83c6b374f9b4cfa835027"),
        decode(b"0603b2002fabf88886f91029b7a6680898ce0ea30a64ff56413e3629479a394b"),
        decode(b"9f575bc39f27c4201a1b5d7a35233ca71340fa80a8a66426cf538b3e3dedf945"),
        decode(b"42ee2cce00bd4acf655923136ed0a073a6a3e7f8128eba6601c7d4cb6ae6ff92"),
        decode(b"d8d2461bc1f4de9a798267f9602e0f1c596fb35a448d128c3d34d35c37f22ec1"),
        decode(b"0faebc0f55f1d427dadc41c46ad13de75e498158eb4b65be70893d3f7fd72578"),
        decode(b"49ec00f2af38ebb5fdd08d62149d031b6d81a269d5e4adc21d2b54d0929758b1"),
    ];
    failed_pegout(
        genesis,
        burning_tx,
        new_merkle_proof(positions, hashes),
        0,
        0,
    );
}
