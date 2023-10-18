import { ethers, run } from "hardhat";

import dotenv from "dotenv";
dotenv.config();

async function main() {
  let admin = process.env.ADMIN_ADDRESS;
  const MockToken = await ethers.getContractFactory("MockToken");
  const mockToken = await MockToken.deploy();
  await mockToken.deployed();

  await run("verify:verify", {
    address: mockToken.address,
    constructorArguments: [],
  });

  const GaugeController = await ethers.getContractFactory("GaugeController");
  const gaugeController = await GaugeController.deploy(`${admin}`);

  await gaugeController.deployed();

  console.log(`GaugeController deployed to ${gaugeController.address}`);

  await run("verify:verify", {
    address: gaugeController.address,
    constructorArguments: [admin],
  });

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
