import { ethers, run } from "hardhat";

import dotenv from "dotenv";
dotenv.config();

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
async function main() {

    const NFTFactoryInstance = await ethers.getContractFactory("SynthrNFTFactory");
    const NFTFactory = await NFTFactoryInstance.deploy();

    await NFTFactory.deployed();
    console.log(`NFT Factory contract deployed to ${NFTFactory.address}`);

    await sleep(60000); // Sleep for 1 minute

    await run("verify:verify", {
        address: NFTFactory.address,
        constructorArguments: [],
    });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
