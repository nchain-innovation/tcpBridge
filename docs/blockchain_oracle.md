# Blockchain oracle

The `blockchain_oracle` Sui package implements a BSV blockchain oracle in Sui move.
The package contains the following files:
- [block_header](./sources/block_header.move): It contains the implementation of the `BlockHeader` object, which can be (de)serialised, and for which we can compute block hashes
- [blockchain_oracle](./sources//blockchain_oracle.move): It contains the implementation of the `HeaderChain` object, which is the sequence of block headers, block hashes, and chainworks. It can be updated by anyone once it's been instatiated (it's a shared object). At instantiation, the header chain be instatiated either from the genesis, or from a different starting point
- [spv](./sources/spv.move): It contains the implementation of `spv`, a public function that can be used to verify validity of a Merkle proof of inclusion for a transaction in a block whose header is contained in the header chain

## Publishing the package

Before publishing the package, one must choose from which block header the oracle should be instantiated, which we will call `GENESIS_BLOCK`.
After publishing, only transactions mined in blocks after or in `GENESIS_BLOCK` can be validated via SPV by the blockchain oracle.

The blockchain header, its hash, its block height, and its chainwork mus the added in [blockchain_oracle.move](../move/oracle/sources/blockchain_oracle.move#L12).
The blockchain header and its hash have to be added as a list of bytes.

> [!NOTE]
> To obtain the relavant data to be added to [blockchain_oracle.move](../move/oracle/sources/blockchain_oracle.move#L12), you can use the script [fetch_oracle_data](../cli/bsv/fetch_oracle_data.py). The command is as follows: `python3 -m fetch_oracle_data --blockchash <BLOCKHASH> --network <NETWORK>`.

After you have inserted the relevant data in [blockchain_oracle.move](../move/oracle/sources/blockchain_oracle.move#L12), you can publish the package with

```
sui client publish
```

## Public entry functions

The package has two public entry functions:

- [update_chain](../move/oracle/sources/blockchain_oracle.move#L105): this function can be used to update the chain. It takes two arguments: the header chain to be updated, and the byte serialisation of the block to be added. If the block is valid, then the header chain will be updated. Otherwise, nothing happens. This function can be called via the sui cli [sui](../cli/sui/), see [sui_docs](../docs/sui.md). 
- [reorg_chain](../move/oracle/sources/blockchain_oracle.move#L123): this function can be used to reorganise the header chain after a fork. It takes three arguments: the header chain to be updated, the fork index, and the serilisations of the blocks to be added, which are passed as a list of byte serialisations. The fork index is the index at which the fork happended (e.g., if the chain forked at block `N`, then you would submit `N` as the fork index argument).

## Updating the oracle

To update the oracle you can use the script [oracle_service.py](../cli/bsv/oracle_service.py).
The command syntax is:

```
python3 -m oracle_service --block_height <BLOCK_HEIGHT> --network <NETWORK>
```

where `<BLOCK_HEIGHT>` is the block height from which you want to update the oracle from.
The script will add all the blocks from `<BLOCK_HEIGHT>` to the current blockchain tip to the oracle.