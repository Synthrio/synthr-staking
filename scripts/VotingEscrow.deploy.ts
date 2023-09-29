import { ethers , run} from "hardhat"

import dotenv from "dotenv";
import { ADDRESS_ZERO } from "../test/utilities";
dotenv.config();

async function main() {
  let gaugeControllerAddress = process.env.GAUGE_CONTROLLER_ADDRESS;

  const Token = await ethers.getContractFactory("MockToken");
  const token = await Token.deploy();

  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const votingEscrow = await VotingEscrow.deploy(
    token.address,
    `${gaugeControllerAddress}`,
    "Vote Escrowed SYNTH",
    "veSYNTH",
    "1"
  );

  await votingEscrow.deployed();
  console.log(`VotingEscrow deployed to ${votingEscrow.address}`);
  console.log(`Token deployed to ${token.address}`);

  await run("verify:verify", {
    address: votingEscrow.address,
    constructorArguments: [
      token.address,
      `${gaugeControllerAddress}`,
      "Vote Escrowed SYNTH",
      "veSYNTH",
      "1"
    ],
  });

  await run("verify:verify", {
    address: token.address,
    constructorArguments: [
    ],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
