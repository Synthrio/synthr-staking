import { ethers, run} from "hardhat";

import dotenv from "dotenv";
dotenv.config();

async function main() {
  let rewardToken = process.env.REWARD_TOKEN_ADDRESS;

  const DexLpFarming = await ethers.getContractFactory("DexLpFarming");
  const dexLpFarming = await DexLpFarming.deploy(`${rewardToken}`);

  await dexLpFarming.deployed();
  console.log(`DexLpFarming deployed to ${dexLpFarming.address}`);

  await run("verify:verify", {
    address: dexLpFarming.address,
    constructorArguments: [
      rewardToken
    ],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
