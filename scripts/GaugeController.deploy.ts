import { ethers } from "hardhat";

import dotenv from "dotenv";
dotenv.config();

async function main() {
  let admin = process.env.ADMIN_ADDRESS;

  const GaugeController = await ethers.getContractFactory("GaugeController");
  const gaugeController = await GaugeController.deploy(`${admin}`);

  await gaugeController.deployed();

  gaugeController;
  console.log(`GaugeController deployed to ${gaugeController.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
