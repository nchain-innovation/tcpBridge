import argparse
from pathlib import Path
import requests
import subprocess
import toml
import sys
import json
import os

sys.path.append(str(Path(__file__).parent.parent / "zkscript_package"))
sys.path.append("..")
from bsv.wallet import WalletManager
from bsv.block_header import BlockHeader, MerkleProof
from bsv.utils import tx_from_id, setup_network_connection
from tx_engine.interface.interface_factory import WoCInterface, RPCInterface
from tx_engine import Wallet

# TCP
INPUT_INDEX = 1
OUTPUT_INDEX = 0


# Commands
# Pegin and pegout can be replaced by pegin_with_chunks and pegout_with_chunks if
# transaction size exceeds 128kB

ADD_BRIDGE_ENTRY_COMMAND = "cargo run -- add-bridge-entry"
PEGIN_COMMAND = "cargo run -- pegin"
PEGOUT_COMMAND = "cargo run -- pegout"

INFO_FILE = "info.json"


def save_info(key, value):
    try:
        with open(INFO_FILE, "r") as f:
            info = json.load(f)
    except FileNotFoundError:
        info = {}
    info[key] = value
    with open(INFO_FILE, "w") as f:
        json.dump(info, f)


def read_info(key):
    with open(INFO_FILE, "r") as f:
        info = json.load(f)
    return info.get(key)


def run_cargo_build(project_dir="."):
    process = subprocess.Popen(
        ["cargo", "build"],
        cwd=project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,  # Line buffered
    )
    # Print each line as it is produced
    for line in process.stdout:
        print(line, end="")  # 'end=""' avoids double newlines
    process.wait()
    if process.returncode == 0:
        print("Build succeeded!")
    else:
        print("Build failed!")


def get_bulk_tx_data(txid: str, network: WoCInterface | RPCInterface):
    if isinstance(network, WoCInterface):
        network_str = "test" if network.is_testnet() else "main"
    else:
        network_str = "test"
    api_request = f"https://api.whatsonchain.com/v1/bsv/{network_str}/txs/hex"
    payload = {"txids": [txid]}
    return requests.post(url=api_request, json=payload)


def map_user_to_index(user_name: str, wallet_manager: WalletManager) -> int:
    return wallet_manager.names.index(user_name)


def conditional_generate_block(network: WoCInterface | RPCInterface):
    if isinstance(network, RPCInterface):
        for i in range(5):
            try:
                network.generate_blocks(1)
                break
            except Exception:
                pass
    return


def run_sui_command(command_args, working_dir=None):
    try:
        # Run the command and capture output
        result = subprocess.run(
            ["sui"] + command_args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
            cwd=working_dir,
        )
        # Print and return outputs
        # print("\nCommand Output:\n" + result.stdout)
        # if result.stderr:
        #    print("Errors:\n" + result.stderr)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Command failed with error {e.returncode}:")
        print(e.stderr)
        return None


def extract_bridge_objects(data):
    results = {
        "bridge_admin_id": None,
        "bridge_id": None,
        "bridge_ver": None,
        "package_id": None,
    }
    for obj in data.get("objectChanges", []):
        # Extract BridgeAdmin object ID
        if "BridgeAdmin" in obj.get("objectType", ""):
            results["bridge_admin_id"] = obj.get("objectId")

        # Extract TCPBridge object ID and version
        if "tcpbridge::Bridge" in obj.get("objectType", ""):
            results["bridge_id"] = obj.get("objectId")
            results["bridge_ver"] = obj.get("version")

        # Extract package ID
        if obj.get("type") == "published":
            results["package_id"] = obj.get("packageId")
    return results


def generate_wallets(users, network):
    wallets = {user: {} for user in users}
    for user in users:
        user_key = Wallet.generate_keypair("BSV_Testnet")
        user_address = user_key.get_address()
        network.import_address(user_address)
        network.send_to_address(user_address, 1)
        wallets[user]["key"] = user_key.to_hex()
        print(f"{user} address = {user_address}")
        funding_utxo = network.get_utxo(user_address)
        tx_hash = funding_utxo[0]["tx_hash"]
        tx_pos_hex = funding_utxo[0]["tx_pos"].to_bytes(4, byteorder="little").hex()
        wallets[user]["utxo"] = f"{tx_hash}:{tx_pos_hex}"
        sui_address_result = run_sui_command(
            ["client", "new-address", "ed25519", "--json"]
        )
        sui_address_output = json.loads(sui_address_result)
        run_sui_command(
            ["client", "switch", "--address", f"{sui_address_output['address']}"]
        )
        run_sui_command(["client", "faucet"])
        wallets[user]["sui_address"] = f"{sui_address_output['address']}".removeprefix(
            "0x"
        )
    return wallets


