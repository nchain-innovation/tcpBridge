# SUI - BSV bridge

> [!WARNING]
> As of now, it is not possible to peg out from the bridge. This is because the size of the final transaction that should be submitted to Sui is above the allowed limits, see [docs/tcp_bridge](./docs/tcpbridge.md). We are working on reducing the size of the final transaction.


This repository contains a proof-of-concept implementation of a bridge between Sui and BSV.
The repository serves as a monorepo for this project.
It contains:
- [cli](./cli/): The CLI to interact with the bridge.
- [move](./move/): The Move code for the smart contracts published on Sui.
- [zk_engine](./zk_engine/): The zero-knowledge component of the bridge.
- [zkscript_package](./zkscript_package/): A git submodule that is used to build complex Bitcoin Scripts (zkSNARK verifiers).

## Requirements

The repository requires Python >= 3.12, [Rust](https://www.rust-lang.org/tools/install) (with Cargo >= 1.86), and [Sui](https://docs.sui.io/guides/developer/getting-started).
If you want to use the Sui localnet, you might want to install the [Sui explorer](https://github.com/suiware/sui-explorer).

## Getting started

To initialise the repository, execute the following commands:

### Cloning
```
git clone https://github.com/nchain-innovation/tcpBridge.git
cd tcpBridge
git submodule update --init --recursive
git submodule update --remote
cd zkscript_package
pip install -r requirements.txt
cd ../cli
pip install -r requirements.txt
```

### ZK engine setup

To setup the zk engine, i.e., generating proving and verification keys, execute the following commands.
The repository already contains example setup files required for the `setup` command.

```
cd zk_engine
cargo run --release -- setup
```

See also [docs/zk_engine](./docs/zk_engine.md).

### Publish Sui packages and setup sui cli

> [!NOTE]
> Before executing the following commands, ensure that your Sui client is connected to the correct network (localnet, devnet, testnet, mainnet).

> [!NOTE]
> Before executing the following command, you need to choose the block header from which the blockchain oracle will start and paste the relevant information in [`blockchain_oracle.move`](./move/oracle/sources/blockchain_oracle.move). See [docs/blockchain_oracle](./docs/blockchain_oracle.md) for more information.

To publish the `blockchain_oracle` Sui package

```
cd move/oracle
sui client publish
```

Get the Object ID of the `HeaderChain` genereted by the above command and paste it into [tcpbridge](./move/bridge/sources/tcpbridge.move#L34).
Then, execute the following command to publish the `tcpbridge` package.

> [!NOTE]
> The bridge depends on a few configuration parameters: [`COIN_VALUE`](./move/bridge/sources/backed_pool.move#L21), [`MIN_PEGOUT_DELAY`](./move/bridge/sources/backed_pool.move#L22), [`N_CHUNKS_BURNING_TX`](./move/bridge/sources/backed_pool.move#L23). They are set up to `10`, `0`, and `4` respectively. See [docs/tcpbridge](./docs/tcpbridge.md) for their meaning in case you want to change them.


```
cd move/bridge
sui client publish
```

At this point, to setup the sui cli copy (without `0x`):

- the Object ID and shared version of the `HeaderChain`
- the Package ID of `blockchain_oracle`
- the Object ID of the `BridgeAdminCap`
- the Object ID and shared version of the `Bridge`
- the Package ID of `tcpbridge`

and paste them in [configs.rs](./cli/sui/src/configs.rs).
Also, fill in the path [config.rs](./cli/sui/src/configs.rs#L36) with the path to your local Sui wallet.
Then, run

```
cd cli/sui
cargo build
```

For documentation on the Sui packages, see [docs/blockchain_oracle](./docs/blockchain_oracle.md) and [docs/tcpbridge](./docs/tcpbridge.md).
For documentation on the Sui cli, see [docs/sui](./docs/sui.md).

## Usage

If you have succesfully completed the above section, you are ready to use the bridge.

### Wallet and users

Create a file `wallet.json` under [./cli](./cli/).
Use the same structure as the file [`empty_wallet.json`](./cli/empty_wallet.json) and populate the fields:
- `name`: the name of the user
- `bsv_wallet`: the user BSV private key in hex format
- `sui_address`: the user Sui public address

> [!NOTE]
> Remember to always leave a user with name _issuer_.

If you have some funding you wish to use, you can add them to the `funding_utxos` using the following format: for a UTXO given by `(txid, index)`, add the string

```
txid:index.to_bytes(4, "little")
```

where `index.to_bytes(4, "little")` means `index` as a 4-byte number in little endian.
For example, the UTXO `(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, 1)` would be added as

```
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:01000000
```

> [!NOTE]
> If you are using a `regtest` environment for BSV, you can get funding from the cli. Run the command `python3 -m python_cli setup --network setup` after having added your BSV addresses to `wallet.json`.

> [!NOTE]
> If you are using a `testnet` you can get funding from the [sCrypt Faucet](https://scrypt.io/faucet).

> [!NOTE]
> You can print to screen the information contained in your wallet using the following command `python3 -m wallet_manager_ui --network <NETWORK>`, where `<NETWORK>` can be either `regtest`, `testnet`, or `mainnet`.

### Setup

Once you've populated `wallet.json` with your keys/addresses, and you have gotten some funding, you can set up the wallet for use.
To do so, execute the following command

```
python3 -m python_cli setup --network <NETWORK>
```

You are now ready to use the bridge.
For the avaiable commands, see [python_cli](./docs/python_cli.md).

## License

The code is released under the attached [LICENSE](./LICENSE.txt). If you would like to use it for commercial purposes, please contact <research.enquiries@nchain.com>.

