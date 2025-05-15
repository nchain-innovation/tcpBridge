# Transaction Chain Proof Bridge

The [tcpbridge](../move/bridge/) package contains the implementation of the bridge between Sui and BSV. It contains the following files:
- [admin](../move/bridge/sources/admin.move): it creates the `BridgeAdmin` capatibility, that gives the publisher of the bridge the capability to add entries to the bridge.
- [tranasactions](../move/bridge/sources/transactions.move): it contains implementation of Bitcoin objects such as transactions and transaction ids. These structs are used for internal representation of the data in the bridge.
- [unbacked_pool](../move/bridge/sources/unbacked_pool.move): it contains the implementation of `UnbackedPool`, a struct where bridge entries reside until a user pegs in by sending coins to the bridge.
- [backed_pool](../move/bridge/sources/backed_pool.move): it contains the implementation of `BackedPool`, a struct where bridge entries that are backed by some coins reside until a user requests to peg them out.
- [tcp_bridge](../move/bridge/sources/tcpbridge.move): it contains the implementation of `Bridge`, the struct which ties all the above structs together, i.e., the real bridge.

## Publishing the package

To publish the package, you need to specify the Object ID of an [`HeaderChain`](../move/oracle/sources/block_header.move#L30).
This is because to validate a peg out request the bridge checks the SPV for a transaction, for which it requires a block header.
To ensure that the users submit a specific instance of `HeaderChain`, we hard-code its Object ID when publishing the `tcpbridge` package.

To publish the [`blockchain_oracle`](../move/oracle/) package, follow the instructions in [docs/blockchain_oracle](./blockchain_oracle.md).
Then, copy the Object ID of the `HeaderChain` that you created, and paste it in [tcpbridge.move](../move/bridge/sources/tcpbridge.move#L34).

Before publishing, you need to choose the configuration parameters of the bridge, they are:
- [`COIN_VALUE`](./move/bridge/sources/backed_pool.move#L21): the minimum amount require to peg in with
- [`MIN_PEGOUT_DELAY`](./move/bridge/sources/backed_pool.move#L22): the minimum number of blocks that have to be mined on top of the block containing the burning transaction before the peg out can be executed.
- [`N_CHUNKS_BURNING_TX`](./move/bridge/sources/backed_pool.move#L23): the number of chunks the burning transaction is split into for storage on the Sui blockchain. See also [With Chunks](#with-chunks).

```
sui client publish
```

## System design

For the system design, see [docs/system_design](./system_design.md).

## Public entry functions

The [`Bridge`](../move/bridge/sources/tcpbridge.move#L50) struct has various public entry functions:
- [add](../move/bridge/sources/tcpbridge.move#L72): this function allows the owner of `BridgeAdmin` to add an entry `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` to the bridge. From the moment the bridge admin adds the couple to the bridge, the user has [PEGIN_TIME](../move/bridge/sources/unbacked_pool.move#L8) to peg in to the bridge. After that time, the bridge admin can remove the couple from the bridge. This function can be called vai the sui cli, see [sui](./sui.md).
- [drop_elapsed](../move/bridge/sources/tcpbridge.move#L91): this function allows the owner of `BridgeAdming` to remove an entry for which [PEGIN_TIME](../move/bridge/sources/unbacked_pool.move#L8) has elapsed.
- [is_valid_for_pegin](../move/bridge/sources/tcpbridge.move#L107): this function can be called to check whether a couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` is a valid couple for peg in, i.e., it was added to the `UnbackedPool`, and the pegin time has not elapsed. This function can be called vai the sui cli, see [sui](./sui.md).
- [get_pegout](../move/bridge/sources/tcpbridge.move#L134): this function can be called to retrieve the pegout UTXO attached to a couple `((genesis_txid, genesis_index), (_, _))`
- [is_valid_for_pegout](../move/bridge/sources/tcpbridge.move#L144): this function can be called to check whether a couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` is a valid couple for peg out, i.e., whether it was added to the `BackedPool`, and the pegin time has not elapsed. This function can be called vai the sui cli, see [sui](./sui.md).
- [pegin](../move/bridge/sources/tcpbridge.move#L165): this function can be called to peg in with respect to a couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` which is currently in the `UnbackedPool`. When calling this function, the user specifies the `pegin_amount`, which says how many coins the user wants to lock in the bridge.This function can be called vai the sui cli, see [sui](./sui.md).
- [pegout](../move/bridge/sources/tcpbridge.move#L187): this function can be called to peg out with respect to a couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` which is currently in the `BackedPool`. It requires a `burning_tx` (the transaction in which the BSV token holding the SUI was burnt), the Merkle proof of inclusion of `burning_tx`, and the `block_height` at which `burning_tx` was mined. This function can be called vai the sui cli, see [sui](./sui.md).
- [get_coin_value](../move/bridge/sources/tcpbridge.move#L217): this function can be called to get the coin amount locked in the bridge for the couple `((genesis_txid, genesis_index), (_, _))`.
- [is_valid_for_pegout_with_chunks](../move/bridge/sources/tcpbridge.move#L144): this function can be called to check whether a couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` is a valid couple for peg out, i.e., whether it was added to the `BackedPool` (with chunks, see ), and the pegin time has not elapsed. This function can be called vai the sui cli, see [sui](./sui.md).
- [pegin_with_chunks](../move/bridge/sources/tcpbridge.move#L165): this function can be called to peg in (with chunks, see ) with respect to a couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` which is currently in the `UnbackedPool`. When calling this function, the user specifies the `pegin_amount`, which says how many coins the user wants to lock in the bridge.This function can be called vai the sui cli, see [sui](./sui.md).
- [pegout_with_chunks](../move/bridge/sources/tcpbridge.move#L187): this function can be called to peg out with respect to a couple `((genesis_txid, genesis_index), (pegout_txid, pegout_index))` which is currently in the `BackedPool` (with chunks, see ). It requires a `burning_tx` (the transaction in which the BSV token holding the SUI was burnt), the Merkle proof of inclusion of `burning_tx`, and the `block_height` at which `burning_tx` was mined. This function can be called vai the sui cli, see [sui](./sui.md).
- [get_coin_value_with_chunks](../move/bridge/sources/tcpbridge.move#L217): this function can be called to get the coin amount locked in the bridge (with chunks, see ) for the couple `((genesis_txid, genesis_index), (_, _))`.
- [update_chunks](../move/bridge/sources/tcpbridge.move#L304): this function can be called to update the chunks of `burning_tx` currently stored in the bridge (with chunks, see ) for the couple `((genesis_txid, genesis_index), (_, _))`. Default behaviour is to override chunks that already exist at index `chunk_index`.

## With Chunks

As the size of `burning_tx` is currently `~330KB`, we cannot:
- submit it as a single pure argument in a Sui Move public entry function
- submit is in a single transaction
- hash it in Move

This is because the size of `burning_tx` violates the Move limits, see [Building Against Limits](https://move-book.com/guides/building-against-limits.html).
While the third problem is something we are working on (i.e., we are working on reducing the size of `burning_tx`), the `_with_chunks` functions take care of the other two problems as of now.
In this way, as soon as the size of `burning_tx` goes below `256KB`, the bridge can be deployed.
When the size of `burning_tx` is below `16KB`, we will be able to use the functions without the chunks.
