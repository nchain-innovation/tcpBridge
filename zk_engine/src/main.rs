use clap::{Parser, Subcommand};

pub mod pob_engine;
pub mod tcp_engine;
pub mod utils;

use pob_engine::pob::{prove, setup, verify};
use tcp_engine::{
    data_structures::{
        proving_data::ProvingData as ProvingDataTCP, setup_data::SetupData as SetupDataTCP,
        verifying_data::VerifyingData as VerifyingDataTCP,
    },
    tcp_system::{TCPSystem, groth16_tcp::UniversalTCPSnark},
};

#[derive(Parser)]
#[command(name = "zk_engine")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Setup both TCP and PoB
    Setup,
    /// TCP commands
    TcpEngine {
        #[command(subcommand)]
        subcommand: TcpEngineCommands,
    },
    /// PoB Commands
    PobEngine {
        #[command(subcommand)]
        subcommand: PobEngineCommands,
    },
}

#[derive(Subcommand)]
enum TcpEngineCommands {
    /// Setup the TCP engine
    Setup,
    /// Prove using the TCP engine
    Prove,
    /// Verify using the TCP engine
    Verify,
}

#[derive(Subcommand)]
enum PobEngineCommands {
    /// Setup the POB engine
    Setup,
    /// Prove using the POB engine
    Prove,
    /// Verify using the POB engine
    Verify,
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Setup => {
            println!("Setting up the TCP system...");
            let setup_data =
                SetupDataTCP::load("data/tcp_engine/configs/setup.toml".to_string()).unwrap();
            <UniversalTCPSnark as TCPSystem>::setup(setup_data).unwrap();

            println!("Setting up the PoB system...");
            setup();

            println!("Setup complete.")
        }
        Commands::TcpEngine { subcommand } => match subcommand {
            TcpEngineCommands::Setup => {
                println!("Setting up the TCP engine...");
                let setup_data =
                    SetupDataTCP::load("data/tcp_engine/configs/setup.toml".to_string()).unwrap();
                <UniversalTCPSnark as TCPSystem>::setup(setup_data).unwrap();

                println!("WARNING: After this setup, PoB will not work anymore.");

                println!("Setup complete.")
            }
            TcpEngineCommands::Prove => {
                println!("Proving using the TCP engine...");

                let proving_data =
                    ProvingDataTCP::load("data/tcp_engine/configs/prove.toml".to_string()).unwrap();
                <UniversalTCPSnark as TCPSystem>::prove(proving_data).unwrap();
            }
            TcpEngineCommands::Verify => {
                println!("Verifying using the TCP engine...");

                let verifying_data =
                    VerifyingDataTCP::load("data/tcp_engine/configs/verify.toml".to_string()).unwrap();
                assert!(
                    <UniversalTCPSnark as TCPSystem>::verify(verifying_data).unwrap(),
                    "\nProof not valid.\n"
                );
                println!("\nValid proof.\n")
            }
        },
        Commands::PobEngine { subcommand } => match subcommand {
            PobEngineCommands::Setup => {
                println!("Setting up the POB engine...");
                setup();

                println!("Setup complete.")
            }
            PobEngineCommands::Prove => {
                println!("Proving using the POB engine...");
                prove();
            }
            PobEngineCommands::Verify => {
                println!("Verifying using the POB engine...");
                assert!(verify(), "\nProof not valid.\n");
                println!("\nValid proof.\n")
            }
        },
    }
}
