
import requests

from tx_engine import hash256d
from tx_engine.interface.interface_factory import WoCInterface, RPCInterface

class BlockHeader:
    def __init__(self, version: int, hash_prev_block: bytes, hash_merkle_root: bytes, time: int, bits: bytes, nonce: int):
        self.version = version
        self.hash_prev_block = hash_prev_block
        self.hash_merkle_root = hash_merkle_root
        self.time = time
        self.bits = bits
        self.nonce = nonce

    def __repr__(self):
        return f"BlockHeader(\nversion={self.version},\nhash_prev_block={self.hash_prev_block[::-1].hex()},\nhash_merkle_root={self.hash_merkle_root[::-1].hex()},\ntime={self.time},\nbits={self.bits[::-1].hex()},\nnonce={self.nonce})"

    def serialise(self):
        return self.version.to_bytes(4, "little") + self.hash_prev_block + self.hash_merkle_root + self.time.to_bytes(4, "little") + self.bits + self.nonce.to_bytes(4, "little")
    
    def hash(self):
        return hash256d(self.serialise())
    
    def get_target(self):
        return 256**(self.bits[-1] - 3) * int.from_bytes(self.bits[:-1], "little")

    @staticmethod
    def get(block_hash: str, connection: WoCInterface | RPCInterface):
        block_header_json = connection.get_block_header(block_hash)
        return BlockHeader(
            version=block_header_json["version"],
            hash_prev_block=bytes.fromhex(block_header_json["previousblockhash"])[::-1],
            hash_merkle_root=bytes.fromhex(block_header_json["merkleroot"])[::-1],
            time=int(block_header_json["time"]),
            bits=bytes.fromhex(block_header_json["bits"])[::-1],
            nonce=int(block_header_json["nonce"])
        )

class MerkleProof:

    def __init__(self, index: int, nodes: list[bytes]):
        self.index = index
        self.nodes = nodes
        
    def __repr__(self):
        return f"MerkleProof(\nindex={self.index},\nnodes=[{"".join([f"\n\t{node.hex()}," for node in self.nodes])}\n])"
    
    @staticmethod
    def get_merkle_proof(block_hash: str, tx_id: str, connection: WoCInterface | RPCInterface):
        if isinstance(connection, WoCInterface):
            merkle_proof_json = connection.get_merkle_proof(block_hash, tx_id)[0]
        else:
            payload = {
                        "method": "getmerkleproof2",
                        "params": [block_hash, tx_id],
                        "jsonrpc": "2.0",
                        "id": 1
            }
            merkle_proof_json = requests.post("http://" + connection.address, json=payload, auth=(connection.user, connection.password)).json()["result"]
        index = merkle_proof_json["index"]
        nodes = [bytes.fromhex(node)[::-1] for node in merkle_proof_json["nodes"]]
        return MerkleProof(index, nodes)
    
    def positions(self):
        out = []
        index = self.index
        for _ in range(len(self.nodes)):
            out.append(index & 1)
            index >>= 1
        return out
    
    def validate(self, tx_id: str, target: bytes):
        # Use positions to mimic what happens in Move
        positions = self.positions()
        hash = bytes.fromhex(tx_id)[::-1]
        for i in range(len(self.nodes)):
            if positions[i]:
                hash = hash256d(self.nodes[i] + hash)
            else:
                hash = hash256d(hash + self.nodes[i])
        return hash == target
