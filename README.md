# Bridging Ethereum and Sui to Bitcoin SV

> [!WARNING]
> All smart contracts provided in this repo is for research, experiments and demostrations only. They have not been audited for security. Deloying them to mainnet may cause loss of funds.


This repository contains proof-of-concept implementations of a bridge between Sui and Bitcoin SV and a bridge between Ethereum and Bitcoin SV. 

**For Sui:**
- In [cli](./cli/): a client written in Rust to interact with the Sui contracts and a python script sui_demo.py for demos. 
- [move](./move/): The Move code for the smart contracts to be published on Sui.

**For Ethereum:**
- [cli](./cli/): a python script evm_demo.py to semi-automate a demo.
- [evm](./evm/): the solidity smart contracts and javascripts to deploy and interact with the Ethereum contracts. 

**For ZKP used by both Sui and Ethereum bridges:**
- [zk_engine](./zk_engine/): The zero-knowledge component of the bridges.
- [zkscript_package](./zkscript_package/): A git submodule that is used to build complex Bitcoin Scripts (zkSNARK verifiers).

## Requirements

The repository requires
1. Python >= 3.12.
2. [Rust](https://www.rust-lang.org/tools/install) (with Cargo >= 1.86).
3. [Sui](https://docs.sui.io/guides/developer/getting-started) for Sui. If you want to use the Sui localnet, you might want to install the [Sui explorer](https://github.com/suiware/sui-explorer).
4. [Hardhat](https://hardhat.org/hardhat-runner/docs/guides/project-setup) for Ehtereum. 
5. [wild-bit-lab](https://github.com/nchain-innovation/wild-bit-lab) for Bitcoin SV regtest.



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

Note that this is only needed once for both bridges. The proof system is designed such that the same verification key and proving key can be used for all bridges and bridged tokens. 

See also [docs/zk_engine](./docs/zk_engine.md). 


### Setting Up BSV Regtest

1. Locate bitcoin.conf for your Regest and update [bsv_config.toml](./cli/bsv_config.toml) to make sure that the port number is the same as rpcport. If you are using [wild bit lab](https://github.com/nchain-innovation/wild-bit-lab), then it is under ```./wild-bit-lab/data/```

2. Add the following line to bitcoin.conf if they do not exist.
    ```
    maxscriptsizepolicy=100000000
    ```

3. Start or restart Regtest and make sure at least 100 blocks are mined. 


> [!NOTE]
> If you are using a `testnet` you can get funding from the [sCrypt Faucet](https://scrypt.io/faucet).

> [!NOTE]
> You can print to screen the information contained in your wallet using the following command `python3 -m wallet_manager_ui --network <NETWORK>`, where `<NETWORK>` can be either `regtest`, `testnet`, or `mainnet`.


### Setting Up Sui Network
you can follow the link in [Requirement 3](#requirements) or the steps below to setup Sui.

1. Install Sui and a local explorer.
    ```
    brew install sui
    brew install sui-explorer-local 
    ```

2. Initialise Sui. You can just press ENTER following the prompts. 
    ```
    sui client
    ```

3. Start Sui with facucet. 
    ```
    RUST_LOG="off,sui_node=info" sui start --with-faucet --force-regenesis
    ```
4. Run the following command to use localnet. 
    ```
    sui client new-env --alias local --rpc http://127.0.0.1:9000
    sui client switch --env local
    ```

5. Start a local explorer.
    ```
    sui-explorer-local start
    ```

To stop Sui, press "Control + C". To stop the local explorer, ```sui-explorer-local stop```.

## Sui Bridge Demo

1. The following command will setup example wallets, publish Oracle contract, publish Bridge contract, and build a client to interact with the contracts. 
    ```
    cd ./cli
    python -m sui_demo setup --network regtest
    ```
2. Now you can use sui_demo.py to do pegin, transfer, burn, and pegout. For examples:
    ```
    python -m sui_demo pegin --user alice --pegin-amount 32000000000 --network regtest

    python -m sui_demo transfer --sender alice --receiver bob --token-index 0 --network regtest

    python -m sui_demo burn --user bob --token-index 0 --network regtest     

    python3 -m sui_demo pegout --user bob --token-index 0 --network regtest --update
    
    ```  

3. After "pegout", you should be able to see that the user Bob has received 32 sui from a Sui explorer by search his Sui address.

You can always restart from the begining at any time. 


## Ethereum Bridge Demo

To check out Ethereum bridge on local networks, click here [README](./evm/README.md).


## License

The code is released under the attached [LICENSE](./LICENSE.txt). If you would like to use it for commercial purposes, please contact <research.enquiries@nchain.com>.

