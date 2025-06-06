import argparse
from pathlib import Path
import requests
import subprocess
import toml
import sys

sys.path.append(str(Path(__file__).parent.parent / "zkscript_package"))
                
from bsv.wallet import WalletManager
from bsv.block_header import BlockHeader, MerkleProof
from bsv.utils import tx_from_id, setup_network_connection
from tx_engine.interface.interface_factory import WoCInterface, RPCInterface

# TCP
INPUT_INDEX = 1
OUTPUT_INDEX = 0


# Commands
ADD_BRIDGE_ENTRY_COMMAND = "cargo run -- add-bridge-entry"
PEGIN_COMMAND = "cargo run -- pegin-with-chunks"
PEGOUT_COMMAND = "cargo run -- pegout-with-chunks"

def get_bulk_tx_data(txid: str, network: WoCInterface | RPCInterface):
    if isinstance(network, WoCInterface):
        network_str = "test" if network.is_testnet() else "main"
    else:
        network_str = "test"
    api_request = f"https://api.whatsonchain.com/v1/bsv/{network_str}/txs/hex"
    payload = { "txids": [txid] }
    return requests.post(url = api_request, json = payload)

def map_user_to_index(user_name: str, wallet_manager: WalletManager) -> int:
    return wallet_manager.names.index(user_name)
        
def conditional_generate_block(network: WoCInterface | RPCInterface):
    if isinstance(network, RPCInterface):
        for i in range(5):
            try:
                network.generate_blocks(1)
                break
            except:
                pass
    return

def setup(wallet_manager: WalletManager):
    if isinstance(wallet_manager.network, RPCInterface):
        # Get funding
        for i in range(len(wallet_manager.names)):
            wallet_manager.get_funding(i)
    
    conditional_generate_block(wallet_manager.network)

    # Setup for everyone except issuer
    for i, name in enumerate(wallet_manager.names):
        if name != "issuer":
            wallet_manager.setup(i)

    conditional_generate_block(wallet_manager.network)

    print(f"Wallet succesfully set up.")

    return
    
