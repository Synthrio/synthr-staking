import { ethers } from "hardhat";

import dotenv from "dotenv";
import { ADDRESS_ZERO } from "../test/utilities";
dotenv.config();

async function main() {
  let lpToken = process.env.LP_TOKEN_ADDRESS;
  let gaugeControllerAddress = process.env.GAUGE_CONTROLLER_ADDRESS;

  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const votingEscrow = await VotingEscrow.deploy(
    `${lpToken}`,
    `${gaugeControllerAddress}`,
    "voting escrow",
    "vt",
    "v.0.1"
  );

  await votingEscrow.deployed();
  console.log(`VotingEscrow deployed to ${votingEscrow.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
