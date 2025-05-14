# Blockchain oracle

The `blockchain_oracle` Sui package implements a BSV blockchain oracle in Sui move.
The package contains the following files:
- [block_header](./sources/block_header.move): It contains the implementation of the `BlockHeader` object, which can be (de)serialised, and for which we can compute block hashes
- [blockchain_oracle](./sources//blockchain_oracle.move): It contains the implementation of the `HeaderChain` object, which is the sequence of block headers, block hashes, and chainwork. It can be updated by anyone once it's been instatiated (it's a shared object). At instantiation, the header chain be instatiated either from the genesis, or from a different starting point
- [spv](./sources/spv.move): It contains the implementation of `spv`, a public function that can be used to verify validity of a Merkle proof of inclusion for a transaction in a block whose header is contained in the header chain

## Public entry functions



To be implemented:
- [ ] Test reorgs
- [ ] Check median time when updating `HeaderChain` (is this needed?)
- [ ] Allow initialising the `HeaderChain` with more than a single block header
- [ ] Improve handling of the vulnerability of the SPV described [here](https://bitslog.com/2018/06/09/leaf-node-weakness-in-bitcoin-merkle-tree-design/). At the moment, it is handled by requiring tha the size of the transaction is different from `64` bytes, which is ok for our purposes as our transactions have at least two inputs. However, it might be better to have a general solution. For example, request the Merkle proof of inclusion of the coinbase transaction when the function `update_chain` is called, and then store the length of the Merkle proof.