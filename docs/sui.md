# Sui cli

The sui cli [sui](../cli/sui/) is a Rust crate that allows interacting with the Sui network and the packages [`blockchain_oracle`](../move/oracle/) and [`tcpbridge`](../move/bridge/).

> [!Note]
> The cli is written to work with any of the sui clients, but it is currently set up to work with the localnet client. If you want to change the behaviour, uncomment the client you want from [bridge_cli.rs](../cli/sui/src/bridge_cli.rs#L39) and set it to be the `client` in [bridge_cli.rs#L44](../cli/sui/src/bridge_cli.rs#L44).

> [!Note]
> The cli is currently uses the active address in your sui client to perform all its functions.

## Building

Before building the cli, we need to specify which instance of the [`blockchain_oracle`](../move/oracle/) and [`tcpbridge`](../move/bridge/) we want to interact with.
To do so, copy the following data (without `0x`):

- the Object ID and shared version of the `HeaderChain`
- the Package ID of `blockchain_oracle`
- the Object ID of the `BridgeAdminCap`
- the Object ID and shared version of the `Bridge`
- the Package ID of `tcpbridge`

and paste everything (in the relevant lines), in [config.rs#L11](../cli/sui/src/configs.rs#L11).
You should have obtained the above data when you published the two packages [`blockchain_oracle`](../move/oracle/) and [`tcpbridge`](../move/bridge/).
For a guide on how to do that, see [docs/blockchain_oracle](./blockchain_oracle.md) and [docs/tcpbridge](./tcpbridge.md).

After having completed the previous step, paste in [config.rs#L](../cli/sui/src/configs.rs#L36) the address of your `client.yaml` file. You can now build with

```
cargo build
```

## Available commands

The following are the available commands (also obtainable via `cargo run -- help`):
- `update-chain`: update the header chain. The block header serialisation used to update the chain is taken from the file [config_update_chain.toml](../cli/sui/config_files/config_update_chain.toml), which contains a single field `ser: str`, which is the hex representation of the block serialisation.
- `add-bridge-entry`: add an entry to the bridge (can only be used by the owner of `BridgeAdmin`). The data to be added to the chain is taken from the file [config_add_bridge_entry.toml](../cli/sui/config_files/config_add_bridge_entry.toml), which contains four fields:
    - `genesis_txid: str`: the hex representation of the genesis txid
    - `genesis_index: int`: the index of the genesis outpoint
    - `pegout_txid: str`: the hex representation of the pegout txid
    - `pegout_index: int`: the index of the pegout outpoint
- `is-valid-for-pegin`: check if a couple (genesis, pegout) is valid for pegin. The data to be checked is contained in [config_check_bridge_entry](../cli/sui/config_files/config_check_bridge_entry.toml). It contains the same fields as [config_add_bridge_entry.toml](../cli/sui/config_files/config_add_bridge_entry.toml)
- `is-valid-for-pegout`: check if a couple (genesis, pegout) is valid for pegout. The data to be checked is contained in [config_check_bridge_entry](../cli/sui/config_files/config_check_bridge_entry.toml). It contains the same fields as [config_add_bridge_entry.toml](../cli/sui/config_files/config_add_bridge_entry.toml)
- `drop-elapsed`: Drop couples for which the peg in time has elapsed. The data to be checked is contained in [config_drop_elapsed.toml](../cli/sui/config_files/config_drop_elapsed.toml). It contains two fields:
    - `genesis_txid: str`: the hex representation of the genesis txid
    - `genesis_index: int`: the index of the genesis outpoint
- `pegin`: Peg in. The data for peg in is contained in [config_pegin.toml](../cli/sui/config_files/config_pegin.toml). It contains three fields:
    - `genesis_txid: str`: the hex representation of the genesis txid
    - `genesis_index: int`: the index of the genesis outpoint
    - `pegin_amount: int`: the amount of coins to peg in to the bridge.
- `pegout`: Peg out. The data for peg out is contained in [config_pegout.toml](../cli/sui/config_files/config_pegout.toml). It contains three fields and a section:
    - `genesis_txid: str`: the hex representation of the genesis txid
    - `genesis_index: int`: the index of the genesis outpoint
    - `burning_tx: hex`: the hex representation of the transaction that burnt the tip of the transaction chain that started at genesis.
    - `merkle_proof`: a section with two fileds"
        - `positions: vector[int]`: a vector of integers specifying whether a node in the Merkle proof is a left or right node. See also 
        - `hashes: vector[str]`: a vector of strings which are the hex representations of the nodes needed to reconstruct the root of the Merkle tree. 
- `pegin-with-chunks`: Peg in with chunks. The data for this function is the same as that for `pegin`.
- `pegout-with-chunks`: Peg out with chunks. The data for this function is the same as that for `pegout`.

For more information on the move functions called by the above commands, see [docs/blockchain_oracle](./blockchain_oracle.md) and [docs/tcpbridge](./tcpbridge.md).