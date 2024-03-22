import { ethers, run } from "hardhat";

import dotenv from "dotenv";
dotenv.config();

async function main() {
    let rewardToken = process.env.REWARD_TOKEN;
    let NFTToken = process.env.NFT_TOKEN;

    const NFTStakingInstance = await ethers.getContractFactory("NftStaking");
    const NFTStaking = await NFTStakingInstance.deploy(`${rewardToken}`, `${NFTToken}`);

    await NFTStaking.deployed();
    console.log(`NFT Staking contract deployed to ${NFTStaking.address}`);

    await run("verify:verify", {
        address: NFTStaking.address,
        constructorArguments: [`${rewardToken}`, `${NFTToken}`],
    });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
