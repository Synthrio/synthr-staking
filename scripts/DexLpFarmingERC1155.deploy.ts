import { ethers, run} from "hardhat";

import dotenv from "dotenv";
dotenv.config();

async function main() {

    let lbPair = process.env.LBPAIR_FUJI_ADDRESS;

    const MockToken = await ethers.getContractFactory("MockToken");
    const mockToken = await MockToken.deploy();
    await mockToken.deployed();

  const DexLpFarming = await ethers.getContractFactory("DerivedDexLpFarmingERC1155");
  const dexLpFarming = await DexLpFarming.deploy(mockToken.address,`${lbPair}`);

  await dexLpFarming.deployed();
  console.log(`DexLpFarmingERC1155 deployed to ${dexLpFarming.address}`);
  console.log(`MockToken deployed to ${mockToken.address}`);

  await run("verify:verify", {
    address: mockToken.address,
    constructorArguments: [
    ],
  });

  await run("verify:verify", {
    address: dexLpFarming.address,
    constructorArguments: [
    mockToken.address,
      `${lbPair}`
    ],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
