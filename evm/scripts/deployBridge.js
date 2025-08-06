async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const bridgeFactory = await ethers.getContractFactory("BitcoinBridge");
  const bridge = await bridgeFactory.deploy();

  await bridge.waitForDeployment();
  console.log("Bridge Contract deployed to:", bridge.target);
  
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});