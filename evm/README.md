# Sample Hardhat Project

This example brigde allows ETH to be transacted on Bitcon SV (BSV) and withdrawn from a smart contract by providing a Merkle proof of a buring transaction on BSV. We use hardhat for a local Ethereum network and wild-bit lab for a local Bitcoin regtest. There are two smart contracts we use on Ethereum. One is a decentralised Bitcoin header oracle contract, and the other is the bridge contract. 

evm_demo.py is a python script that semi-automates a demo of the bridge. You can follow the intrustion below to run "setup", "pegin", "transfer", "burn", and "pegout" to create the demo yourself. 


Run the following under evm folder to install hardhat locally. 
```shell
npm install --save-dev hardhat
```

You can follow the instructions [here] (https://hardhat.org/hardhat-runner/docs/guides/project-setup) to create a hardhat project.
```shell
npx hardhat init
```

In a terminal window, you can run the following to spin up a local Ethereum network. 
```shell
npx hardhat node
```

In another termianl window, under the directory "wild-bit-lab/", you can run the following to spin up a regtest for Bitcoin.
```shell
docker compose --file three-node.yml up
```

Navigate to cli/, and run the following command to create wallets and publish the two contracts. 
```shell
python -m evm_demo setup 
```

You should be able to see contract addresses as part of the outputs. You can then pegin by running:
```shell
python -m evm_demo pegin --user alice --pegin-amount 10 --network regtest    
```

This will send 10 ETH to the bridge smart contract to active 10 ETH token on BSV. You can then transfer the token on BSV in normal Bitcoin transaction. 
```shell
python -m evm_demo transfer --sender alice --reeiver bob --token-index 0 --network regtest    
```

If Bob wants to pegout, he needs to burn the token first on BSV. 
```shell
python -m evm_demo burn --user bob --token-index 0 --network regtest  
```

The command above also prepares the data needed to pegout on Ethereum. To pegout, Bob runs the following command. 
```shell
python -m evm_demo pegout
```
This command will update the oracle contract first before calling the bridge contract. An account balance is displayed to show the difference before pegout and after. 

Please do reach out if you have any question on the demo. 