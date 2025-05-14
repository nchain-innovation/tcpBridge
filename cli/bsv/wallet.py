
import sys
import json
from pathlib import Path
import subprocess
import toml

sys.path.append(str(Path(__file__).parent.parent.parent / "zkscript_package"))

from bsv.utils import bytes_to_script, prepend_signature, tx_to_input, tx_from_id, p2pkh, spend_p2pkh, p2pkh
from bsv.zk_utils import load_and_process_vk, generate_pob_utxo

from elliptic_curves.instantiations.mnt4_753.mnt4_753 import MNT4_753, ProofMnt4753
from src.zkscript.groth16.mnt4_753.mnt4_753 import mnt4_753
from src.zkscript.script_types.unlocking_keys.reftx import RefTxUnlockingKey
from tx_engine import Wallet, Script, Tx, TxOut
from tx_engine.interface.blockchain_interface import BlockchainInterface
from tx_engine.interface.interface_factory import WoCInterface, RPCInterface

ScalarFieldMNT4 = MNT4_753.scalar_field


BURNING_FUNDING_INDEX = -2 # Funding index for burning is second to last
BALLPARK_TRANSACTION_SIZE = 300
BALLPARK_TRANSACTION_FEE = BALLPARK_TRANSACTION_SIZE * 50 // 1000 # 50 satoshis per kB
BALLPARK_BURNING_TX_SIZE = 300000
BALLPARK_BURNING_TX_FEE = BALLPARK_BURNING_TX_SIZE * 50 // 1000 # 50 satoshis per kB
TRANSFER_ZK_PROOF = "cargo run --release -- tcp-engine prove"
BURNING_ZK_PROOF = "cargo run --release -- pob-engine prove"

"""
The structure of the WalletManager assumes that genesis & pegout are added in order. So, if genesis_1 and genesis_2 are created,
then pegout_1 and pegout_2 must be added in this order. If not, the structure will be messed up.
"""

class Outpoint:

    def __init__(self, prev_tx: str, prev_index: int):
        self.prev_tx = prev_tx
        self.prev_index = prev_index

    @staticmethod
    def from_hexstr(outpoint: str):
        prev_tx = outpoint[:64]
        prev_index = int.from_bytes(bytes.fromhex(outpoint[64:]), "little")
        return Outpoint(prev_tx, prev_index)
    
    def to_hexstr(self) -> str:
        return f"{self.prev_tx}" + self.prev_index.to_bytes(4, 'little').hex()
    
    def __repr__(self):
        return f"prev_tx: {self.prev_tx}, prev_index: {self.prev_index}"
    
class BurntToken:

    def __init__(self, genesis_txid: str, burning_txid: str):
        self.genesis_txid = genesis_txid
        self.burning_txid = burning_txid

    def to_hexstr(self) -> str:
        return f"{self.genesis_txid}:{self.burning_txid}"
    
    @staticmethod
    def from_hexstr(burnt_token: str):
        elements = burnt_token.split(":")
        return BurntToken(
            genesis_txid=elements[0],
            burning_txid=elements[1]
        )
    
    def __repr__(self):
        return f"Genesis: {self.genesis_txid}, Burning tx: {self.burning_txid}"

