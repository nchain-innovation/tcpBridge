const fs = require("fs");
const { ethers } = require("hardhat");

async function main() {
    try {
        console.log("\nGenerate ETH addresses...");
        const accounts = await ethers.getSigners();
        const addresses = accounts.map(account => account.address);

        fs.writeFileSync('addresses.txt', addresses.join('\n'), 'utf-8');

        console.log("ETH addresses written to addresses.txt");
    } catch (error) {
        console.error("Error generating addresses:", error);
        process.exit(1);
    }
}

main();