def populate_wallet_json(input_json, wallets, output_json):
    with open(input_json, "r") as f:
        data = json.load(f)

    # Populate both "bsv_wallet" and "funding_utxos" fields
    for user in data:
        if user in wallets:
            data[user]["bsv_wallet"] = wallets[user]["key"]
            data[user]["funding_utxos"] = [wallets[user]["utxo"]]
            data[user]["source_address"] = wallets[user]["sui_address"]

    # Save the updated JSON
    with open(output_json, "w") as f:
        json.dump(data, f, indent=2)


def setup_wallets(wallet_manager, json_file):
    for i, name in enumerate(wallet_manager.names):
        if name != "issuer":
            wallet_manager.setup(i)
    wallet_manager.save_wallet(json_file)


def setup_for_regtest(network):
    users = ["alice", "bob", "charlie", "issuer"]

    print("Setting up wallets...")
    wallets = generate_wallets(users, network)

    populate_wallet_json("./empty_wallet.json", wallets, "./sui_bsv_wallet.json")

    network.generate_blocks(1)

    wallet_manager = WalletManager.load_wallet("./sui_bsv_wallet.json", network)

    setup_wallets(wallet_manager, "./sui_bsv_wallet.json")

    blockhash = network.get_best_block_hash()
    blockheader = BlockHeader.get(blockhash, network)
    richBlockHeader = network.get_block_header(blockhash)
    genesis_height = richBlockHeader.get("height")

    print(f"\nPublishing Oracle contract with genesis height {genesis_height} ...")

    # generate oracle contract from template
    with open("blockchain_oracle_template.move", "r") as f:
        oracle_template = f.read()
        formatted_oracle_template = oracle_template.format(
            genesis_block=f"{list(blockheader.serialise())}",
            genesis_hash=f"{list(blockheader.hash())}",
            genesis_height=f"{genesis_height}",
            genesis_chain_work=f"0x{richBlockHeader.get('chainwork').lstrip('0')}",
        )
    with open("../move/oracle/sources/blockchain_oracle.move", "w") as f:
        f.write(formatted_oracle_template)

    oracle_result = run_sui_command(["client", "publish", "--json"], "../move/oracle")
    oracle_output = json.loads(oracle_result)
    # Extract package ID
    oraclePackageId = next(
        (
            item["packageId"]
            for item in oracle_output["objectChanges"]
            if item.get("type") == "published"
        ),
        None,
    )
    # Get HeaderChain Object ID and Version
    headerChainId = next(
        (
            item["objectId"]
            for item in oracle_output["objectChanges"]
            if "::HeaderChain" in item.get("objectType", "")
        ),
        None,
    )
    headerChainVer = next(
        (
            item["version"]
            for item in oracle_output["objectChanges"]
            if "::HeaderChain" in item.get("objectType", "")
        ),
        None,
    )

    print(f"Oracle Package ID: {oraclePackageId}")
    print(f"HeaderChain Object ID: {headerChainId}")
    print(f"HeaderChain Object version: {headerChainVer}")
    save_info("genesis_height", genesis_height)

    print("\nPublishing Bridge contract...")

    # generate bridge contract from template
    with open("tcpbridge_template.move", "r") as f:
        bridge_template = f.read()

    formatted_bridge_template = bridge_template.format(
        header_chain_objectId=headerChainId
    )
    with open("../move/bridge/sources/tcpbridge.move", "w") as f:
        f.write(formatted_bridge_template)

    bridge_result = run_sui_command(["client", "publish", "--json"], "../move/bridge")
    bridge_output = json.loads(bridge_result)
    bridge_info = extract_bridge_objects(bridge_output)
    print(f"BridgeAdmin ID: {bridge_info['bridge_admin_id']}")
    print(f"TCPBridge ID: {bridge_info['bridge_id']}")
    print(f"TCPBridge Version: {bridge_info['bridge_ver']}")
    print(f"Package ID: {bridge_info['package_id']}")

    print("\nBuilding client to interact with contracts...")

    # generate configs for building a client to interact with the bridge and the oracle smart contract
    with open("configs_template.rs", "r") as f:
        configs_template = f.read()
        formatted_configs_template = configs_template.format(
            bridge_admin_id=bridge_info["bridge_admin_id"].removeprefix("0x"),
            bridge_id=bridge_info["bridge_id"].removeprefix("0x"),
            bridge_ver=bridge_info["bridge_ver"],
            bridge_package_id=bridge_info["package_id"].removeprefix("0x"),
            header_chain_id=headerChainId.removeprefix("0x"),
            header_chain_ver=headerChainVer,
            oracle_package_id=oraclePackageId.removeprefix("0x"),
            sui_config_path=f"{os.path.expanduser('~/.sui/sui_config/client.yaml')}",
        )
    with open("sui/src/configs.rs", "w") as f:
        f.write(formatted_configs_template)

    run_cargo_build("sui")

    return


