use std::fs;

use anyhow::{Result, anyhow};
use serde::Deserialize;

#[derive(Clone, Deserialize)]
pub struct SetupData {
    pub index: usize, // Index of the input to be burnt
}

impl SetupData {
    pub fn load(file_path: String) -> Result<Self> {
        let file_data = fs::read_to_string(file_path)
            .map_err(|e| anyhow!("Failed to read setup data. Error: {}", e))?;
        toml::from_str::<SetupData>(&file_data)
            .map_err(|e| anyhow!("Failed to parse setup data. Error: {}", e))
    }
}
