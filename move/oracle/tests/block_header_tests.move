#[test_only]
module blockchain_oracle::block_header_tests;

use blockchain_oracle::block_header::{
    BlockHeader,
    new_block_header,
    compute_block_hash,
    bits_to_target,
    get_target,
    serialise_block_header,
    deserialise_block_header
};
use std::unit_test::assert_eq;
use sui::hex::decode;
use sui::test_utils;

const TEST_SERIALISATION: vector<u8> =
    b"00000020148617fec3b8a35ad7ff98f987caedab10778c37f31e04000000000000000000ac30c372441c96ad0ffdc751bbeafe3b9e38503edd808f3236c6ca0f87b5d116ebfa89646d6005174f347164";

#[test]
fun test_serialisation() {
    let test_serialisation = decode(TEST_SERIALISATION);
    let block_header = new_block_header(
        536870912,
        decode(b"148617fec3b8a35ad7ff98f987caedab10778c37f31e04000000000000000000"),
        decode(b"ac30c372441c96ad0ffdc751bbeafe3b9e38503edd808f3236c6ca0f87b5d116"),
        1686764267,
        vector[109, 96, 5, 23],
        1685140559,
    );
    assert_eq!(serialise_block_header(&block_header), test_serialisation);
    test_utils::destroy<BlockHeader>(block_header);
}

#[test]
fun test_deserialisation() {
    let test_serialisation = decode(TEST_SERIALISATION);
    let test_block_header = deserialise_block_header(test_serialisation);
    assert_eq!(
        test_block_header,
        new_block_header(
            536870912,
            decode(b"148617fec3b8a35ad7ff98f987caedab10778c37f31e04000000000000000000"),
            decode(b"ac30c372441c96ad0ffdc751bbeafe3b9e38503edd808f3236c6ca0f87b5d116"),
            1686764267,
            vector[109, 96, 5, 23],
            1685140559,
        ),
    );
    test_utils::destroy<BlockHeader>(test_block_header);
}

#[test]
fun test_block_hash() {
    let test_serialisation = decode(TEST_SERIALISATION);
    let test_block_hash = decode(
        b"7b56dd00f29f30984381efb72cf7979edd47612fcb1603000000000000000000",
    );
    let test_block_header = deserialise_block_header(test_serialisation);
    let test_hash = compute_block_hash(&test_block_header);
    assert_eq!(test_hash, test_block_hash);
    test_utils::destroy<BlockHeader>(test_block_header);
    test_utils::destroy<vector<u8>>(test_hash);
}

#[test]
fun test_bits_to_target() {
    let test_bits = vector[109, 96, 5, 23];
    let test_target: u256 = 0x00000000000000000005606d0000000000000000000000000000000000000000;

    assert_eq!(bits_to_target(test_bits), test_target);
}

#[test]
fun test_get_target() {
    let test_serialisation = decode(TEST_SERIALISATION);
    let test_target: u256 = 0x00000000000000000005606d0000000000000000000000000000000000000000;
    let test_block_header = deserialise_block_header(test_serialisation);
    assert_eq!(get_target(&test_block_header), test_target);
    test_utils::destroy<BlockHeader>(test_block_header);
}
