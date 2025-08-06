async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const oracleFactory = await ethers.getContractFactory("BitcoinHeader");
  const oracle = await oracleFactory.deploy();

  await oracle.waitForDeployment();
  console.log("Oracle Contract deployed to:", oracle.target);
 
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});