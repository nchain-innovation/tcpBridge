const fs = require("fs");
const { ethers } = require("hardhat");

async function main() {
  try {
    // Load contract address
    const contractAddresses = JSON.parse(fs.readFileSync("contract_addresses.json", "utf8"));
    const bridgeAddress = contractAddresses.bridge_address;
    console.log("Bridge address:", bridgeAddress);

    // Load pegin info
    const peginInfo = JSON.parse(fs.readFileSync("pegin_info.json", "utf8"));
    const { genesis_txid, pegout_txid, pegin_amount } = peginInfo;

    if (isNaN(pegin_amount)) {
      throw new Error("Invalid pegin_amount in pegin_info.json");
    }

    const ethToSend = ethers.parseEther(String(pegin_amount));
    console.log("ETH to send:", ethToSend.toString());

    // Get contract instance
    const bridge = await ethers.getContractAt("BitcoinBridge", bridgeAddress);

    // Contract interactions
    const tx1 = await bridge.addUnbackedPair(genesis_txid, pegout_txid);
    await tx1.wait();
    console.log("Genesis tx:", genesis_txid);
    console.log("Pegout tx", pegout_txid);
    console.log("added as unbacked pair.");
    const tx2 = await bridge.fundPair(genesis_txid, { value: ethToSend });
    await tx2.wait();
    console.log("\nPair successfully funded.");

  } catch (error) {
    console.error("Error:", error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

main();
