use std::{{path::Path, str::FromStr}};
use sui_sdk::{{
    SuiClient,
    rpc_types::SuiObjectDataOptions,
    types::{{
        base_types::{{ObjectID, ObjectRef, SequenceNumber}},
        transaction::ObjectArg,
    }},
}};

const BRIDGE_ADMIN_ID: &str = "{bridge_admin_id}";

const BRIDGE_ID: &str = "{bridge_id}";
const BRIDGE_SHARED_VERSION: u64 = {bridge_ver};

const BRIDGE_PACKAGE_ID: &str = "{bridge_package_id}";

const HEADER_CHAIN_ID: &str = "{header_chain_id}";
const HEADER_CHAIN_SHARED_VERSION: u64 = {header_chain_ver};

const BLOCKCHAIN_ORACLE_ID: &str =
    "{oracle_package_id}";

pub fn oracle_config(mutable_header_chain: bool) -> (ObjectArg, ObjectID) {{
    (
        ObjectArg::SharedObject {{
            id: ObjectID::from_str(HEADER_CHAIN_ID).unwrap(), // Header chain
            initial_shared_version: SequenceNumber::from_u64(HEADER_CHAIN_SHARED_VERSION),
            mutable: mutable_header_chain,
        }},
        ObjectID::from_str(BLOCKCHAIN_ORACLE_ID).unwrap(), // Blockchain oracle
    )
}}

pub fn wallet_config() -> &'static Path {{
    Path::new("{sui_config_path}")
}}

pub async fn bridge_config(
    client: &SuiClient,
    mutable_bridge: bool,
) -> (ObjectRef, ObjectArg, ObjectID) {{
    let bridge_admin_obj_data = client
        .read_api()
        .get_object_with_options(
            ObjectID::from_str(BRIDGE_ADMIN_ID).unwrap(), // Bridge Admin
            SuiObjectDataOptions {{
                show_owner: false,
                show_previous_transaction: false,
                show_display: false,
                show_bcs: false,
                show_type: false,
                show_content: true,
                show_storage_rebate: false,
            }},
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
        ObjectArg::SharedObject {{
            id: ObjectID::from_str(BRIDGE_ID).unwrap(), // Bridge ID
            initial_shared_version: SequenceNumber::from_u64(BRIDGE_SHARED_VERSION),
            mutable: mutable_bridge,
        }},
        ObjectID::from_str(BRIDGE_PACKAGE_ID).unwrap(), // Bridge package ID
    )
}}
