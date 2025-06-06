import sys
import os
import subprocess
import toml
import json
from typing import MutableMapping, Any
sys.path.append("..") 
from tx_engine import Wallet
from tx_engine import interface_factory
from bsv.wallet import WalletManager
from bsv.utils import tx_from_id, setup_network_connection
from tx_engine.interface.interface_factory import WoCInterface, RPCInterface
from bsv.block_header import BlockHeader

def load_config(filename="bsv.toml") -> MutableMapping[str, Any]:
    """ Load config from provided toml file
    """
    try:
        with open(filename, "r") as f:
            config = toml.load(f)
        return config
    except FileNotFoundError as e:
        print(e)
        return {}

def run_sui_command(command_args, working_dir=None):
    try:
        # Run the command and capture output
        result = subprocess.run(
            ["sui"] + command_args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,    
            text=True,
            check=True,
            cwd=working_dir
        )
        # Print and return outputs
        #print("\nCommand Output:\n" + result.stdout)
        #if result.stderr:
        #    print("Errors:\n" + result.stderr)   
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Command failed with error {e.returncode}:")
        print(e.stderr)
        return None

def generate_oracle_contract_from_template(
    template_file: str,    
    genesis_block: str,
    genesis_hash: str,
    genesis_height: str,
    geesis_chain_work: str,
    output_file: str,
):
    with open(template_file, 'r') as f:
        template = f.read()
    
    formatted_template = template.format(
        genesis_block=genesis_block,
        genesis_hash=genesis_hash,
        genesis_height=genesis_height,
        geesis_chain_work=geesis_chain_work
    )   
    with open(output_file, 'w') as f:
        f.write(formatted_template)

def generate_bridge_contract_from_template(
    template_file: str,
    header_chain_objectId: str,
    output_file: str
):
    with open(template_file, 'r') as f:
        template = f.read()
    
    formatted_template = template.format(
        header_chain_objectId=header_chain_objectId
    )
    with open(output_file, 'w') as f:
        f.write(formatted_template)

def generate_bridgeClientConfig_from_template(
    template_file: str,
    bridge_admin_id: str,
    bridge_id: str,
    bridge_ver: str,
    bridge_package_id: str,
    header_chain_id: str,
    header_chain_ver: str,
    oracle_package_id: str,
    sui_config_path: str,
    output_file: str
):
    with open(template_file, 'r') as f:
        template = f.read()
    formatted_template = template.format(
        bridge_admin_id=bridge_admin_id,
        bridge_id = bridge_id,
        bridge_ver = bridge_ver,
        bridge_package_id = bridge_package_id,
        header_chain_id = header_chain_id,
        header_chain_ver = header_chain_ver,
        oracle_package_id = oracle_package_id,
        sui_config_path = sui_config_path
    )
    with open(output_file, 'w') as f:
        f.write(formatted_template)

def extract_bridge_objects(data):
    results = {
        'bridge_admin_id': None,
        'bridge_id': None,
        'bridge_ver': None,
        'package_id': None
    }
    for obj in data.get("objectChanges", []):
        # Extract BridgeAdmin object ID
        if "BridgeAdmin" in obj.get("objectType", ""):
            results['bridge_admin_id'] = obj.get("objectId")
            
        # Extract TCPBridge object ID and version
        if "tcpbridge::Bridge" in obj.get("objectType", ""):
            results['bridge_id'] = obj.get("objectId")

        if "tcpbridge::Bridge" in obj.get("objectType", ""):
            results['bridge_ver'] = obj.get("version")
            
        # Extract package ID
        if obj.get("type") == "published":
            results['package_id'] = obj.get("packageId")
    return results

def run_cargo_build(project_dir="."):
    process = subprocess.Popen(
        ["cargo", "build"],
        cwd=project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1  # Line buffered
    )
    # Print each line as it is produced
    for line in process.stdout:
        print(line, end="")  # 'end=""' avoids double newlines
    process.wait()
    if process.returncode == 0:
        print("Build succeeded!")
    else:
        print("Build failed!")

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
        tx_pos = funding_utxo[0]["tx_pos"]
        tx_pos_bytes = tx_pos.to_bytes(4, byteorder='little')
        tx_pos_hex = tx_pos_bytes.hex()
        wallets[user]["utxo"] = f"{tx_hash}:{tx_pos_hex}"
        sui_address_result = run_sui_command(["client", "new-address", "ed25519", "--json"])
        sui_address_output = json.loads(sui_address_result)
        wallets[user]["sui_address"] = f"{sui_address_output["address"]}".removeprefix("0x")
    return wallets 

