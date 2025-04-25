use std::path::Path;

use clap::Parser;
use cli::{BlockHeaderSerialisation, Pegin, Pegout};
use sui_sdk::SuiClientBuilder;

pub mod bridge_cli;
pub mod cli;
pub mod configs;
pub mod oracle_cli;
pub mod utils;

const CONFIG_PATH_UPDATE_CHAIN: &str = "config_files/config_update_chain.toml";
const CONFIG_PATH_ADD_BRIDGE_ENTRY: &str = "config_files/config_add_bridge_entry.toml";
const CONFIG_PATH_CHECK_BRIDGE_ENTRY: &str = "config_files/config_check_bridge_entry.toml";
const CONFIG_PATH_DROP_ELAPSED: &str = "config_files/config_drop_elapsed.toml";
const CONFIG_PATH_PEGIN: &str = "config_files/config_pegin.toml";
const CONFIG_PATH_PEGOUT: &str = "config_files/config_pegout.toml";

fn get_config_files_path() -> String {
    let relative_path = file!();
    let absolute_path = std::env::current_dir()
        .unwrap()
        .join(Path::new(relative_path));
    absolute_path
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_str()
        .unwrap()
        .to_owned()
}

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let cli = cli::Cli::parse();
    
    let localnet_client = SuiClientBuilder::default().build_localnet().await?;
    //let devnet_client = SuiClientBuilder::default().build_devnet().await?;
    //let testnet_client = SuiClientBuilder::default().build_testnet().await?;
    //let mainnet_client = SuiClientBuilder::default().build_mainnet().await?;

    let client = localnet_client;

    let config_file_path_as_str = get_config_files_path();

    match cli.command {
        cli::Commands::UpdateChain => {
            let block_header_serialisation =
                toml::from_str::<BlockHeaderSerialisation>(&std::fs::read_to_string(format!(
                    "{config_file_path_as_str}/{CONFIG_PATH_UPDATE_CHAIN}"
                ))?)?;
            oracle_cli::update_chain(
                client,
                hex::decode(block_header_serialisation.ser)?,
            )
            .await?;
        }
        cli::Commands::AddBridgeEntry => {
            println!(
                "{}",
                format!("{config_file_path_as_str}/{CONFIG_PATH_UPDATE_CHAIN}")
            );
            let bridge_entry = toml::from_str::<cli::BridgeEntry>(&std::fs::read_to_string(
                format!("{config_file_path_as_str}/{CONFIG_PATH_ADD_BRIDGE_ENTRY}"),
            )?)?;
            bridge_cli::add(client, bridge_entry).await?;
        }
        cli::Commands::IsValidForPegin => {
            let bridge_entry = toml::from_str::<cli::BridgeEntry>(&std::fs::read_to_string(
                format!("{config_file_path_as_str}/{CONFIG_PATH_CHECK_BRIDGE_ENTRY}"),
            )?)?;
            let is_valid = bridge_cli::is_valid_for_pegin(client, bridge_entry).await?;
            if is_valid {
                println!("Couple is valid");
            } else {
                println!("Couple is not valid");
            }
        }
        cli::Commands::IsValidForPegout => {
            let bridge_entry = toml::from_str::<cli::BridgeEntry>(&std::fs::read_to_string(
                format!("{config_file_path_as_str}/{CONFIG_PATH_CHECK_BRIDGE_ENTRY}"),
            )?)?;
            let is_valid = bridge_cli::is_valid_for_pegout(client, bridge_entry).await?;
            if is_valid {
                println!("Couple is valid");
            } else {
                println!("Couple is not valid");
            }
        }
        cli::Commands::DropElapsed => {
            let elapsed_bridge_entry =
                toml::from_str::<cli::ElapsedBridgeEntry>(&std::fs::read_to_string(format!(
                    "{config_file_path_as_str}/{CONFIG_PATH_DROP_ELAPSED}"
                ))?)?;
            bridge_cli::drop_elapsed(client, elapsed_bridge_entry).await?;
        }
        cli::Commands::Pegin => {
            let pegin = toml::from_str::<Pegin>(&std::fs::read_to_string(format!(
                "{config_file_path_as_str}/{CONFIG_PATH_PEGIN}"
            ))?)?;
            bridge_cli::pegin(client, pegin).await?;
        }
        cli::Commands::Pegout => {
            let pegout = toml::from_str::<Pegout>(&std::fs::read_to_string(format!(
                "{config_file_path_as_str}/{CONFIG_PATH_PEGOUT}"
            ))?)?;
            bridge_cli::pegout(client, pegout).await?;
        }
        cli::Commands::PeginWithChunks => {
            let pegin = toml::from_str::<Pegin>(&std::fs::read_to_string(format!(
                "{config_file_path_as_str}/{CONFIG_PATH_PEGIN}"
            ))?)?;
            bridge_cli::pegin_with_chunks(client, pegin).await?;
        }
        cli::Commands::PegoutWithChunks => {
            let pegout = toml::from_str::<Pegout>(&std::fs::read_to_string(format!(
                "{config_file_path_as_str}/{CONFIG_PATH_PEGOUT}"
            ))?)?;
            bridge_cli::pegout_with_chunks(client, pegout).await?;
        }
    }

    Ok(())
}
