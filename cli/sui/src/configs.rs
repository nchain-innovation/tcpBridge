use std::{path::Path, str::FromStr};
use sui_sdk::{
    SuiClient,
    rpc_types::SuiObjectDataOptions,
    types::{
        base_types::{ObjectID, ObjectRef, SequenceNumber},
        transaction::ObjectArg,
    },
};

const BRIDGE_ADMIN_ID: &str = "cc84d6f6c0d77fc2696f043e41d81b2a3ad8acbb7c5041b63954abc1050b678c";

const BRIDGE_ID: &str = "4fe45088bf79dcda6acdc0be6b076ef16ab4b59bf7d1f5322d275a62b90780fd";
const BRIDGE_SHARED_VERSION: u64 = 7678;

const BRIDGE_PACKAGE_ID: &str = "c846dde5b0405eb2b6b165dd3b6b494a56b756ae9dab916e6d8621c956e8f0e3";

const HEADER_CHAIN_ID: &str = "2665df4be2279a6e3244a22449a7107ee21e7558206c052cf88be65b94851d97";
const HEADER_CHAIN_SHARED_VERSION: u64 = 2;

const BLOCKCHAIN_ORACLE_ID: &str =
    "6d1950a17368b44ff5a76317ce33c97335560fac2956d6a1c422d2e3c2b0c0ef";

pub fn oracle_config(mutable_header_chain: bool) -> (ObjectArg, ObjectID) {
    (
        ObjectArg::SharedObject {
            id: ObjectID::from_str(HEADER_CHAIN_ID).unwrap(), // Header chain
            initial_shared_version: SequenceNumber::from_u64(HEADER_CHAIN_SHARED_VERSION),
            mutable: mutable_header_chain,
        },
        ObjectID::from_str(BLOCKCHAIN_ORACLE_ID).unwrap(), // Blockchain oracle
    )
}

pub fn wallet_config() -> &'static Path {
    Path::new("/Users/federicobarbacovi/.sui/sui_config/client.yaml")
}

pub async fn bridge_config(
    client: &SuiClient,
    mutable_bridge: bool,
) -> (ObjectRef, ObjectArg, ObjectID) {
    let bridge_admin_obj_data = client
        .read_api()
        .get_object_with_options(
            ObjectID::from_str(BRIDGE_ADMIN_ID).unwrap(), // Bridge Admin
            SuiObjectDataOptions {
                show_owner: false,
                show_previous_transaction: false,
                show_display: false,
                show_bcs: false,
                show_type: false,
                show_content: true,
                show_storage_rebate: false,
            },
        )
        .await
        .unwrap()
        .data
        .unwrap();

    (
        (
            ObjectID::from_str(BRIDGE_ADMIN_ID).unwrap(), // Bridge Admin
            bridge_admin_obj_data.clone().version,
            bridge_admin_obj_data.digest,
        ),
        ObjectArg::SharedObject {
            id: ObjectID::from_str(BRIDGE_ID).unwrap(), // Bridge ID
            initial_shared_version: SequenceNumber::from_u64(BRIDGE_SHARED_VERSION),
            mutable: mutable_bridge,
        },
        ObjectID::from_str(BRIDGE_PACKAGE_ID).unwrap(), // Bridge package ID
    )
}
