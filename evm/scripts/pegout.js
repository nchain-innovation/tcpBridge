const fs = require("fs");
const { ethers } = require("hardhat");
const crypto = require('crypto');

// --- Shared Setup (only runs once) ---

// Replace with your deployed contract address
const bridgeAddress = JSON.parse(fs.readFileSync("contract_addresses.json", "utf8")).bridge_address;

// Mock input values (replace with your real data)
const pegout_data = JSON.parse(fs.readFileSync("pegout_data.json", "utf8"));

// Extract fields
const serializedBitcoinTx = "0x" + pegout_data.serializedBitcoinTx;
const merkleProof = pegout_data.merkleProof.map(b => '0x' + b);
const bitcoinBlockHash = reverseHex('0x' + pegout_data.bitcoinBlockHash);
const positions = pegout_data.positions;
const mintTxId = "0x" + pegout_data.mintTxId;
const ethAddress = "0x" + pegout_data.ethAddress;

// Log the extracted fields
console.log("\nSerialized Burn Transaction:", serializedBitcoinTx);
console.log("\nMerkle Proof:", merkleProof);
console.log("\nPositions:", positions);
console.log("\nBitcoin Block Hash:", bitcoinBlockHash);
console.log("\nGenesis Transaction ID:", mintTxId);
console.log("\nReceipient ETH address:", ethAddress);

// Helper to reverse hex
function reverseHex(hex) {
    hex = hex.replace(/^0x/, '');
    return '0x' + hex.match(/../g).reverse().join('');
}

function doubleSha256(data) {
    return crypto.createHash('sha256').update(
        crypto.createHash('sha256').update(data).digest()
    ).digest();
}

async function main() {
    const bridge = await ethers.getContractAt("BitcoinBridge", bridgeAddress);

    console.log("\nburn txid:", doubleSha256(serializedBitcoinTx).toString("hex"));
    const balanceBefore = await ethers.provider.getBalance(ethAddress);
    console.log("\nAccount balance:", ethers.formatEther(balanceBefore)); 
    const tx = await bridge.pegout(
        serializedBitcoinTx,
        merkleProof,
        bitcoinBlockHash,
        positions,
        mintTxId
    );
    await tx.wait();
    console.log("\npegout completed.");
    const balanceAfter = await ethers.provider.getBalance(ethAddress);
    console.log("\nAccount balance:", ethers.formatEther(balanceAfter)); 
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});