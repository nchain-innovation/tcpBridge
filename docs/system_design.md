# System Design

This document captures the system design for this project.


## System Overview

This diagram captures the key use cases supported by this project.

![Use Cases](diagrams/use-case.png)


The `Admin` performs on initial project setup:
1) `Upload Oracle Smart Contract` 
2) `Upload Bridge Smart Contract` , note this is dependent on 1) 
3) `Setup ZKEngine`



## Transfer Sui to BSV

This diagram shows the interactions required to Transfer Sui to BSV.

![Transfer Sui to BSV](diagrams/sequence-sui-to-bsv.png)

Note that the `Check Sui` stage, checks
* Time of `Peg_Out_UTXO`, is within 10 mins
* Format of ...


## Transfer Wrapped Sui

This diagram shows the interactions required to Transfer Wrapped Sui on BSV between Users.

![Transfer Wrapped Sui](diagrams/sequence-wrapped-sui-transfer.png)

Note that the `Check Sui` stage is not currently implemented.


## Transfer BSV to Sui (Unlocking Sui)

This diagram shows the interactions required to Unlock Sui.

![Transfer BSV to Sui](diagrams/sequence-sui-to-bsv.png)


This currently takes a BSV tx of 330K, however Sui currently is limited to objects of 256K.

