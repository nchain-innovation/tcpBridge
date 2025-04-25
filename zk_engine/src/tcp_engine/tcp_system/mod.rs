use anyhow::Result;
use ark_serialize::{CanonicalDeserialize, CanonicalSerialize};

use crate::tcp_engine::data_structures::proving_data::ProvingData;
use crate::tcp_engine::data_structures::setup_data::SetupData;
use crate::tcp_engine::data_structures::verifying_data::VerifyingData;

pub mod groth16_tcp;

/// Interface
pub trait TCPSystem {
    type ProvingKeyMainCircuit: Clone + CanonicalSerialize + CanonicalDeserialize;
    type ProvingKeyHelpCircuit: Clone + CanonicalSerialize + CanonicalDeserialize;
    type ProvingKey: Clone;
    type VerifyingKeyMainCircuit: Clone + CanonicalSerialize + CanonicalDeserialize;
    type VerifyingKeyHelpCircuit: Clone + CanonicalSerialize + CanonicalDeserialize;
    type VerifyingKey;
    type Proof: Clone + CanonicalSerialize + CanonicalDeserialize;
    const KEYS_PATH: &str;
    const PROOFS_PATH: &str;

    // Perform the setup of the TCP system
    fn setup(setup_data: SetupData) -> Result<()>;

    // Prove that an input is in a transaction chain
    fn prove(proving_data: ProvingData) -> Result<()>;

    // Verify that an input is in a transaction chain
    fn verify(verifying_data: VerifyingData) -> Result<bool>;

    // Load the proving key of the TCP system
    fn load_pk() -> Result<Self::ProvingKey>;

    // Load the verifying key of the TCP system
    fn load_vk() -> Result<Self::VerifyingKey>;
}
