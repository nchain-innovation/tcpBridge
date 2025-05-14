import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent.parent / "zkscript_package"))

from elliptic_curves.data_structures.vk import PreparedVerifyingKey
from elliptic_curves.data_structures.zkscript import ZkScriptVerifyingKey
from elliptic_curves.instantiations.mnt4_753.mnt4_753 import MNT4_753, VerifyingKeyMnt4753
from tx_engine import SIGHASH, Tx, TxOut, Wallet

from src.zkscript.groth16.mnt4_753.mnt4_753 import mnt4_753
from src.zkscript.reftx.reftx import RefTx
from src.zkscript.script_types.locking_keys.reftx import RefTxLockingKey

ScalarFieldMNT4 = MNT4_753.scalar_field


def load_and_process_vk(genesis_txid: bytes) -> list[VerifyingKeyMnt4753, PreparedVerifyingKey, ZkScriptVerifyingKey]:
    genesis_txid_as_input = int.from_bytes(genesis_txid, "little")
    
    with open(str(Path(__file__).parent.parent.parent / "zk_engine/data/pob_engine/keys/vk.bin"), "rb") as f:
        vk_bytes = list(f.read())
        vk = VerifyingKeyMnt4753.deserialise(vk_bytes[8:])

        # Precompute locking data
        precomputed_l_out = vk.gamma_abc[0] + vk.gamma_abc[1].multiply(genesis_txid_as_input)
        # Modified gamma_abc
        gamma_abc_mod = [precomputed_l_out, *vk.gamma_abc[2:]]
        # Modified vk
        vk_mod = VerifyingKeyMnt4753(vk.alpha, vk.beta, vk.gamma, vk.delta, gamma_abc_mod)
        # Prepare the vk
        cache_vk = vk_mod.prepare()
        prepared_vk = vk_mod.prepare_for_zkscript(cache_vk)

        return vk_mod, cache_vk, prepared_vk


def generate_pob_utxo(
    vk: PreparedVerifyingKey, prepared_vk: ZkScriptVerifyingKey
) -> TxOut:
    # Generate PoB locking script
    locking_key = RefTxLockingKey(
        alpha_beta=prepared_vk.alpha_beta,
        minus_gamma=prepared_vk.minus_gamma,
        minus_delta=prepared_vk.minus_delta,
        precomputed_l_out=vk.gamma_abc[0].to_list(),
        gamma_abc_without_l_out=[element.to_list() for element in vk.gamma_abc[1:]],
        gradients_pairings=[
            prepared_vk.gradients_minus_gamma,
            prepared_vk.gradients_minus_delta,
        ],
        sighash_flags=SIGHASH.ALL_FORKID,
    )

    lock = RefTx(mnt4_753).locking_script(
        sighash_flags=SIGHASH.ALL_FORKID,
        locking_key=locking_key,
        modulo_threshold=200 * 8,
        max_multipliers=None,
        check_constant=True,
    )

    return TxOut(amount=1, script_pubkey=lock)