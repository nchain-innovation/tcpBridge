use std::{path::Path, str::FromStr};
use sui_sdk::{
    SuiClient,
    rpc_types::SuiObjectDataOptions,
    types::{
        base_types::{ObjectID, ObjectRef, SequenceNumber},
        transaction::ObjectArg,
    },
};

const BRIDGE_ADMIN_ID: &str = "d58e056abdf5adb09bf36c74d8a8e3526019bd66bfc4089c79fc72726e2fd3e5";

const BRIDGE_ID: &str = "c74e333d6c208ffa18f94a14951d485b23a6bb99bcbff7a1063f8e35c57f0c59";
const BRIDGE_SHARED_VERSION: u64 = 4;

const BRIDGE_PACKAGE_ID: &str = "75dcf92661af82906662ff018affa057146ba80194e474d03f28feba42422ce7";

const HEADER_CHAIN_ID: &str = "ca071c9725f9332c85bba033b30663050bd25bd68d97605bafcb33f88d62164e";
const HEADER_CHAIN_SHARED_VERSION: u64 = 3;

const BLOCKCHAIN_ORACLE_ID: &str =
    "6b685d7912b6aee51e2bedbc70e39459fd68beab9e8062dbbfcc9962d4c3aa0e";

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
