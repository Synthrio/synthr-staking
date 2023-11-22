import { ethers, run } from "hardhat";

import dotenv from "dotenv";
dotenv.config();

async function main() {
  // let rewardToken = process.env.REWARD_TOKEN_ADDRESS;
  let tokenTracker = process.env.TOKEN_TRACKER;
  let nativeToken = process.env.NATIVE_TOKEN_ADDRESS;
  let liquidityPool = process.env.LIQUIDITY_POOL_ADDRESS;
  let mockToken = process.env.REE;

  const DexLpFarming = await ethers.getContractFactory("DerivedDexLpFarming");
  const dexLpFarming = await DexLpFarming.deploy(
    `${mockToken}`,
    `${tokenTracker}`,
    `${liquidityPool}`,
    `${nativeToken}`
  );

  await dexLpFarming.deployed();
  console.log(`DexLpFarming deployed to ${dexLpFarming.address}`);

  await run("verify:verify", {
    address: dexLpFarming.address,
    constructorArguments: [
      `${mockToken}`,
      `${tokenTracker}`,
      `${liquidityPool}`,
      `${nativeToken}`,
    ],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
