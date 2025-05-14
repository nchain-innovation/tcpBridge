# ZK engine

The [`zk_engine`](../zk_engine/) Rust crate handles the zero-knowledge proving/verifying that ensures the security of the bridge.
The Rust crate is composed of two modules:
- [`tcp_engine`](../zk_engine/src/tcp_engine/)
- [`pob_engine`](../zk_engine/src/pob_engine/)

## TCP engine

The Transaction Chain Proof engine is used to prove/verify statements concerning _transaction chains_.
Namely, we use the TCP engine to prove/verify statements of the following form: fix `(i,j)` a couple of indices,

```
The outpoint (txid, i) is part of a chain (Tx_1, Tx_2, .., Tx_n) where each j-th input of a transaction in the chain spends the i-th output of the previous transaction.
```

For example, if `n=3`, then `Tx_2.inputs[j] = Tx_1.outputs[i]` and `Tx_3.inputs[j] = Tx_1.outputs[i]`.

We call `Tx_1` the _genesis_ transaction, as it is the first transaction in the chain, and we say that `(Tx_1, Tx_2, .., Tx_n)` is a transaction chain with input index `j` and output index `i`.

## PoB engine

The Proof of Burn engine is used to prove/verify statements about _burning_ the tip of a transaction chain.
More precisely, fix `(i,j)` and a _genesis_ transaction `Tx_1`.
Then, we use the PoB engine to prove/verify statements of the following form:

```
The transaction Tx_burn is such that:
- Tx_burn.inputs[j] is part of a transaction chain with input index i and output index i starting at Tx_1
- Tx_burn has only one output, which is unspendable
```

We call the transaction `Tx_burn` a _burning transaction_ as it _burns_ the tip of a transaction chain started at `Tx_1`, ending the transaction chain.

## Getting started

To use the engines, first one needs to generate proving/verifying keys.
To do so, create the folders `zk_engine/data/<ENGINE_NAME>/configs`.
Then, in each folder create a `setup.toml` file and populate it as follows:

- For the TCP engine
    ```
    input_index = j
    output_index = i
    ```
- For the POB engine
    ```
    index = output_index
    ``

Then, execute the following command

```
cargo run -- setup
```

This will generate proving/verifying keys for both engine in the folder `zk_engine/data/`.
If you want to generate keys only for one of the engines, execute

```
cargo run -- <ENGINE_NAME> setup
```

where `<ENGINE_NAME>` can be either `tcp-engine` or `pob-engine`.

> [!NOTE]
> If you generate new keys for the `tcp-engine`, you will need to generate new keys also for the `pob-engine`. The reverse is not true: you can update the keys for the `pob-engine` without updating the keys for the `tcp-engine`.

> [!NOTE]
> To use the PoC implementation, set `input_index = 1`, `output_index = 0`, `index = 0`.

## Proving

To prove statements, the command is

```
cargo run -- <ENGINE_NAME> prove
```

The command will fetch the proving key and the data to generate a proof for from the file `prove.toml` contained in `zk_engine/data/<ENGINE_NAME>/configs`.
The data depends on the engine.

### Proving data - TCP engine

The structure of the proving data for the TCP engine is the following:

```
proof_name: str

[chain_parameters]
input_index: int
output_index: int

[public_inputs]
outpoint_txid: str
genesis_txid: str

[witness]
tx: str
prior_proof_path: str
```

where

- `proof_name` is the name of the proofs that gets generated.
It will be saved under `zk_engine/data/tcp_engine/proofs`
- `input_index`, `output_index` are the indices chosen at setup
- `outpoint_txid` is the Txid of the transaction for which you want to prove that `(outpoint_txid, output_index)` is in a transaction chain starting from `genesis_txid`
- `genesis_txid` is the Txid of the genesis transaction in the transaction chain
- `tx` is the transaction whose Txid is `outpoint_txid`. If `outpoint_txid = genesis_txid`, then `tx = ""`.
- `prior_proof_path` is the name the of the proof for the _prior_ outpoint_txid, i.e., the proof generated when executing the `prove` command on the outpoint reference by `tx.inputs[input_index]`. The proof must be located in `zk_engine/data/tcp_engine/proofs`. If `outpoint_txid = genesis_txid`, then `prior_proof_path = ""`.

### Proving data - PoB engine

The structure of the proving data for the PoB engine is the following:

```
genesis_txid: str
spending_tx: str
tcp_proof_name: str
prev_amount: int
```

where

- `genesis_txid` is the Txid of the genesis transaction of the transaction chain of which `spending_tx.inputs[index]` is a part of.
- `spending_tx` is the transaction that burns the tip of the transaction chain started at `genesis_txid`
- `tcp_proof_name` is the name of the proof proving (via the TCP engine) that `spending_tx.inputs[index]` is part of the transaction chain started at `genesis_txid` (it must be located in `zk_engine/data/tcp_engine/proofs`)
- `prev_amount` is the amount held by the UTXO reference by `spending_tx.inputs[index]`

## Verifying

To verify statements, the command is

```
cargo run -- <ENGINE_NAME> verify
```

The command will fetch the verifying key and the data to verify a proof for.
The data depends on the engine.

### Verifying data - TCP engine

The structure of the verifying data for the TCP engine is the following:

```
proof_name: str

[chain_parameters]
input_index: int
output_index: int

[public_inputs]
outpoint_txid: str
genesis_txid: str
```

where the data is defined as before.

To verify a proof, create a file `verify.toml` in the folder `zk_engine/data/tcp_engine/configs` and populate it with the above data.

### Verifying data - PoB engine

At the moment, the PoB engine allows verification only of the latest generated proof.
As such, it doesn't require any data.
It is enough to execute the verification command.