def pegin(wallet_manager: WalletManager, user_name: str, pegin_amount: int):
    user = map_user_to_index(user_name, wallet_manager)
    issuer_index = map_user_to_index("issuer", wallet_manager)

    # Generate genesis
    print(f"\nGenerating genesis transaction...")

    wallet_manager.generate_genesis_for_pegin(user)
    wallet_manager.save_wallet("./wallet.json")

    print(f"\nGenesis transaction generated at: {wallet_manager.genesis_utxos[user][-1]}")

    conditional_generate_block(wallet_manager.network)

    # Generate pegout
    print(f"\nGenerating pegout UTXO...")

    wallet_manager.generate_pegout(user, issuer_index, -1)
    wallet_manager.save_wallet("./wallet.json")
    
    print(f"\nPegout UTXO generated at: {wallet_manager.pegout_utxos[user][-1]}")

    conditional_generate_block(wallet_manager.network)

    # Save data to file
    print(f"\nAdd bridge entry...")

    data = {
        "genesis_txid" : wallet_manager.genesis_utxos[user][-1].prev_tx,
        "genesis_index" : wallet_manager.genesis_utxos[user][-1].prev_index,
        "pegout_txid" : wallet_manager.pegout_utxos[user][-1].prev_tx,
        "pegout_index" : wallet_manager.pegout_utxos[user][-1].prev_index
    }
    with open(str(Path(__file__).parent / "sui/config_files/config_add_bridge_entry.toml"), "w") as file:
        toml.dump(data, file)
    
    # Add bridge entry
    subprocess.run(
            f"cd {Path(__file__).parent / "sui"} && {ADD_BRIDGE_ENTRY_COMMAND}",
            shell=True,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
    print(f"Added bridge entry: \n\tgenesis: {wallet_manager.genesis_utxos[user][-1]}\n\tpegout: {wallet_manager.pegout_utxos[user][-1]}")


    # Save data to file
    print(f"Pegin...")

    data = {
        "genesis_txid" : wallet_manager.genesis_utxos[user][-1].prev_tx,
        "genesis_index" : wallet_manager.genesis_utxos[user][-1].prev_index,
        "pegin_amount" : pegin_amount,
    }
    with open(str(Path(__file__).parent / "sui/config_files/config_pegin.toml"), "w") as file:
        toml.dump(data, file)

    # Pegin
    subprocess.run(
            f"cd {Path(__file__).parent / "sui"} && {PEGIN_COMMAND}",
            shell=True,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
    print(f"\nSuccessfully pegged in for \n\tgenesis: {wallet_manager.genesis_utxos[user][-1]}")

    return

def pegout_for_regtest(wallet_manager: WalletManager, user_name: str, token_index: int, blockhash: str, block_height: int):
    user = map_user_to_index(user_name, wallet_manager)
    burnt_token = wallet_manager.burnt_tokens[user][token_index]
    burning_tx = tx_from_id(burnt_token.burning_txid, wallet_manager.network)
    merkle_proof = MerkleProof.get_merkle_proof(blockhash, burnt_token.burning_txid, wallet_manager.network)

    # Pegout
    print(f"\nPegout...")

    data = {
        "genesis_txid" : burnt_token.genesis_txid,
        "genesis_index" : OUTPUT_INDEX,
        "burning_tx" : burning_tx.serialize().hex(),
        "block_height" : block_height,
        "merkle_proof" : {
            "positions" : merkle_proof.positions(),
            "hashes" : [node.hex() for node in merkle_proof.nodes],
        }
    }
    with open(str(Path(__file__).parent / "sui/config_files/config_pegout.toml"), "w") as file:
        toml.dump(data, file)

    subprocess.run(
            f"cd {Path(__file__).parent / "sui"} && {PEGOUT_COMMAND}",
            shell=True,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
    print(f"\nSuccessfully pegged out for \n\tgenesis: {burnt_token.genesis_txid}")

    return

def pegout(wallet_manager: WalletManager, user_name: str, token_index: int):  
    user = map_user_to_index(user_name, wallet_manager)
    burnt_token = wallet_manager.burnt_tokens[user][token_index]
    burning_tx = tx_from_id(burnt_token.burning_txid, wallet_manager.network)
    bulk_tx_data = get_bulk_tx_data(burnt_token.burning_txid, wallet_manager.network).json()
    block_height = bulk_tx_data[0]["blockheight"]
    merkle_proof = MerkleProof.get_merkle_proof(bulk_tx_data[0]["blockhash"], burnt_token.burning_txid, wallet_manager.network)

    # Pegout
    print(f"\nPegout...")

    data = {
        "genesis_txid" : burnt_token.genesis_txid,
        "genesis_index" : OUTPUT_INDEX,
        "burning_tx" : burning_tx.serialize().hex(),
        "block_height" : block_height,
        "merkle_proof" : {
            "positions" : merkle_proof.positions(),
            "hashes" : [node.hex() for node in merkle_proof.nodes],
        }
    }
    with open(str(Path(__file__).parent / "sui/config_files/config_pegout.toml"), "w") as file:
        toml.dump(data, file)

    subprocess.run(
            f"cd {Path(__file__).parent / "sui"} && {PEGOUT_COMMAND}",
            shell=True,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
    print(f"\nSuccessfully pegged out for \n\tgenesis: {burnt_token.genesis_txid}")

    return
    
def transfer(wallet_manager: WalletManager, sender_name: str, receiver_name: str, token_index: int):
    sender = map_user_to_index(sender_name, wallet_manager)
    receiver = map_user_to_index(receiver_name, wallet_manager)

    print(f"Transferring from {sender_name} to {receiver_name}")
    wallet_manager.transfer_token(sender, receiver, token_index)
    wallet_manager.save_wallet("./wallet.json")
    print(f"Successfully transferred token in {wallet_manager.token_utxos[receiver][-1].prev_tx}")

    return

def burn(wallet_manager: WalletManager, user_name: str, token_index: int):
    user = map_user_to_index(user_name, wallet_manager)

    print(f"\nBurning token generated at {wallet_manager.genesis_utxos[user][token_index].prev_tx}")
    wallet_manager.burn_token(user, token_index)
    wallet_manager.save_wallet("./wallet.json")
    print(f"\nToken successfully burn at {wallet_manager.burnt_tokens[user][-1].burning_txid}")

    conditional_generate_block(wallet_manager.network)

    return

def main():
    parser = argparse.ArgumentParser(description="CLI for tcpBridge")
    subparsers = parser.add_subparsers(dest="command", required=True, help="Available commands")

    # Setup command
    setup_parser = subparsers.add_parser("setup", help="Execute the setup command")
    setup_parser.add_argument("--network", type=str, required=True, help="The network")

    # Pegin command
    pegin_parser = subparsers.add_parser("pegin", help="Execute the pegin command")
    pegin_parser.add_argument("--user", type=str, required=True, help="The user name")
    pegin_parser.add_argument("--pegin-amount", type=int, required=True, help="The pegin amount")
    pegin_parser.add_argument("--network", type=str, required=True, help="The network")

    # Pegout command
    pegout_parser = subparsers.add_parser("pegout", help="Execute the pegout command")
    pegout_parser.add_argument("--user", type=str, required=True, help="The user name")
    pegout_parser.add_argument("--token-index", type=int, required=True, help="The token index")
    pegout_parser.add_argument("--network", type=str, required=True, help="The network")
    pegout_parser.add_argument("--blockhash", type=str, required=False, help="The blockhash")
    pegout_parser.add_argument("--block_height", type=int, required=False, help="The blockheight")

    # Transfer command
    transfer_parser = subparsers.add_parser("transfer", help="Execute the transfer command")
    transfer_parser.add_argument("--sender", type=str, required=True, help="The sender name")
    transfer_parser.add_argument("--receiver", type=str, required=True, help="The receiver name")
    transfer_parser.add_argument("--token-index", type=int, required=True, help="The token index")
    transfer_parser.add_argument("--network", type=str, required=True, help="The network")

    # Burn command
    burn_parser = subparsers.add_parser("burn", help="Execute the burn command")
    burn_parser.add_argument("--user", type=str, required=True, help="The user name")
    burn_parser.add_argument("--token-index", type=int, required=True, help="The token index")
    burn_parser.add_argument("--network", type=str, required=True, help="The network")

    # Parse arguments
    args = parser.parse_args()

    # Load wallet
    network = setup_network_connection(args.network)
    wallet_manager = WalletManager.load_wallet("./wallet.json", network)

    # Dispatch commands
    if args.command == "setup":
        if not isinstance(wallet_manager.network, RPCInterface):
            print("WARNING: Setup outside regtest requires getting funding from a faucet.")
        setup(wallet_manager)
    elif args.command == "pegin":
        pegin(wallet_manager, args.user, args.pegin_amount)
    elif args.command == "pegout":
        if args.network == "regtest":
            assert args.blockhash is not None, "Pegout for regtest requires blockhash"
            assert args.block_height is not None, "Pegout for regtest requires block height"
            pegout_for_regtest(wallet_manager, args.user, args.token_index, args.blockhash, args.block_height)
        else:
            pegout(wallet_manager, args.user, args.token_index)
    elif args.command == "transfer":
        transfer(wallet_manager, args.sender, args.receiver, args.token_index)
    elif args.command == "burn":
        burn(wallet_manager, args.user, args.token_index)

    wallet_manager.save_wallet("./wallet.json")

if __name__ == "__main__":
    main()