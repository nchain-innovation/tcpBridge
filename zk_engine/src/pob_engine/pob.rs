use ark_groth16::{Groth16, constraints::Groth16VerifierGadget};
use ark_mnt4_753::{Fr as ScalarFieldMNT4, MNT4_753, constraints::PairingVar as MNT4PairingVar};
use ark_mnt6_753::{
    Fr as ScalarFieldMNT6, MNT6_753, constraints::PairingVar as MNT6PairingVar,
    g1::Parameters as ShortWeierstrassParameters,
};
use ark_pcd::{
    ec_cycle_pcd::ECCyclePCDConfig,
    variable_length_crh::injective_map::{
        VariableLengthPedersenCRHCompressor, constraints::VariableLengthPedersenCRHCompressorGadget,
    },
};
use bitcoin_r1cs::{
    bitcoin_predicates::proof_of_burn::ProofOfBurn, constraints::tx::TxVarConfig,
    transaction_integrity_gadget::TransactionIntegrityConfig,
};
use chain_gang::transaction::sighash::{SIGHASH_ALL, SIGHASH_FORKID};
use rand_chacha::ChaChaRng;

use std::io::Cursor;

use anyhow::anyhow;
use ark_crypto_primitives::SNARK;
use ark_ff::PrimeField;
use ark_groth16::{Proof, ProvingKey, VerifyingKey};
use ark_pcd::variable_length_crh::pedersen::VariableLengthPedersenParameters;
use ark_serialize::CanonicalDeserialize;
use bitcoin_r1cs::bitcoin_predicates::data_structures::proof::BitcoinProof;
use bitcoin_r1cs::bitcoin_predicates::data_structures::unit::BitcoinUnit;
use bitcoin_r1cs::reftx::RefTxCircuit;
use bitcoin_r1cs::{
    bitcoin_predicates::data_structures::field_array::FieldArray,
    transaction_integrity_gadget::TransactionIntegrityScheme,
};
use chain_gang::script::Script;
use chain_gang::script::op_codes::OP_CHECKSIG;
use chain_gang::transaction::sighash::SigHashCache;
use chain_gang::{
    messages::Tx,
    util::{Hash256, Serializable},
};
use rand_chacha::rand_core::SeedableRng;

use crate::utils::{data_to_serialisation, read_from_file, save_to_file};

use crate::pob_engine::proving_data::ProvingData;

pub struct PCDGroth16;
impl ECCyclePCDConfig<ScalarFieldMNT4, ScalarFieldMNT6> for PCDGroth16 {
    type CRH = VariableLengthPedersenCRHCompressor<ChaChaRng, ShortWeierstrassParameters>;
    type CRHGadget =
        VariableLengthPedersenCRHCompressorGadget<ChaChaRng, ShortWeierstrassParameters>;
    type MainSNARK = Groth16<MNT4_753>;
    type HelpSNARK = Groth16<MNT6_753>;
    type MainSNARKGadget = Groth16VerifierGadget<MNT4_753, MNT4PairingVar>;
    type HelpSNARKGadget = Groth16VerifierGadget<MNT6_753, MNT6PairingVar>;
}

#[derive(Clone)]
pub struct Config;

impl TxVarConfig for Config {
    const N_INPUTS: usize = 3; // RefTx input, Token to be burnt, funds
    const N_OUTPUTS: usize = 1; // Burnt token
    const LEN_UNLOCK_SCRIPTS: &[usize] = &[0, 0, 0];
    const LEN_LOCK_SCRIPTS: &[usize] = &[0x23]; // OP_0 OP_RETURN 0x23 <Sui Address>
}

impl TransactionIntegrityConfig for Config {
    const LEN_PREV_LOCK_SCRIPT: usize = 1; // OP_CHECKSIG
    const N_INPUT: usize = 0; // Reftx input is the first one
    const SIGHASH_FLAG: u8 = SIGHASH_ALL | SIGHASH_FORKID;
}

pub type PoB = ProofOfBurn<ScalarFieldMNT4, ScalarFieldMNT6, PCDGroth16, Config>;

const TCP_SYSTEM_KEYS: &str = "data/tcp_engine/keys/";
const TCP_SYSTEM_PROOFS: &str = "data/tcp_engine/proofs/";
const POB_SYSTEM_KEYS: &str = "data/pob_engine/keys/";
const POB_SYSTEM_PROOFS: &str = "data/pob_engine/proofs/";
const POB_INDEX: usize = 1; // Index of the burnt output
const POB_DATA: &str = "data/pob_engine/";

fn generate_pob_predicate() -> PoB {
    // Load the key of the TCP System
    let crh_pp_seed_bytes = read_from_file(&(TCP_SYSTEM_KEYS.to_owned() + "crh_pp_seed.bin"))
        .map_err(|e| anyhow!("Failed to read crh_pp. Error: {}", e))
        .unwrap();
    let help_vk_bytes = read_from_file(&(TCP_SYSTEM_KEYS.to_owned() + "help_vk.bin"))
        .map_err(|e: std::io::Error| anyhow!("Failed to read help_vk. Error: {}", e))
        .unwrap();

    let crh_pp = VariableLengthPedersenParameters {
        seed: crh_pp_seed_bytes,
    };
    let help_vk = VerifyingKey::<MNT6_753>::deserialize_unchecked(help_vk_bytes.as_slice())
        .map_err(|e| anyhow!("Failed to deserialize help_vk. Error: {}", e))
        .unwrap();

    // PoB
    PoB::new(&crh_pp, &help_vk, POB_INDEX)
}

