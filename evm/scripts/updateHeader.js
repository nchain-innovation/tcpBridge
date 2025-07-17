const fs = require("fs");
const { ethers } = require("hardhat");

async function main() {
    // Load deployed contract address

    const contractAddresses = JSON.parse(fs.readFileSync("contract_addresses.json", "utf8"));
    const oracleAddress = contractAddresses.oracle_address;
    console.log("\nOrace address:", oracleAddress);

    // Load headers from file
    
    const headersHex = JSON.parse(fs.readFileSync("blockheaders.json", "utf8"));
 

    // Get signer and contract
    const [signer] = await ethers.getSigners();
    const headerContract = await ethers.getContractAt("BitcoinHeader", oracleAddress, signer);

    // Submit each header
    for (let i = 0; i < headersHex.length; i++) {
        const hex = headersHex[i];
        const headerBytes = `0x${hex}`;
        try {
            const tx = await headerContract.submitHeader(headerBytes);
            console.log(`\nSubmitted header ${i}: ${hex}`);
            await tx.wait();
        } catch (err) {
            console.error(`Error submitting header ${i}:`, err.message);
        }
    }
    console.log("All headers processed.");
}

main().catch((error) => {
    console.error("Unhandled error:", error);
    process.exitCode = 1;
});
