#[test_only]
module blockchain_oracle::blockchain_oracle_tests;

use blockchain_oracle::block_header::deserialise_block_header;
use blockchain_oracle::blockchain_oracle::{
    new_header_chain,
    HeaderChain,
    lengths,
    access_headers,
    access_hashes,
    update_chain
};
use std::unit_test::assert_eq;
use sui::hex::decode;
use sui::test_scenario;

const GENESIS_BLOCK: vector<u8> =
    b"0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c";
const GENESIS_HASH: vector<u8> =
    b"6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000";
const GENESIS_HEIGHT: u64 = 0;
const GENESIS_CHAIN_WORK: u256 = 0x100010001;
const SECOND_BLOCK: vector<u8> =
    b"010000006fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000982051fd1e4ba744bbbe680e1fee14677ba1a3c3540bf7b1cdb606e857233e0e61bc6649ffff001d01e36299";
const SECOND_BLOCK_HASH: vector<u8> =
    b"4860eb18bf1b1620e37e9490fc8a427514416fd75159ab86688e9a8300000000";

#[test]
fun test_header_chain_update() {
    let dummy_address: address = @0xCAFE;

    let mut scenario = test_scenario::begin(dummy_address);
    {
        let header_chain = new_header_chain(
            GENESIS_HEIGHT,
            decode(GENESIS_BLOCK),
            GENESIS_CHAIN_WORK,
            scenario.ctx(),
        );
        transfer::public_share_object(header_chain);
    };

    scenario.next_tx(dummy_address);
    {
        let header_chain = test_scenario::take_shared<HeaderChain>(&scenario);
        let (headers_length, hashes_length) = lengths(&header_chain);
        assert_eq!(headers_length, 1);
        assert_eq!(hashes_length, 1);

        let block_header = deserialise_block_header(decode(GENESIS_BLOCK));
        assert_eq!(access_headers(&header_chain, 0), block_header);
        assert_eq!(access_hashes(&header_chain, 0), decode(GENESIS_HASH));

        test_scenario::return_shared(header_chain);
    };

    scenario.next_tx(dummy_address);
    {
        let next_block_serialisation = decode(SECOND_BLOCK);
        let next_block_hash = decode(SECOND_BLOCK_HASH);
        let mut header_chain = test_scenario::take_shared<HeaderChain>(&scenario);
        update_chain(&mut header_chain, next_block_serialisation);
        assert_eq!(
            access_headers(&header_chain, 1),
            deserialise_block_header(next_block_serialisation),
        );
        assert_eq!(access_hashes(&header_chain, 1), next_block_hash);

        test_scenario::return_shared(header_chain);
    };

    scenario.end();
}
