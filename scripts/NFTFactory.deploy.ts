import { ethers, run } from "hardhat";

import dotenv from "dotenv";
dotenv.config();

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
async function main() {
    let owner: any;
    [owner] =  await ethers.getSigners();
    console.log(`Owner address check: ${owner.address}`);
    const NFTFactoryInstance = await ethers.getContractFactory("SynthrNFTFactory");
    const NFTFactory = await NFTFactoryInstance.deploy(owner.address);

    await NFTFactory.deployed();
    console.log(`NFT Factory contract deployed to ${NFTFactory.address}`);

    await sleep(30000); // Sleep for 30 seconds

    await run("verify:verify", {
        address: NFTFactory.address,
        constructorArguments: [owner.address],
    });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