def pegin(wallet_manager: WalletManager, user_name: str, pegin_amount: int):
    user = map_user_to_index(user_name, wallet_manager)
    issuer_index = map_user_to_index("issuer", wallet_manager)

    # Generate genesis
    print("\nGenerating genesis transaction...")

    wallet_manager.generate_genesis_for_pegin(user)
    wallet_manager.save_wallet("./sui_bsv_wallet.json")

    print(
        f"\nGenesis transaction generated at: {wallet_manager.genesis_utxos[user][-1]}"
    )

    conditional_generate_block(wallet_manager.network)

    # Generate pegout
    print("\nGenerating pegout UTXO...")

    wallet_manager.generate_pegout(user, issuer_index, -1)
    wallet_manager.save_wallet("./sui_bsv_wallet.json")

    print(f"\nPegout UTXO generated at: {wallet_manager.pegout_utxos[user][-1]}")

    conditional_generate_block(wallet_manager.network)

    # Save data to file
    print("\nAdd bridge entry...")

    data = {
        "genesis_txid": wallet_manager.genesis_utxos[user][-1].prev_tx,
        "genesis_index": wallet_manager.genesis_utxos[user][-1].prev_index,
        "pegout_txid": wallet_manager.pegout_utxos[user][-1].prev_tx,
        "pegout_index": wallet_manager.pegout_utxos[user][-1].prev_index,
    }
    with open(
        str(Path(__file__).parent / "sui/config_files/config_add_bridge_entry.toml"),
        "w",
    ) as file:
        toml.dump(data, file)

    print(f"{run_sui_command(['client', 'active-address'])}")

    # switch to admin to add bridge entry. This address should be the same as the address that is used to publish the bridge contract
    admin_sui_address = get_sui_address(wallet_manager, "issuer")
    run_sui_command(["client", "switch", "--address", f"{admin_sui_address}"])

    print(f"{run_sui_command(['client', 'active-address'])}")

    # Add bridge entry
    subprocess.run(
        f"cd {Path(__file__).parent / 'sui'} && {ADD_BRIDGE_ENTRY_COMMAND}",
        shell=True,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    print(
        f"Added bridge entry: \n\tgenesis: {wallet_manager.genesis_utxos[user][-1]}\n\tpegout: {wallet_manager.pegout_utxos[user][-1]}"
    )

    # Save data to file
    print("Pegin...")

    data = {
        "genesis_txid": wallet_manager.genesis_utxos[user][-1].prev_tx,
        "genesis_index": wallet_manager.genesis_utxos[user][-1].prev_index,
        "pegin_amount": pegin_amount,
    }
    with open(
        str(Path(__file__).parent / "sui/config_files/config_pegin.toml"), "w"
    ) as file:
        toml.dump(data, file)

    user_sui_address = get_sui_address(wallet_manager, user_name)
    run_sui_command(["client", "switch", "--address", f"{user_sui_address}"])

    # Pegin
    subprocess.run(
        f"cd {Path(__file__).parent / 'sui'} && {PEGIN_COMMAND}",
        shell=True,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    print(
        f"\nSuccessfully pegged in for \n\tgenesis: {wallet_manager.genesis_utxos[user][-1]}"
    )

    return


def run_pegout_command(genesis_txid, burning_tx, block_height, merkle_proof):
    # Pegout
    print("\nPegout...")

    data = {
        "genesis_txid": genesis_txid,
        "genesis_index": OUTPUT_INDEX,
        "burning_tx": burning_tx.serialize().hex(),
        "block_height": block_height,
        "merkle_proof": {
            "positions": merkle_proof.positions(),
            "hashes": [node.hex() for node in merkle_proof.nodes],
        },
    }
    with open(
        str(Path(__file__).parent / "sui/config_files/config_pegout.toml"), "w"
    ) as file:
        toml.dump(data, file)

    subprocess.run(
        f"cd {Path(__file__).parent / 'sui'} && {PEGOUT_COMMAND}",
        shell=True,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    print(f"\nSuccessfully pegged out for \n\tgenesis: {genesis_txid}\n")

    return


def pegout_for_regtest(
    wallet_manager: WalletManager,
    user_name: str,
    token_index: int,
    blockhash: str,
    block_height: int,
):
    user = map_user_to_index(user_name, wallet_manager)
    burnt_token = wallet_manager.burnt_tokens[user][token_index]
    burning_tx = tx_from_id(burnt_token.burning_txid, wallet_manager.network)
    merkle_proof = MerkleProof.get_merkle_proof(
        blockhash, burnt_token.burning_txid, wallet_manager.network
    )
    sui_address = get_sui_address(wallet_manager, user_name)
    run_sui_command(["client", "switch", "--address", f"{sui_address}"])
    print(f"\n{user_name} sui address: {sui_address}")
    print(f"{run_sui_command(['client', 'balance'])}")

    run_pegout_command(burnt_token.genesis_txid, burning_tx, block_height, merkle_proof)

    print(f"\n{user_name} sui address: {sui_address}")
    print(f"{run_sui_command(['client', 'balance'])}")

    return


def pegout(wallet_manager: WalletManager, user_name: str, token_index: int):
    user = map_user_to_index(user_name, wallet_manager)
    burnt_token = wallet_manager.burnt_tokens[user][token_index]
    burning_tx = tx_from_id(burnt_token.burning_txid, wallet_manager.network)
    bulk_tx_data = get_bulk_tx_data(
        burnt_token.burning_txid, wallet_manager.network
    ).json()
    block_height = bulk_tx_data[0]["blockheight"]
    merkle_proof = MerkleProof.get_merkle_proof(
        bulk_tx_data[0]["blockhash"], burnt_token.burning_txid, wallet_manager.network
    )

    run_pegout_command(burnt_token.genesis_txid, burning_tx, block_height, merkle_proof)

    return


def transfer(
    wallet_manager: WalletManager,
    sender_name: str,
    receiver_name: str,
    token_index: int,
):
    sender = map_user_to_index(sender_name, wallet_manager)
    receiver = map_user_to_index(receiver_name, wallet_manager)

    print(f"Transferring from {sender_name} to {receiver_name}")
    wallet_manager.transfer_token(sender, receiver, token_index)
    wallet_manager.save_wallet("./sui_bsv_wallet.json")
    print(
        f"Successfully transferred token in {wallet_manager.token_utxos[receiver][-1].prev_tx}"
    )

    return


def burn(wallet_manager: WalletManager, user_name: str, token_index: int):
    user = map_user_to_index(user_name, wallet_manager)

    print(
        f"\nBurning token generated at {wallet_manager.genesis_utxos[user][token_index].prev_tx}"
    )

    wallet_manager.burn_token(user, token_index)
    wallet_manager.save_wallet("./sui_bsv_wallet.json")

    conditional_generate_block(wallet_manager.network)
    blockhash = wallet_manager.network.get_best_block_hash()
    blockheader = wallet_manager.network.get_block_header(blockhash)
    blockheight = blockheader.get("height")

    save_info("burn_blockhash", blockhash)
    save_info("burn_blockheight", blockheight)

    print(
        f"\nToken successfully burned at transaction {wallet_manager.burnt_tokens[user][-1].burning_txid} \nblock height {blockheight} \nblock hash {blockhash}"
    )

    return


def update_oracle(genesis_height: int, network: str):
    subprocess.run(
        [
            "python3",
            "-m",
            "oracle_service",
            "--block_height",
            f"{genesis_height}",
            "--network",
            network,
        ],
        cwd="./bsv",
    )
    return


def get_sui_address(wallet_manager: WalletManager, user_name: str):
    user = map_user_to_index(user_name, wallet_manager)
    sui_address = wallet_manager.source_addresses[user]
    extended_address = bytes.fromhex("00") * (32 - len(sui_address)) + sui_address
    extended_address = "0x" + extended_address.hex()
    return extended_address


def main():
    parser = argparse.ArgumentParser(description="CLI for tcpBridge")
    subparsers = parser.add_subparsers(
        dest="command", required=True, help="Available commands"
    )

    # Setup command
    setup_parser = subparsers.add_parser("setup", help="Execute the setup command")
    setup_parser.add_argument("--network", type=str, required=True, help="The network")

    # Pegin command
    pegin_parser = subparsers.add_parser("pegin", help="Execute the pegin command")
    pegin_parser.add_argument("--user", type=str, required=True, help="The user name")
    pegin_parser.add_argument(
        "--pegin-amount", type=int, required=True, help="The pegin amount"
    )
    pegin_parser.add_argument("--network", type=str, required=True, help="The network")

    # Pegout command
    pegout_parser = subparsers.add_parser("pegout", help="Execute the pegout command")
    pegout_parser.add_argument("--user", type=str, required=True, help="The user name")
    pegout_parser.add_argument(
        "--token-index", type=int, required=True, help="The token index"
    )
    pegout_parser.add_argument("--network", type=str, required=True, help="The network")
    pegout_parser.add_argument(
        "--update", action="store_true", help="update the header oracle before pegout"
    )

    # Transfer command
    transfer_parser = subparsers.add_parser(
        "transfer", help="Execute the transfer command"
    )
    transfer_parser.add_argument(
        "--sender", type=str, required=True, help="The sender name"
    )
    transfer_parser.add_argument(
        "--receiver", type=str, required=True, help="The receiver name"
    )
    transfer_parser.add_argument(
        "--token-index", type=int, required=True, help="The token index"
    )
    transfer_parser.add_argument(
        "--network", type=str, required=True, help="The network"
    )

    # Burn command
    burn_parser = subparsers.add_parser("burn", help="Execute the burn command")
    burn_parser.add_argument("--user", type=str, required=True, help="The user name")
    burn_parser.add_argument(
        "--token-index", type=int, required=True, help="The token index"
    )
    burn_parser.add_argument("--network", type=str, required=True, help="The network")

    # Update command
    update_parser = subparsers.add_parser(
        "update", help="Execute the update oracle command"
    )
    update_parser.add_argument("--network", type=str, required=True, help="The network")

    # Parse arguments
    args = parser.parse_args()

    # Load wallet
    network = setup_network_connection(args.network)

    # Dispatch commands
    if args.command == "setup":
        if args.network == "regtest":
            setup_for_regtest(network)
        else:
            print(
                "WARNING: Setup outside regtest requires getting funding from a faucet."
            )
    else:
        # setup should be skipped if not in regtest, in which case wallet.json must be populated before calling the commands below.
        wallet_manager = WalletManager.load_wallet("./sui_bsv_wallet.json", network)
        if args.command == "pegin":
            pegin(wallet_manager, args.user, args.pegin_amount)
        elif args.command == "pegout":
            if args.update:
                genesis_height = read_info("genesis_height")
                update_oracle(genesis_height, args.network)
            if args.network == "regtest":
                blockhash = read_info("burn_blockhash")
                blockheight = read_info("burn_blockheight")
                pegout_for_regtest(
                    wallet_manager, args.user, args.token_index, blockhash, blockheight
                )
            else:
                pegout(wallet_manager, args.user, args.token_index)
        elif args.command == "transfer":
            transfer(wallet_manager, args.sender, args.receiver, args.token_index)
        elif args.command == "burn":
            burn(wallet_manager, args.user, args.token_index)
        elif args.command == "update":
            genesis_height = read_info("genesis_height")
            update_oracle(genesis_height, args.network)
        wallet_manager.save_wallet("./sui_bsv_wallet.json")


if __name__ == "__main__":
    main()
