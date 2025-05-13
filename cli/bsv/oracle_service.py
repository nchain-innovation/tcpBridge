import argparse
from block_header import BlockHeader
from pathlib import Path
import subprocess
import time
import toml
from utils import setup_network_connection

BLOCK_HEADER_SERIALISATION = "config_files/config_update_chain.toml"
UPDATE_CHAIN_COMMAND = "cargo run -- update-chain"

def main():
    parser = argparse.ArgumentParser(description='Oracle service updating BSV oracle smart contract.')
    parser.add_argument('block_height', type=int, 
                        help='Specify the block_height to start the service from')
    parser.add_argument('network', choices=['regtest', 'testnet', 'mainnet'], 
                        help='Specify the network to connect to: regtest, testnet, or mainnet.')

    args = parser.parse_args()

    print(f"Connecting to the {args.network}...")
    bsv = setup_network_connection(args.network)

    prev_block_height = args.block_height

    while True:
        # Check every 10 seconds
        time.sleep(10)

        current_block_height = bsv.get_block_count()
        current_block_hash = bsv.get_best_block_hash()
        if prev_block_height != current_block_height:
            block_headers = [BlockHeader.get(current_block_hash, bsv)]
            for _ in range(prev_block_height, current_block_height-1):
                block_hash = block_headers[-1].hash_prev_block[::-1].hex()
                block_headers.append(BlockHeader.get(block_hash, bsv))
            for block_header in block_headers[::-1]:
                with open(Path(__file__).parent.parent / "sui" / BLOCK_HEADER_SERIALISATION, "w") as file:
                    toml.dump({"ser": block_header.serialise().hex()}, file)
                subprocess.run(
                    f"cd {Path(__file__).parent.parent / "sui"} && {UPDATE_CHAIN_COMMAND}",
                    shell=True,
                    check=True,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE)
                print(f"Block {block_header.hash()[::-1].hex()} added to the oracle")
            prev_block_height = current_block_height

if __name__ == '__main__':
    main()