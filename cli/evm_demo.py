import time
import subprocess
import toml
import json
from typing import MutableMapping, Any
from tx_engine import Wallet
from tx_engine import interface_factory
from bsv.wallet import WalletManager
from tx_engine.interface.interface_factory import WoCInterface, RPCInterface
import argparse
from bsv.block_header import MerkleProof


def load_config(filename="bsv.toml") -> MutableMapping[str, Any]:
    """Load config from provided toml file"""
    try:
        with open(filename, "r") as f:
            config = toml.load(f)
        return config
    except FileNotFoundError as e:
        print(e)
        return {}


def generate_wallets(users, network):
    wallets = {user: {} for user in users}
    with open("../evm/addresses.txt", "r") as f:
        # Read all non-empty, stripped lines
        eth_addresses = [line.strip() for line in f if line.strip()]
    # print(f"{eth_addresses}")
    for i, user in enumerate(users):
        user_key = Wallet.generate_keypair("BSV_Testnet")
        user_address = user_key.get_address()
        network.import_address(user_address)
        network.send_to_address(user_address, 1)
        wallets[user]["key"] = user_key.to_hex()
        funding_utxo = network.get_utxo(user_address)
        tx_hash = funding_utxo[0]["tx_hash"]
        tx_pos_hex = funding_utxo[0]["tx_pos"].to_bytes(4, byteorder="little").hex()
        wallets[user]["utxo"] = f"{tx_hash}:{tx_pos_hex}"
        wallets[user]["eth_address"] = f"{eth_addresses[i]}".removeprefix("0x")
    return wallets


def populate_wallet_json(input_json, wallets, output_json):
    print("\nAdding addresses to eth_bsv_wallet.json...")
    with open(input_json, "r") as f:
        data = json.load(f)

    # Populate both "bsv_wallet" and "funding_utxos" fields
    for user in data:
        if user in wallets:
            data[user]["bsv_wallet"] = wallets[user]["key"]
            data[user]["funding_utxos"] = [wallets[user]["utxo"]]
            data[user]["source_address"] = wallets[user]["eth_address"]

    # Save the updated JSON
    with open(output_json, "w") as f:
        json.dump(data, f, indent=2)

    return


def setup_wallets(network):
    users = ["alice", "bob", "charlie", "issuer"]

    # create the file addresses.txt to be used by generate_wallets.
    subprocess.run(
        [
            "npx",
            "hardhat",
            "run",
            "./scripts/getAddresses.js",
            "--network",
            "localhost",
        ],
        cwd="../evm",
    )
    wallets = generate_wallets(users, network)

    print(f"\nSetting up wallets for {users}...")

    populate_wallet_json("./empty_wallet.json", wallets, "./eth_bsv_wallet.json")
    network.generate_blocks(1)
    wallet_manager = WalletManager.load_wallet("./eth_bsv_wallet.json", network)
    for i, name in enumerate(wallet_manager.names):
        if name != "issuer":
            wallet_manager.setup(i)
    wallet_manager.save_wallet("./eth_bsv_wallet.json")

    return


def publish_oracle(blockheader, richBlockHeader):
    # generate oracle contract from template
    with open("../evm/contracts/oracle/BitcoinHeader.sol.template", "r") as f_oracle:
        oracle_template = f_oracle.read()
        formatted_oracle_template = oracle_template.format(
            blockheader_serialisation=f"{blockheader}",
            genesis_chain_work=f"0x{richBlockHeader.get('chainwork').lstrip('0')}",
        )
    with open("../evm/contracts/oracle/BitcoinHeader.sol", "w") as f_oracle:
        f_oracle.write(formatted_oracle_template)

    oracle_result = subprocess.run(
        [
            "npx",
            "hardhat",
            "run",
            "./scripts/deployOracle.js",
            "--network",
            "localhost",
        ],
        capture_output=True,
        text=True,
        cwd="../evm",
    )
    if oracle_result.returncode != 0:
        print(f"Error occurred: {oracle_result.stderr}")
    else:
        print(oracle_result.stdout)

    for line in oracle_result.stdout.splitlines():
        if "deployed to:" in line:
            oracle_address = line.split("deployed to:")[1].strip()
            break

    return oracle_address


