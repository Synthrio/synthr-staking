import { ethers, run } from "hardhat";

import dotenv from "dotenv";
import { ADDRESS_ZERO } from "../test/utilities";
dotenv.config();

async function main() {
  let gaugeControllerAddress = process.env.GAUGE_CONTROLLER_ADDRESS;
  let rewardToken = process.env.REWARD_TOKEN_ARBITRUM_ADDRESS;

  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const votingEscrow = await VotingEscrow.deploy(
    `${rewardToken}`,
    `${gaugeControllerAddress}`,
    "Vote Escrowed SYNTH",
    "veSYNTH",
    "1"
  );

  await votingEscrow.deployed();
  console.log(`VotingEscrow deployed to ${votingEscrow.address}`);

  await run("verify:verify", {
    address: votingEscrow.address,
    constructorArguments: [
      `${rewardToken}`,
      `${gaugeControllerAddress}`,
      "Vote Escrowed SYNTH",
      "veSYNTH",
      "1",
    ],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
