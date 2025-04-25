## Blockchain oracle

- [ ] Test reorgs
- [ ] Check median time when updating `HeaderChain` (is this needed?)
- [ ] Allow initialising the `HeaderChain` with more than a single block header
- [ ] Improve handling of the vulnerability of the SPV described [here](https://bitslog.com/2018/06/09/leaf-node-weakness-in-bitcoin-merkle-tree-design/). At the moment, it is handled by requiring tha the size of the transaction is different from `64` bytes, which is ok for our purposes as our transactions have at least two inputs. However, it might be better to have a general solution. For example, request the Merkle proof of inclusion of the coinbase transaction when the function `update_chain` is called, and then store the length of the Merkle proof.
- [ ] Improve test coverage

## TCP Bridge

- [ ] Emit events when the functions are called? (Like: pegin successfull, pegin failed, etc.)
- [ ] Improve test coverage
- [ ] Get rid of `_with_chunks` functions when the burning transaction size goes below `16KB`.

## Sui cli

- [ ] Allow the user to choose which address to use. At the moment the cli uses by default the active address in the client.
- [ ] Implement commands to call other functions from the smart contracts.