def publish_bridge(oracle_address):
    with open("../evm/contracts/bridge/BitcoinBridge.sol.template", "r") as f_bridge:
        bridge_template = f_bridge.read()
        formatted_bridge_template = bridge_template.format(
            oracle_contract_address=f"{oracle_address}"
        )
    with open("../evm/contracts/bridge/BitcoinBridge.sol", "w") as f_bridge:
        f_bridge.write(formatted_bridge_template)

    bridge_result = subprocess.run(
        [
            "npx",
            "hardhat",
            "run",
            "./scripts/deployBridge.js",
            "--network",
            "localhost",
        ],
        capture_output=True,
        text=True,
        cwd="../evm",
    )
    if bridge_result.returncode != 0:
        print(f"Error occurred: {bridge_result.stderr}")
    else:
        print(bridge_result.stdout)

    for line in bridge_result.stdout.splitlines():
        if "deployed to:" in line:
            bridge_address = line.split("deployed to:")[1].strip()
            break

    return bridge_address


def setup_demo(network):
    setup_wallets(network)

    blockhash = network.get_best_block_hash()
    blockheader = network.rpc_connection.getblockheader(blockhash, False)
    richBlockHeader = network.get_block_header(blockhash)
    genesis_height = richBlockHeader.get("height")

    print(f"\nPublishing Oracle contract with genesis height {genesis_height}...")
    oracle_address = publish_oracle(blockheader, richBlockHeader)

    print("\nPublishing Bridge contract...")
    bridge_address = publish_bridge(oracle_address)

    data = {
        "oracle_address": oracle_address,
        "genesis_height": genesis_height,
        "bridge_address": bridge_address,
    }
    with open("../evm/contract_addresses.json", "w") as file:
        json.dump(data, file, indent=2)

    return


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


def pegin_prep(wallet_manager: WalletManager, user_name: str, pegin_amount: int):
    user = map_user_to_index(user_name, wallet_manager)
    issuer_index = map_user_to_index("issuer", wallet_manager)
    # Generate genesis
    print("\nGenerating genesis transaction...")
    start = time.perf_counter()
    wallet_manager.generate_genesis_for_pegin(user)
    end = time.perf_counter()
    wallet_manager.save_wallet("./eth_bsv_wallet.json")
    print(
        f"\nGenesis transaction generated at: \n{wallet_manager.genesis_utxos[user][-1]}".replace(
            "prev_", ""
        )
    )
    print(f"\nElapsed time: {end - start} seconds")

    conditional_generate_block(wallet_manager.network)

    # Generate pegout
    print("\nGenerating pegout UTXO...")

    wallet_manager.generate_pegout(user, issuer_index, -1)
    wallet_manager.save_wallet("./eth_bsv_wallet.json")

    print(
        f"\nPegout UTXO generated at: \n{wallet_manager.pegout_utxos[user][-1]}".replace(
            "prev_", ""
        )
    )

    conditional_generate_block(wallet_manager.network)

    # Save data to file
    data = {
        "genesis_txid": f"0x{wallet_manager.genesis_utxos[user][-1].prev_tx}",
        "genesis_index": wallet_manager.genesis_utxos[user][-1].prev_index,
        "pegout_txid": f"0x{wallet_manager.pegout_utxos[user][-1].prev_tx}",
        "pegout_index": wallet_manager.pegout_utxos[user][-1].prev_index,
        "pegin_amount": pegin_amount,
    }
    with open("../evm/pegin_info.json", "w") as file:
        json.dump(data, file, indent=2)

    return


def pegin(wallet_manager: WalletManager, user_name: str, pegin_amount: int):
    pegin_prep(wallet_manager, user_name, pegin_amount)

    print("\nAdding entry to the bridge...\n")
    subprocess.run(
        ["npx", "hardhat", "run", "./scripts/pegin.js", "--network", "localhost"],
        cwd="../evm",
    )
    print(f"\nSuccessfully pegged in {pegin_amount} ETH")

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
    start = time.perf_counter()
    wallet_manager.transfer_token(sender, receiver, token_index)
    end = time.perf_counter()
    wallet_manager.save_wallet("./eth_bsv_wallet.json")
    print(
        f"Successfully transferred token in {wallet_manager.token_utxos[receiver][-1].prev_tx}"
    )
    print(f"\nElapsed time: {end - start} seconds")

    return