pub fn setup() {
    // PoB
    let pob = generate_pob_predicate();

    // Dummy RefTx
    let dummy_reftx = RefTxCircuit::<PoB, ScalarFieldMNT4, Config> {
        locking_data: FieldArray::<1, ScalarFieldMNT4, Config>::default(),
        integrity_tag: None,
        unlocking_data: BitcoinUnit::default(),
        witness: BitcoinProof::new(&Proof::<MNT6_753>::default()),
        spending_data: None,
        prev_lock_script: None,
        prev_amount: None,
        sighash_cache: None,
        predicate: pob,
    };

    // Setup
    let mut rng = ChaChaRng::from_entropy();
    let (pk, vk) = Groth16::<MNT4_753>::circuit_specific_setup(dummy_reftx, &mut rng).unwrap();

    // Save keys
    save_to_file(
        &data_to_serialisation(&pk),
        &(POB_SYSTEM_KEYS.to_owned() + "pk.bin"),
    )
    .unwrap();
    save_to_file(
        &data_to_serialisation(&vk),
        &(POB_SYSTEM_KEYS.to_owned() + "vk.bin"),
    )
    .unwrap();
}

pub fn prove() {
    let proving_data = ProvingData::load(&(POB_DATA.to_owned() + "proving_data.toml")).unwrap();
    let genesis_txid =
        FieldArray::<1, ScalarFieldMNT4, Config>::new([ScalarFieldMNT4::from_le_bytes_mod_order(
            &Hash256::decode(&proving_data.genesis_txid).unwrap().0,
        )]);
    let spending_tx = Tx::read(&mut Cursor::new(
        hex::decode(proving_data.spending_tx)
            .map_err(|e| anyhow!("Failed to hex decode witness tx. Error: {}", e))
            .unwrap(),
    ))
    .map_err(|e| anyhow!("Failed to read witness tx. Error: {}", e))
    .unwrap();
    let tcp_proof = Proof::<MNT6_753>::deserialize_unchecked(Cursor::new(
        read_from_file(
            &(TCP_SYSTEM_PROOFS.to_owned() + &format!("{}.bin", proving_data.tcp_proof_name)),
        )
        .map_err(|e| anyhow!("Failed to read prior proof. Error: {}", e))
        .unwrap(),
    ))
    .unwrap();

    // PoB
    let pob = generate_pob_predicate();

    // Tag
    let tag = TransactionIntegrityScheme::<Config>::commit(
        &spending_tx,
        &Script(vec![OP_CHECKSIG]),
        proving_data.prev_amount,
        &mut SigHashCache::new(),
    );

    // RefTx
    let reftx = RefTxCircuit::<PoB, ScalarFieldMNT4, Config> {
        locking_data: genesis_txid,
        integrity_tag: Some(tag),
        unlocking_data: BitcoinUnit::default(),
        witness: BitcoinProof::new(&tcp_proof),
        spending_data: Some(spending_tx),
        prev_lock_script: Some(Script(vec![OP_CHECKSIG])),
        prev_amount: Some(proving_data.prev_amount),
        sighash_cache: None,
        predicate: pob,
    };

    // Load key of RefTx
    let pk_serialised = read_from_file(&(POB_SYSTEM_KEYS.to_owned() + "pk.bin"))
        .map_err(|e: std::io::Error| anyhow!("Failed to read pk. Error: {}", e))
        .unwrap();
    let pk = ProvingKey::<MNT4_753>::deserialize_unchecked(pk_serialised.as_slice())
        .map_err(|e| anyhow!("Failed to deserialize pk. Error: {}", e))
        .unwrap();

    // Save the public input
    save_to_file(
        data_to_serialisation(&reftx.public_input()).as_slice(),
        &(POB_SYSTEM_PROOFS.to_owned() + "input_proof_of_burn.bin"),
    )
    .unwrap();

    // Proof
    let mut rng = ChaChaRng::from_entropy();
    let proof = Groth16::<MNT4_753>::prove(&pk, reftx, &mut rng).unwrap();

    // Save the proof
    save_to_file(
        &data_to_serialisation(&proof),
        &(POB_SYSTEM_PROOFS.to_owned() + "proof_of_burn.bin"),
    )
    .unwrap();
}

pub fn verify() -> bool {
    // Load vk of RefTx
    let vk_serialised = read_from_file(&(POB_SYSTEM_KEYS.to_owned() + "vk.bin"))
        .map_err(|e: std::io::Error| anyhow!("Failed to read vk. Error: {}", e))
        .unwrap();
    let vk = VerifyingKey::<MNT4_753>::deserialize_unchecked(vk_serialised.as_slice())
        .map_err(|e| anyhow!("Failed to deserialize vk. Error: {}", e))
        .unwrap();

    // Load the public input
    let public_input_serialised =
        read_from_file(&(POB_SYSTEM_PROOFS.to_owned() + "input_proof_of_burn.bin"))
            .map_err(|e: std::io::Error| anyhow!("Failed to read public input. Error: {}", e))
            .unwrap();
    let public_input =
        Vec::<ScalarFieldMNT4>::deserialize_unchecked(public_input_serialised.as_slice())
            .map_err(|e| anyhow!("Failed to deserialize public input. Error: {}", e))
            .unwrap();

    // Load the proof
    let proof_serialised = read_from_file(&(POB_SYSTEM_PROOFS.to_owned() + "proof_of_burn.bin"))
        .map_err(|e: std::io::Error| anyhow!("Failed to read proof. Error: {}", e))
        .unwrap();
    let proof = Proof::<MNT4_753>::deserialize_unchecked(proof_serialised.as_slice())
        .map_err(|e| anyhow!("Failed to deserialize proof. Error: {}", e))
        .unwrap();

    Groth16::<MNT4_753>::verify(&vk, &public_input, &proof).unwrap()
}
