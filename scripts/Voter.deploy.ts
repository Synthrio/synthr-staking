import { ethers, run } from "hardhat";

import dotenv from "dotenv";
import { ADDRESS_ZERO } from "../test/utilities";
dotenv.config();

async function main() {
  let votingEscrowAddress = process.env.VOTING_ESCROW_ADDRESS;

  const Voter = await ethers.getContractFactory("Voter");
  const voter = await Voter.deploy(ADDRESS_ZERO, `${votingEscrowAddress}`);

  await voter.deployed();
  console.log(`Voter deployed to ${voter.address}`);

  await run("verify:verify", {
    address: voter.address,
    constructorArguments: [ADDRESS_ZERO, `${votingEscrowAddress}`],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