class WalletManager:

    def __init__(
            self,
            names: list[str],
            bsv_wallets: list[Wallet],
            sui_addresses: list[bytes],
            genesis_utxos: list[list[Outpoint]],
            token_utxos: list[list[Outpoint]],
            pegout_utxos: list[list[Outpoint]],
            zk_proof_paths: list[str],
            funding_utxos: list[list[Outpoint]],
            burnt_tokens: list[BurntToken],
            network: BlockchainInterface,
        ):
        self.names = names
        self.bsv_wallets = bsv_wallets
        self.sui_addresses = sui_addresses
        self.genesis_utxos = genesis_utxos
        self.token_utxos = token_utxos
        self.pegout_utxos = pegout_utxos
        self.zk_proof_paths = zk_proof_paths
        self.funding_utxos = funding_utxos
        self.burnt_tokens = burnt_tokens
        self.network = network


    def clear_wallet(self):
        return WalletManager(
            names = self.names,
            bsv_wallets=self.bsv_wallets,
            sui_addresses=self.sui_addresses,
            genesis_utxos=[[]] * len(self.bsv_wallets),
            token_utxos=[[]] * len(self.bsv_wallets),
            pegout_utxos=[[]] * len(self.bsv_wallets),
            zk_proof_paths=[[]] * len(self.bsv_wallets),
            funding_utxos=[[]] * len(self.bsv_wallets),
            burnt_tokens=[[]] * len(self.bsv_wallets),
            network=self.network,
        )

    @staticmethod
    def load_wallet(wallet_path: str, network: WoCInterface | RPCInterface):
        """
        Load a wallet from a JSON file.

        [
            "name" : {
                "bsv_wallet": [],
                "sui_address": [],
                "genesis_utxos": [],
                "token_utxos": [],
                "pegout_utxos": [],
                "zk_proof_paths": [],
                "funding_utxos": [],
                "burnt_tokens": [],
            }
        ]

        Args:
            wallet_path (str): The path to the wallet configuration file.
        """
        if isinstance(network, RPCInterface):
            network_str = "BSV_Testnet"
        else:
            if network.is_testnet():
                network_str = "BSV_Testnet"
            else:
                network_str = "BSV_Mainnet"
        try:
            names = []
            bsv_wallets = []
            sui_addresses = []
            genesis_utxos = []
            token_utxos = []
            pegout_utxos = []
            zk_proof_paths = []
            funding_utxos = []
            burnt_tokens = []
            with open(wallet_path, 'r') as file:
                data = json.load(file)
                for name in data.keys():
                    names.append(name)
                    bsv_wallets.append(Wallet.from_hexstr(network_str, data[name]["bsv_wallet"]))
                    sui_addresses.append(bytes.fromhex(data[name]["sui_address"]))
                    genesis_utxos_to_add = []
                    token_utxos_to_add = []
                    pegout_utxos_to_add = []
                    zk_proof_paths_to_add = []
                    funding_utxos_to_add = []
                    burnt_tokens_to_add = []
                    for outpoint in data[name]["genesis_utxos"]:
                        genesis_utxos_to_add.append(Outpoint.from_hexstr(outpoint))
                    for outpoint in data[name]["token_utxos"]:
                        token_utxos_to_add.append(Outpoint.from_hexstr(outpoint))
                    for outpoint in data[name]["pegout_utxos"]:
                        pegout_utxos_to_add.append(Outpoint.from_hexstr(outpoint))
                    for path in data[name]["zk_proof_paths"]:
                        zk_proof_paths_to_add.append(path)
                    for outpoint in data[name]["funding_utxos"]:
                        funding_utxos_to_add.append(Outpoint.from_hexstr(outpoint))
                    for outpoint in data[name]["burnt_tokens"]:
                        burnt_tokens_to_add.append(BurntToken.from_hexstr(outpoint))
                    genesis_utxos.append(genesis_utxos_to_add)
                    token_utxos.append(token_utxos_to_add)
                    pegout_utxos.append(pegout_utxos_to_add)
                    zk_proof_paths.append(zk_proof_paths_to_add)
                    funding_utxos.append(funding_utxos_to_add)
                    burnt_tokens.append(burnt_tokens_to_add)
            return WalletManager(names, bsv_wallets, sui_addresses, genesis_utxos, token_utxos, pegout_utxos, zk_proof_paths, funding_utxos, burnt_tokens, network)

        except (FileNotFoundError, json.JSONDecodeError, ValueError) as e:
            print(f"Error loading wallet data: {e}")
            return None
        

    def save_wallet(self, wallet_path: str):
        """
        Save the wallet data to a JSON file.

        Args:
            wallet_path (str): The path to save the wallet configuration file.
        """
        data = {}
        for (i, name) in enumerate(self.names):
            bsv_priv_key_hex = self.bsv_wallets[i].to_hex()
            sui_address_hex = self.sui_addresses[i].hex()
            genesis_utxos_hex = [utxo.to_hexstr() for utxo in self.genesis_utxos[i]]
            token_utxos_hex = [utxo.to_hexstr() for utxo in self.token_utxos[i]]
            pegout_utxos_hex = [utxo.to_hexstr() for utxo in self.pegout_utxos[i]]
            zk_proof_path_str = [path for path in self.zk_proof_paths[i]]
            funding_utxos_hex = [utxo.to_hexstr() for utxo in self.funding_utxos[i]]
            burnt_tokens_hex = [utxo.to_hexstr() for utxo in self.burnt_tokens[i]]
            data[name] = {}
            data[name]["bsv_wallet"] = bsv_priv_key_hex
            data[name]["sui_address"] = sui_address_hex
            data[name]["genesis_utxos"] = genesis_utxos_hex
            data[name]["token_utxos"] = token_utxos_hex
            data[name]["pegout_utxos"] = pegout_utxos_hex
            data[name]["zk_proof_paths"] = zk_proof_path_str
            data[name]["funding_utxos"] = funding_utxos_hex
            data[name]["burnt_tokens"] = burnt_tokens_hex

        with open(wallet_path, 'w') as file:
            json.dump(data, file, indent=4)
        print(f"Wallet successfully saved to {wallet_path}")

        return


    def get_funding(self, wallet_index: int):
        assert isinstance(self.network, RPCInterface), "get_funding is supported only for regtest"

        funding_txid = self.network.send_to_address(self.bsv_wallets[wallet_index].get_address())
        for i in range(5):
            try:
                self.network.generate_blocks(1)
                break
            except:
                pass
        funding_tx = tx_from_id(funding_txid, self.network)
        index = None
        for (i, outputs) in enumerate(funding_tx.tx_outs):
            if outputs.script_pubkey == self.bsv_wallets[wallet_index].get_locking_script():
                index = i
                break
        assert index is not None
        self.add_funding(wallet_index, Outpoint(funding_txid, index))

        return


    def setup(self, wallet_index: int):
        """Split funds for wallet_index into 10 smaller denominations.
        
        To be called only at the beginning of the DEMO. It assumes the address only has one UTXO for funding."""
        funding_tx = tx_from_id(self.funding_utxos[wallet_index][0].prev_tx, self.network)
        amount = funding_tx.tx_outs[self.funding_utxos[wallet_index][0].prev_index].amount
        split_amount = BALLPARK_TRANSACTION_FEE
        remaning_amount = amount - split_amount * 10 - BALLPARK_BURNING_TX_FEE

        outputs = [p2pkh(self.bsv_wallets[wallet_index], split_amount) for _ in range(10)]
        outputs.append(p2pkh(self.bsv_wallets[wallet_index], BALLPARK_BURNING_TX_FEE))
        outputs.append(p2pkh(self.bsv_wallets[wallet_index], remaning_amount))

        (spending_tx, response) = spend_p2pkh(
            [funding_tx],
            [self.funding_utxos[wallet_index][0].prev_index],
            outputs,
            11,
            [self.bsv_wallets[wallet_index]],
            50,
            self.network
        )

        assert response.status_code == 200, f"Error spending UTXO: {response.content}"

        self.funding_utxos[wallet_index] = []
        to_add = []
        for i, _ in enumerate(spending_tx.tx_outs):
            to_add.append(Outpoint(spending_tx.id(), i))
        self.funding_utxos[wallet_index].extend(to_add)

        return


    def generate_genesis_for_pegin(self, wallet_index: int):
        """Generate genesis for pegin.
        
        Uses last funding UTXO as that is the one with most funds by design."""
        funding_tx = tx_from_id(self.funding_utxos[wallet_index][-1].prev_tx, self.network)
        funding_index = self.funding_utxos[wallet_index][-1].prev_index
        genesis = p2pkh(self.bsv_wallets[wallet_index], 1)
        change = p2pkh(self.bsv_wallets[wallet_index], funding_tx.tx_outs[funding_index].amount - 1)

        (spending_tx, response) = spend_p2pkh(
            [funding_tx],
            [funding_index],
            [genesis, change],
            1,
            [self.bsv_wallets[wallet_index]],
            50,
            self.network
        )

        assert response.status_code == 200, f"Error spending UTXO: {response.content}"

        data = {
            "proof_name": f"proof_{spending_tx.id()}",
            "chain_parameters" : {
                "input_index": 1,
                "output_index": 0,
            },
            "public_inputs" : {
                "outpoint_txid": spending_tx.id(),
                "genesis_txid": spending_tx.id(),
            },
            "witness" : {
                "tx": "",
                "prior_proof_path": ""
            }
        }
        # Write data
        with open(str(Path(__file__).parent.parent.parent / "zk_engine/data/tcp_engine/configs/prove.toml"), "w") as f:
            toml.dump(data, f)
            f.close()
        # Generate proof
        subprocess.run(
            f"cd {Path(__file__).parent.parent.parent / "zk_engine"} && {TRANSFER_ZK_PROOF}",
            shell=True,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        self.genesis_utxos[wallet_index].append(Outpoint(spending_tx.id(), 0))
        self.zk_proof_paths[wallet_index].append(f"proof_{spending_tx.id()}")
        self.token_utxos[wallet_index].append(Outpoint(spending_tx.id(), 0))
        self.funding_utxos[wallet_index].pop(-1)
        self.funding_utxos[wallet_index].append(Outpoint(spending_tx.id(), 1))

        return


    def generate_pegout(self, wallet_index: int, issuer_index: int, token_index: int):
        funding_tx = tx_from_id(self.funding_utxos[issuer_index][-1].prev_tx, self.network)
        funding_index = self.funding_utxos[issuer_index][-1].prev_index

        genesis_tx = tx_from_id(self.genesis_utxos[wallet_index][token_index].prev_tx, self.network)

        vk, _, prepared_vk = load_and_process_vk(genesis_tx.hash())
        pegout = generate_pob_utxo(vk, prepared_vk)
        change = p2pkh(self.bsv_wallets[issuer_index], funding_tx.tx_outs[funding_index].amount)

        (spending_tx, response) = spend_p2pkh(
            [funding_tx],
            [funding_index],
            [pegout, change],
            1,
            [self.bsv_wallets[issuer_index]],
            50,
            self.network
        )

        assert response.status_code == 200, f"Error spending UTXO: {response.content}"

        self.pegout_utxos[wallet_index].append(Outpoint(spending_tx.id(), 0))
        self.funding_utxos[issuer_index].pop(-1)
        self.funding_utxos[issuer_index].append(Outpoint(spending_tx.id(), 1))

        return


    def add_pegout(self, wallet_index: int, pegout: Outpoint):
        self.pegout_utxos[wallet_index].append(pegout)
        
        return


    def add_funding(self, wallet_index: int, funding: Outpoint):
        self.funding_utxos[wallet_index].append(funding)
        return


    def __generate_transfer_zk_proof(self, spending_tx: Tx, wallet_index: int, token_index: int):
        data = {
            "proof_name": self.zk_proof_paths[wallet_index][token_index],
            "chain_parameters" : {
                "input_index": 1,
                "output_index": 0,
            },
            "public_inputs" : {
                "outpoint_txid": spending_tx.id(),
                "genesis_txid": self.genesis_utxos[wallet_index][token_index].prev_tx
            },
            "witness" : {
                "tx": spending_tx.serialize().hex(),
                "prior_proof_path": self.zk_proof_paths[wallet_index][token_index]
            }
        }
        # Write data
        with open(str(Path(__file__).parent.parent.parent / "zk_engine/data/tcp_engine/configs/prove.toml"), "w") as f:
            toml.dump(data, f)
            f.close()
        # Generate proof
        subprocess.run(
            f"cd {Path(__file__).parent.parent.parent / "zk_engine"} && {TRANSFER_ZK_PROOF}",
            shell=True,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        return


    def __generate_burning_zk_proof(self, wallet_index: int, spending_tx: Tx, token_index: int):
        data = {
            "genesis_txid" : self.genesis_utxos[wallet_index][token_index].prev_tx,
            "spending_tx": spending_tx.serialize().hex(),
            "tcp_proof_name": self.zk_proof_paths[wallet_index][token_index],
            "prev_amount": 1,
        }
        # Write data
        with open(str(Path(__file__).parent.parent.parent / "zk_engine/data/pob_engine/configs/prove.toml"), "w") as f:
            toml.dump(data, f)
            f.close()
        # Generate proof
        subprocess.run(
            f"cd {Path(__file__).parent.parent.parent / "zk_engine"} && {BURNING_ZK_PROOF}",
            shell=True,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        return


    def transfer_token(self, sender_index: int, receiver_index: int, token_index: int = 0):
        """Transfer the token from sender_index to receiver_index."""
        token_tx = tx_from_id(self.token_utxos[sender_index][token_index].prev_tx, self.network)
        token_tx_index = self.token_utxos[sender_index][token_index].prev_index
        funding_tx = tx_from_id(self.funding_utxos[receiver_index][0].prev_tx, self.network)
        funding_tx_index = self.funding_utxos[receiver_index][0].prev_index

        token_output = p2pkh(self.bsv_wallets[receiver_index], 1)

        (spending_tx, response) = spend_p2pkh(
            [funding_tx, token_tx],
            [funding_tx_index, token_tx_index],
            [token_output],
            0, # dummy
            [self.bsv_wallets[receiver_index], self.bsv_wallets[sender_index]],
            0,
            self.network
        )

        assert response.status_code == 200, f"Error spending UTXO: {response.content}"

        self.__generate_transfer_zk_proof(spending_tx, sender_index, token_index)

        self.token_utxos[sender_index].pop(token_index)
        self.funding_utxos[receiver_index].pop(0)

        genesis_utxo = self.genesis_utxos[sender_index].pop(token_index)
        pegout_utxo = self.pegout_utxos[sender_index].pop(token_index)
        zk_proof_path = self.zk_proof_paths[sender_index].pop(token_index)
        
        self.genesis_utxos[receiver_index].append(genesis_utxo)
        self.pegout_utxos[receiver_index].append(pegout_utxo)
        self.token_utxos[receiver_index].append(Outpoint(spending_tx.id(), 0))
        self.zk_proof_paths[receiver_index].append(zk_proof_path)

        return
    

    def __generate_pegout_unlocking_script(self, wallet_index: int, token_index: int):
        with open(str(Path(__file__).parent.parent.parent / "zk_engine/data/pob_engine/proofs/proof_of_burn.bin"), "rb") as f:
            proof_bytes = list(f.read())
            proof = ProofMnt4753.deserialise(proof_bytes[8:])
        with open(str(Path(__file__).parent.parent.parent / "zk_engine/data/pob_engine/proofs/input_proof_of_burn.bin"), "rb") as f:
            processed_input_bytes = list(f.read())
            # Bit length of a single input
            length = (MNT4_753.scalar_field.get_modulus().bit_length() + 8) // 8
            # Fetch the second input (the first one is the genesis_txid, which we hard-coded)
            # Bytes are:
            #   [total length of bytestring] [2 as u64] [genesis_txid as element in MNT4_753.scalar_field] [integrity tag = sighash]
            input = [ScalarFieldMNT4.deserialise(processed_input_bytes[16 + length :]).to_int()]

        genesis_tx = tx_from_id(self.genesis_utxos[wallet_index][token_index].prev_tx, self.network)
        _, cache_vk, _ = load_and_process_vk(genesis_tx.hash())

        # Prepare the proof
        prepared_proof = proof.prepare_for_zkscript(cache_vk, input)

        # Generate unlocking script
        unlock_key = RefTxUnlockingKey.from_data(
            groth16_model=mnt4_753,
            pub=input,
            A=prepared_proof.a,
            B=prepared_proof.b,
            C=prepared_proof.c,
            gradients_pairings=[
                prepared_proof.gradients_b,
                prepared_proof.gradients_minus_gamma,
                prepared_proof.gradients_minus_delta,
            ],
            gradients_multiplications=prepared_proof.gradients_multiplications,
            max_multipliers=None,
            gradients_additions=prepared_proof.gradients_additions,
            inverse_miller_output=prepared_proof.inverse_miller_loop,
            gradient_precomputed_l_out=prepared_proof.gradient_gamma_abc_zero,
        )
        
        return unlock_key.to_unlocking_script(mnt4_753)


    def burn_token(self, wallet_index: int, token_index: int):
        """Burn the token at token_index owned by the address at wallet_index."""

        token_tx = tx_from_id(self.token_utxos[wallet_index][token_index].prev_tx, self.network)
        token_tx_index = self.token_utxos[wallet_index][token_index].prev_index
        pegout_tx = tx_from_id(self.pegout_utxos[wallet_index][token_index].prev_tx, self.network)
        pegout_tx_index = self.pegout_utxos[wallet_index][token_index].prev_index
        funding_tx = tx_from_id(self.funding_utxos[wallet_index][BURNING_FUNDING_INDEX].prev_tx, self.network)
        funding_tx_index = self.funding_utxos[wallet_index][BURNING_FUNDING_INDEX].prev_index

        output_script = Script.parse_string("OP_0 OP_RETURN")
        extended_address = bytes.fromhex("00") * (32 - len(self.sui_addresses[wallet_index])) + self.sui_addresses[wallet_index]
        output_script.append_pushdata(extended_address)

        spending_tx = Tx(
            version=1,
            tx_ins=[
                tx_to_input(pegout_tx, pegout_tx_index, Script()),
                tx_to_input(token_tx, token_tx_index, Script()),
                tx_to_input(funding_tx, funding_tx_index, Script())
            ],
            tx_outs=[
                TxOut(amount=0, script_pubkey=output_script)
            ],
            locktime=0,
        )

        self.__generate_burning_zk_proof(wallet_index, spending_tx, token_index)

        pegout_unlocking_script = self.__generate_pegout_unlocking_script(wallet_index, token_index)

        inputs = [
            tx_to_input(pegout_tx, pegout_tx_index, pegout_unlocking_script),
            tx_to_input(token_tx, token_tx_index, bytes_to_script(bytes.fromhex(self.bsv_wallets[wallet_index].get_public_key_as_hexstr()))),
            tx_to_input(funding_tx, funding_tx_index, bytes_to_script(bytes.fromhex(self.bsv_wallets[wallet_index].get_public_key_as_hexstr()))),
        ]

        spending_tx = Tx(
            version=1,
            tx_ins=inputs,
            tx_outs=spending_tx.tx_outs,
            locktime=0,
        )

        spending_tx = prepend_signature(
            token_tx,
            spending_tx,
            1,
            self.bsv_wallets[wallet_index],
        )

        spending_tx = prepend_signature(
            funding_tx,
            spending_tx,
            2,
            self.bsv_wallets[wallet_index],
        )


        response = self.network.broadcast_tx(spending_tx.serialize().hex())
        assert response.status_code == 200, f"Error burning pegout: {response.content}"
        
        genesis_txid = self.genesis_utxos[wallet_index].pop(token_index)
        self.token_utxos[wallet_index].pop(token_index)
        self.pegout_utxos[wallet_index].pop(token_index)
        self.zk_proof_paths[wallet_index].pop(token_index)
        self.burnt_tokens[wallet_index].append(BurntToken(
            genesis_txid.prev_tx,
            spending_tx.id(),
        ))

        return