def update_headers(start_height, end_height, network):
    blockheaders = []
    for i in range(start_height + 1, end_height + 1):
        blockhash = network.get_block_hash(i)
        blockheader = network.rpc_connection.getblockheader(blockhash, False)
        blockheaders.append(blockheader)

    with open("../evm/blockheaders.json", "w") as file:
        json.dump(blockheaders, file, indent=2)

    subprocess.run(
        [
            "npx",
            "hardhat",
            "run",
            "./scripts/updateHeader.js",
            "--network",
            "localhost",
        ],
        cwd="../evm",
    )

    return


def burn(wallet_manager: WalletManager, user_name: str, token_index: int):
    user = map_user_to_index(user_name, wallet_manager)

    txid_genesis = wallet_manager.genesis_utxos[user][token_index].prev_tx

    print(f"\nBurning token generated at {txid_genesis}")
    start = time.perf_counter()
    wallet_manager.burn_token(user, token_index)
    end = time.perf_counter()
    wallet_manager.save_wallet("./eth_bsv_wallet.json")

    conditional_generate_block(wallet_manager.network)

    txid_burn = wallet_manager.burnt_tokens[user][-1].burning_txid
    best_blockhash = wallet_manager.network.get_best_block_hash()
    best_blockheader = wallet_manager.network.get_block_header(best_blockhash)
    best_blockheight = best_blockheader.get("height")

    print(
        f"\nToken successfully burned at transaction {txid_burn} \nblock height {best_blockheight} \nblock hash {best_blockhash}"
    )
    print(f"\nElapsed time: {end - start} seconds")

    ethAddress = wallet_manager.source_addresses[user].hex()

    pegout_prep(
        wallet_manager.network, txid_burn, txid_genesis, best_blockhash, ethAddress
    )

    return


def pegout_prep(network, txid_burn, txid_genesis, best_blockhash, ethAddress):
    merkle_proof = MerkleProof.get_merkle_proof(best_blockhash, txid_burn, network)

    rawtx_burn = network.get_raw_transaction(txid_burn)

    pegout_data = {
        "serializedBitcoinTx": rawtx_burn,
        "merkleProof": [node.hex() for node in merkle_proof.nodes],
        "bitcoinBlockHash": best_blockhash,
        "positions": merkle_proof.positions(),
        "mintTxId": txid_genesis,
        "ethAddress": ethAddress,
    }

    with open("../evm/pegout_data.json", "w") as file:
        json.dump(pegout_data, file, indent=2)

    print(f"\n{merkle_proof}")
    print("\nPegout data saved to pegout_date.json\n")

    return


def pegout(network):
    with open("../evm/contract_addresses.json", "r") as file:
        data = json.load(file)
        genesis_height = data["genesis_height"]

    best_blockheight = network.rpc_connection.getblockcount()
    print("updating Oracle contract...")

    update_headers(genesis_height, best_blockheight, network)

    subprocess.run(
        ["npx", "hardhat", "run", "./scripts/pegout.js", "--network", "localhost"],
        cwd="../evm",
    )

    return


def main():
    parser = argparse.ArgumentParser(description="CLI for tcpBridge")
    subparsers = parser.add_subparsers(
        dest="command", required=True, help="Available commands"
    )

    # Setup command
    subparsers.add_parser("setup", help="Execute the setup command")

    # Pegin command
    pegin_parser = subparsers.add_parser("pegin", help="Execute the pegin command")
    pegin_parser.add_argument("--user", type=str, required=True, help="The user name")
    pegin_parser.add_argument(
        "--pegin-amount", type=int, required=True, help="The pegin amount"
    )
    pegin_parser.add_argument("--network", type=str, required=True, help="The network")

    # Pegout command
    subparsers.add_parser("pegout", help="Execute the pegout command")

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

    # Parse arguments
    args = parser.parse_args()

    # Load wallet
    config = load_config("bsv_config.toml")
    bsv_client = interface_factory.set_config(config["bsv_client"])

    # Dispatch commands
    if args.command == "setup":
        setup_demo(bsv_client)
    else:
        wallet_manager = WalletManager.load_wallet("./eth_bsv_wallet.json", bsv_client)
        if args.command == "pegin":
            pegin(wallet_manager, args.user, args.pegin_amount)
        elif args.command == "transfer":
            transfer(wallet_manager, args.sender, args.receiver, args.token_index)
        elif args.command == "burn":
            burn(wallet_manager, args.user, args.token_index)
        elif args.command == "pegout":
            pegout(bsv_client)


if __name__ == "__main__":
    main()
