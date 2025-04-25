# Python cli

The python cli is the cli that orchestrates the whole codebase.
Below is a breakdown of the available commands.

> [!NOTE]
> The commands `pegin` and `pegout` below call the move functions `pegin_with_chunks` and `pegout_with_chunks` from the `tcpbridge` see ([docs/tcpbridge](tcpbridge.md)) via the `sui` cli (see [docs/sui](./sui.md)).

## Getting started

Create a file called `wallet.json` inside the folder [cli](../cli/).
Use the same structure as the file [empty_wallet.json](../cli/empty_wallet.json) and populate the fields:
- `name`: with the name of the user
- `bsv_wallet`: with the BSV private key of the user in hex format
- `sui_address`: with the Sui address of the user

> [!NOTE]
> As at the moment the [sui](../cli/sui/) cli uses the active address by default, you must the address that is active in your sui wallet as the `sui_address` for all users. You can get it via the command `sui client active-address`

> [!NOTE]
> Remember to always have a user called `issuer`.

To get started, you need to get funding for the users.
How you get funding depends on which network you are using:
- If you are using `regtest`, then you can skip this step
- If you are using `testnet`, you can use one of the BSV faucets, for example the [sCrypt Faucet](https://scrypt.io/faucet).
Once you have your funding transaction `funding_tx: str` and funding index `funding_index: int`, you can add it to the list of `funding_utxos` for the relevant user in the following format:

```
"funding_tx:funding_index.to_bytes(4, "little")"
```

where `funding_index.to_bytes(4, "little")` means `funding_index` as a 4-byte little endian number.
For example, `funding_tx = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`, `funding_index = 1` would be added as:

```
"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:01000000"
```

After you have added the funding utxos (you need one per user), you can execute the following command:

```
python3 -m python_cli setup --network <NETWORK>
```

where `<NETWORK>` can either be `regtest`, `testnet`, or `mainnet`.
The `setup` command will set up the wallet for use.
Namely, it will:
- Create `10` outputs per user (except `issuer`), each holding `15` satoshis, which will be used to fund genesis and transfer transactions.
- Create one output per user (except `issuer`) holding `15000` satoshis, which will be user to fund the burning transaction.
- Leave the remaning funds in the last output, so that they can be used again for another round of setup.

## Pegin

To peg in to the bridge, execute the command:

```
python3 -m python_cli pegin --user <USER> --pegin-amount <AMOUNT> --network <NETWORK>
```

This command will:
- Generate a `genesis_txid`, `genesis_index` used for pegin (done by `<USER>`)
- Generate a `pegout_txid`, `pegout_index` used for pegout (done by `<ISSUER>`)
- Add the couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` to the Sui bridge (done by `<ISSUER>`)
- Peg in `<AMOUNT>` for the couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` in the bridge (done by `<USER>`)
- Generate a zk proof that `(genesis_txid, genesis_index)` belongs to a transaction chain starting at `genesis_txid` with `input_index = 1`, `output_index = 0`.

## Transfer

To transfer a token (wrapped Sui) from a user to another, execute the command:

```
python3 -m python_cli transfer --sender <SENDER> --receiver <RECEIVER> --token-index <INDEX> --network <NETWORK>
```

This command will:
- Transfer the token owned by `<SENDER>` to `<RECEIVER>`.
The token owned by `<SENDER>` are represented as a list in the wallet, so we transfer the token at index `<INDEX>`.
- Generate a zk proof that the token received by `<RECEIVER>` is part of a transaction chain starting at `genesis_txid` with `input_index = 1`, `output_index = 0`.

> [!NOTE]
> You can print to screen the information contained in your wallet using the following command `python3 -m wallet_manager_ui --network <NETWORK>`.

## Burn

To burn a token (wrapped Sui) owned by a user, execute the following command:

```
python3 -m python_cli burn --user <USER> --token-index <INDEX> --network <NETWORK> 
```

This command will burn the token owned by `<USER>` (the token at position `<INDEX>` in the wallet) and generate a zk proof of burn.

## Pegout

> [!WARNING]
> As of now, this command will fail. This is due to the size of the burning transaction, which is above the Move limit of `256KB` for an object.

To peg out (unlock Sui), execute the following command (after having burnt the corresponding token):

```
python3 -m python_cli pegout --user <USER> --token-index <INDEX> --network <NETWORK>
```

This command will peg out on Sui for the couple given by the burnt token a position `<INDEX>` in the wallet.