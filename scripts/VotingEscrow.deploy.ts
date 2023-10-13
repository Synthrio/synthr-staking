import { ethers, run } from "hardhat";

import dotenv from "dotenv";
import { ADDRESS_ZERO } from "../test/utilities";
dotenv.config();

async function main() {
  let gaugeControllerAddress = process.env.GAUGE_CONTROLLER_ADDRESS;

  const MockToken = await ethers.getContractFactory("MockToken");
  const mockToken = await MockToken.deploy();
  await mockToken.deployed();

  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const votingEscrow = await VotingEscrow.deploy(
    mockToken.address,
    `${gaugeControllerAddress}`,
    "Vote Escrowed SYNTH",
    "veSYNTH",
    "1"
  );

  await votingEscrow.deployed();
  console.log(`VotingEscrow deployed to ${votingEscrow.address}`);
  console.log(`MockToken deployed to ${mockToken.address}`);

  await run("verify:verify", {
    address: votingEscrow.address,
    constructorArguments: [
      mockToken.address,
      `${gaugeControllerAddress}`,
      "Vote Escrowed SYNTH",
      "veSYNTH",
      "1",
    ],
  });

  await run("verify:verify", {
    address: mockToken.address,
    constructorArguments: [],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