def populate_wallet_json(input_json, wallets, output_json):
    with open(input_json, 'r') as f:
        data = json.load(f)
    
    # Populate both "bsv_wallet" and "funding_utxos" fields
    for user in data:
        if user in wallets:
            data[user]['bsv_wallet'] = wallets[user]["key"]
            data[user]['funding_utxos'] = [wallets[user]["utxo"]]
            data[user]['sui_address'] = wallets[user]["sui_address"]

    # Save the updated JSON
    with open(output_json, 'w') as f:
        json.dump(data, f, indent=2)

def setup_wallets(wallet_manager, json_file):
    for i, name in enumerate(wallet_manager.names):
        if name != "issuer":
            wallet_manager.setup(i)
    wallet_manager.save_wallet(json_file)



def main ():

    config = load_config("bsv_config.toml")
    bsv_client = interface_factory.set_config(config["bsv_client"])

    users = ["alice", "bob", "charlie", "issuer"]

    print("Setting up wallets...")
    wallets = generate_wallets(users, bsv_client)
    
    populate_wallet_json("./empty_wallet.json", wallets, "./wallet.json")

    bsv_client.generate_blocks(1)

    wallet_manager = WalletManager.load_wallet("./wallet.json", bsv_client)

    setup_wallets(wallet_manager, "./wallet.json")

    blockhash = bsv_client.get_best_block_hash()
    blockheader = BlockHeader.get(blockhash, bsv_client)
    richBlockHeader = bsv_client.get_block_header(blockhash)

    print("\nPublishing Oracle contract...")

    generate_oracle_contract_from_template(
        template_file = "blockchain_oracle_temp.move",
        genesis_block = f"{list(blockheader.serialise())}",
        genesis_hash = f"{list(blockheader.hash())}",
        genesis_height = f"{richBlockHeader.get("height")}",
        geesis_chain_work = f"0x{richBlockHeader.get("chainwork").lstrip("0")}",
        output_file = "../move/oracle/sources/blockchain_oracle.move"
    )

    oracle_result = run_sui_command(["client", "publish", "--json"], "../move/oracle")
    oracle_output = json.loads(oracle_result)
    # Extract package ID
    oraclePackageId = next(
        (item["packageId"] for item in oracle_output["objectChanges"] if item.get("type") == "published"),
            None
    )   
    # Get HeaderChain Object ID and Version
    headerChainId = next(
        (item["objectId"] for item in oracle_output["objectChanges"] if "::HeaderChain" in item.get("objectType", "")),
        None
    )
    headerChainVer = next(
        (item["version"] for item in oracle_output["objectChanges"] if "::HeaderChain" in item.get("objectType", "")),
        None
    )

    print(f"Oracle Package ID: {oraclePackageId}")
    print(f"HeaderChain Object ID: {headerChainId}")    
    print(f"HeaderChain Object version: {headerChainVer}")    

    print("\nPublishing Bridge contract...")

    generate_bridge_contract_from_template(
        template_file="tcpbridge_temp.move",
        header_chain_objectId=headerChainId,
        output_file = "../move/bridge/sources/tcpbridge.move"
    )

    bridge_result = run_sui_command(["client", "publish", "--json"], "../move/bridge")
    bridge_output = json.loads(bridge_result)
    bridge_info = extract_bridge_objects(bridge_output)
    print(f"BridgeAdmin ID: {bridge_info['bridge_admin_id']}")
    print(f"TCPBridge ID: {bridge_info['bridge_id']}")
    print(f"TCPBridge Version: {bridge_info['bridge_ver']}")
    print(f"Package ID: {bridge_info['package_id']}")

    print("\nBuilding client to interact with contracts...")

    generate_bridgeClientConfig_from_template(
        template_file = "configs_temp.rs",
        bridge_admin_id = bridge_info["bridge_admin_id"].removeprefix("0x"),
        bridge_id = bridge_info["bridge_id"].removeprefix("0x"), 
        bridge_ver = bridge_info["bridge_ver"],
        bridge_package_id = bridge_info["package_id"].removeprefix("0x"),
        header_chain_id = headerChainId.removeprefix("0x"),
        header_chain_ver = headerChainVer,
        oracle_package_id = oraclePackageId.removeprefix("0x"),
        sui_config_path = f"{os.path.expanduser("~/.sui/sui_config/client.yaml")}",
        output_file = "sui/src/configs.rs"
    )

    run_cargo_build("sui")

if __name__ == '__main__':
    main()



    

 