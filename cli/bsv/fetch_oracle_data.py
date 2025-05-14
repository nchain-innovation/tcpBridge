import argparse
from block_header import BlockHeader
from pathlib import Path
import subprocess
import time
import toml
from utils import setup_network_connection

def main():
    parser = argparse.ArgumentParser(description='Fetch block header data for oracle Sui smart contract.')
    parser.add_argument('--blockhash', type=str, 
                        help='Specify the blockhash to fetch the data for.')
    parser.add_argument('--network', choices=['regtest', 'testnet', 'mainnet'], 
                        help='Specify the network to connect to: regtest, testnet, or mainnet.')

    args = parser.parse_args()

    print(f"\nConnecting to the {args.network}...")
    bsv = setup_network_connection(args.network)

    block_header = BlockHeader.get(args.blockhash, bsv)

    print(f"\nBlock header serialisation:\n{list(block_header.serialise())}")
    print(f"\nBlock hash:\n{list(block_header.hash())}")

if __name__ == '__main__':
    main()