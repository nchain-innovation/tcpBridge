use clap::{Parser, Subcommand};
use serde::Deserialize;

/// Command-line interface for the application
#[derive(Parser)]
#[command(name = "sui_playground")]
#[command(about = "A CLI for managing Sui Playground", long_about = None)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Update the chain configuration
    UpdateChain,
    /// Add a new bridge entry
    AddBridgeEntry,
    /// Check if a couple (genesis, pegout) is valid for pegin
    IsValidForPegin,
    /// Check if a couple (genesis, pegout) is valid for pegout
    IsValidForPegout,
    /// Drop elapsed couples
    DropElapsed,
    /// Pegin
    Pegin,
    /// Pegout
    Pegout,
    /// PeginWithChunks
    PeginWithChunks,
    /// PegoutWithChunks
    PegoutWithChunks,
}

#[derive(Clone, Deserialize)]
pub struct BlockHeaderSerialisation {
    pub ser: String,
}

#[derive(Clone, Deserialize)]
pub struct BridgeEntry {
    pub genesis_txid: String,
    pub genesis_index: u32,
    pub pegout_txid: String,
    pub pegout_index: u32,
}

#[derive(Clone, Deserialize)]
pub struct ElapsedBridgeEntry {
    pub genesis_txid: String,
    pub genesis_index: u32,
}

#[derive(Clone, Deserialize)]
pub struct Pegin {
    pub genesis_txid: String,
    pub genesis_index: u32,
    pub pegin_amount: u64,
}

#[derive(Clone, Deserialize)]
pub struct Pegout {
    pub genesis_txid: String,
    pub genesis_index: u32,
    pub burning_tx: String,
    pub merkle_proof: MerkleProof,
    pub block_height: u64,
}

#[derive(Clone, Deserialize)]
pub struct MerkleProof {
    pub positions: Vec<u32>,
    pub hashes: Vec<String>,
}
