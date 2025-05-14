import argparse
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent / "zkscript_package"))

from bsv.wallet import WalletManager
from bsv.utils import setup_network_connection

def display_wallet_info(wallet_manager: WalletManager):
    print("=" * 50)
    print("Wallet Manager Overview")
    print("=" * 50)

    for index, user_name in enumerate(wallet_manager.names):
        print(f"User: {user_name}")
        print(f"  BSV Address: {wallet_manager.bsv_wallets[index].get_address()}")
        print(f"  SUI Address: {wallet_manager.sui_addresses[index].hex()}")
        print(f"  Genesis UTXOs:")
        for utxo in wallet_manager.genesis_utxos[index]:
            print(f"    - {utxo}")
        print(f"  Token UTXOs:")
        for utxo in wallet_manager.token_utxos[index]:
            print(f"    - {utxo}")
        print(f"  Burnt tokens:")
        for burnt_token in wallet_manager.burnt_tokens[index]:
            print(f"    - {burnt_token}")
        print("-" * 50)

# Example usage
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Text-based UI for WalletManager.')
    parser.add_argument('--network', choices=['regtest', 'testnet', 'mainnet'], 
                        help='Specify the network to connect to: regtest, testnet, or mainnet.')
    
    # Parse args
    args = parser.parse_args()
    network = setup_network_connection(args.network)

    while True:
        print("\nText-Based Wallet Manager UI")
        print("1. Display Wallet Info")
        print("2. Exit")
        choice = input("Enter your choice: ")

        if choice == "1":
            wallet_manager = WalletManager.load_wallet("./wallet.json", network)
            display_wallet_info(wallet_manager)
        elif choice == "2":
            print("Exiting...")
            break
        else:
            print("Invalid choice. Please try again.")
