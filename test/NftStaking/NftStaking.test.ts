import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { Address } from '../../typechain-types/@openzeppelin/contracts/utils/Address';


let owner: any, addr1: any, addr2: any, user0: any, user1: any, user2: any, user3: any;
let nftStaking: any,
    rewardToken: any;

let syCHAD: any, syBULL: any, syHODL: any, syDIAMOND: any, syMAXI: any;
let pools: any;
let totalLockAmount: any;
async function setUp() {
    // Contracts are deployed using the first signer/account by default
    [owner, addr1, addr2, user0, user1, user2, user3] = await ethers.getSigners();
    const RewardToken = await ethers.getContractFactory("MockToken");
    rewardToken = await RewardToken.deploy()

    const NFTStaking = await ethers.getContractFactory("NftStaking");
    nftStaking = await NFTStaking.deploy(owner.address, rewardToken.address);

    const SynthrNFT = await ethers.getContractFactory("SynthrNFT");
    syCHAD = await SynthrNFT.deploy("syCHAD", "syCHAD", owner.address);
    syBULL = await SynthrNFT.deploy("syBULL", "syBULL", owner.address);
    syHODL = await SynthrNFT.deploy("syHODL", "syHODL", owner.address);
    syDIAMOND = await SynthrNFT.deploy("syDIAMOND", "syDIAMOND", owner.address);
    syMAXI = await SynthrNFT.deploy("syMAXI", "syMAXI", owner.address);

    pools = [syCHAD.address,
    syBULL.address,
    syHODL.address,
    syDIAMOND.address,
    syMAXI.address]

    await rewardToken.mint(owner.address, parseUnits("1000000000", 18));

}

async function mintNFTsToLpProviders() {
    const lpAmount = {
        user0: ethers.utils.parseEther("100"), // 100 * 10^18
        user1: ethers.utils.parseEther("2000"),
        user2: ethers.utils.parseEther("30000"),
        user3: ethers.utils.parseEther("400000"),
    }
    await syCHAD.connect(owner).safeMint(user0.address, lpAmount.user0);
    await syBULL.connect(owner).safeMint(user1.address, lpAmount.user1);
    await syHODL.connect(owner).safeMint(user2.address, lpAmount.user2);
    await syDIAMOND.connect(owner).safeMint(user3.address, lpAmount.user3);
    return ethers.utils.parseEther("432100"); //sum of above lpAmount.user
}


async function addPoolFunc() {
    let tx = await nftStaking.addPool(pools);
    await rewardToken.connect(owner).approve(nftStaking.address, ethers.utils.parseEther("100000"));
    let tx1 = await nftStaking.updateEpoch(owner.address, ethers.utils.parseEther("100000"), pools, [1000, 1000, 1000, 1000, 1000]);
    return [tx, tx1];
}

async function approveNFT() {
    await syCHAD.connect(user0).approve(nftStaking.address, 1);
    await syBULL.connect(user1).approve(nftStaking.address, 1);
    await syHODL.connect(user2).approve(nftStaking.address, 1);
    await syDIAMOND.connect(user3).approve(nftStaking.address, 1);
    expect(await syCHAD.getApproved(1)).to.equal(nftStaking.address);
    expect(await syBULL.getApproved(1)).to.equal(nftStaking.address);
    expect(await syHODL.getApproved(1)).to.equal(nftStaking.address);
    expect(await syDIAMOND.getApproved(1)).to.equal(nftStaking.address);
}



async function depositNfts() {
    let tx1 = await nftStaking.connect(user0).deposit(syCHAD.address, 1);
    let tx2 = await nftStaking.connect(user1).deposit(syBULL.address, 1);
    let tx3 = await nftStaking.connect(user2).deposit(syHODL.address, 1);
    let tx4 = await nftStaking.connect(user3).deposit(syDIAMOND.address, 1);
    return [tx1, tx2, tx3, tx4];

}

function calAccRewardPerShare(_accRewardPerShare: BigNumber, _amount: BigNumber): BigNumber {
    const ACC_REWARD_PRECISION: BigNumber = ethers.utils.parseEther("1");
    return _amount.mul(_accRewardPerShare).div(ACC_REWARD_PRECISION);
}

describe("NFTStaking", function () {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.

    beforeEach(async () => {
        await setUp();
        totalLockAmount = await mintNFTsToLpProviders();
        await nftStaking.setTotalLockAmount(totalLockAmount);
        expect(await nftStaking.totalLockAmount()).to.equal(totalLockAmount);
    });

    describe("Funtions", function () {
        it("Should add pool in nftStaking", async function () {
            let txns = await addPoolFunc();
            expect(txns[0])
                .to.emit(nftStaking, "LogPoolAddition")
                .withArgs(owner.address, pools);
            expect(txns[1])
                .to.emit(nftStaking, "EpochUpdated")
                .withArgs(owner.address, pools, [1000, 1000, 1000, 1000, 1000]);
            let poolInfoSyCHAD = await nftStaking.poolInfo(syCHAD.address)
            let poolInfoSyBULL = await nftStaking.poolInfo(syBULL.address)
            let poolInfoSyHODL = await nftStaking.poolInfo(syHODL.address)
            let poolInfoSyDIAMOND = await nftStaking.poolInfo(syDIAMOND.address)
            let poolInfoSyMAXI = await nftStaking.poolInfo(syMAXI.address)
            expect(poolInfoSyCHAD.exist).to.equal(true);
            expect(poolInfoSyBULL.exist).to.equal(true);
            expect(poolInfoSyHODL.exist).to.equal(true);
            expect(poolInfoSyDIAMOND.exist).to.equal(true);
            expect(poolInfoSyMAXI.exist).to.equal(true);
        });


        it("Should have pending reward zero if user has not deposited in pool", async function () {
            await addPoolFunc();
            const currentTime = await time.latest();
            await time.increaseTo(currentTime + 1000);
            expect(
                await nftStaking.pendingReward(pools[0], user0.address)
            ).to.equal(0);
            expect(
                await nftStaking.pendingReward(pools[1], user1.address)
            ).to.equal(0);
            expect(
                await nftStaking.pendingReward(pools[2], user2.address)
            ).to.equal(0);
            expect(
                await nftStaking.pendingReward(pools[3], user3.address)
            ).to.equal(0);
        });

        it("Should deposit user's nft", async function () {
            await addPoolFunc();
            await approveNFT();
            let txns = await depositNfts();
            await expect(txns[0])
                .to.emit(nftStaking, "Deposit")
                .withArgs(syCHAD.address, user0.address, 1);
            await expect(txns[1])
                .to.emit(nftStaking, "Deposit")
                .withArgs(syBULL.address, user1.address, 1);
            await expect(txns[2])
                .to.emit(nftStaking, "Deposit")
                .withArgs(syHODL.address, user2.address, 1);
            await expect(txns[3])
                .to.emit(nftStaking, "Deposit")
                .withArgs(syDIAMOND.address, user3.address, 1);
        })
        it("Should update user reward debt after deposits", async function () {
            await addPoolFunc();
            await approveNFT();
            mine(10000);
            await depositNfts();
            let poolInfoSyCHAD = await nftStaking.poolInfo(syCHAD.address)
            let poolInfoSyBULL = await nftStaking.poolInfo(syBULL.address)
            let poolInfoSyHODL = await nftStaking.poolInfo(syHODL.address)
            let poolInfoSyDIAMOND = await nftStaking.poolInfo(syDIAMOND.address)
            let poolInfoSyMAXI = await nftStaking.poolInfo(syMAXI.address)

            const lockAmount = {
                user0: ethers.utils.parseEther("100"), // 100 * 10^18
                user1: ethers.utils.parseEther("2000"),
                user2: ethers.utils.parseEther("30000"),
                user3: ethers.utils.parseEther("400000"),
            }

            let amt0 = calAccRewardPerShare(poolInfoSyCHAD.accRewardPerShare, lockAmount.user0);
            let amt1 = calAccRewardPerShare(poolInfoSyBULL.accRewardPerShare, lockAmount.user1);
            let amt2 = calAccRewardPerShare(poolInfoSyHODL.accRewardPerShare, lockAmount.user2);
            let amt3 = calAccRewardPerShare(poolInfoSyDIAMOND.accRewardPerShare, lockAmount.user3);

            let user0Info = await nftStaking.userInfo(pools[0], user0.address)
            let user1Info = await nftStaking.userInfo(pools[1], user1.address)
            let user2Info = await nftStaking.userInfo(pools[2], user2.address)
            let user3Info = await nftStaking.userInfo(pools[3], user3.address)

            expect(user0Info.amount).to.equal(lockAmount.user0);
            expect(user1Info.amount).to.equal(lockAmount.user1);
            expect(user2Info.amount).to.equal(lockAmount.user2);
            expect(user3Info.amount).to.equal(lockAmount.user3);

            expect(user0Info.rewardDebt).to.equal(amt0);
            expect(user1Info.rewardDebt).to.equal(amt1);
            expect(user2Info.rewardDebt).to.equal(amt2);
            expect(user3Info.rewardDebt).to.equal(amt3);



        })

        it("Should have reward amount after user triggered claim", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000);
            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            let expectedReward = await nftStaking.pendingRewardAtBlock(pools[0], user0.address, blockNum);
            let tx = await nftStaking.connect(user0).claim(pools[0], user0.address);
            await expect(tx)
                .to.emit(nftStaking, "Claimed")
                .withArgs(user0.address, pools[0], expectedReward);
            let actualReward = await rewardToken.balanceOf(user0.address);
            expect(expectedReward).to.equal(actualReward);


        });

        it("Should withdraw nft to user", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000);
            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            let tx = await nftStaking.connect(user0).withdraw(pools[0], 1);
            await expect(tx)
                .to.emit(nftStaking, "Withdraw")
                .withArgs(pools[0], user0.address, 1);
            expect(await syCHAD.ownerOf(1)).to.equal(user0.address);
            expect((await nftStaking.userInfo(syCHAD.address, user0.address)).amount).to.equal(0);
        });

        it("Should withdraw nft to user and claim reward", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000);
            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            let expectedReward = await nftStaking.pendingRewardAtBlock(pools[0], user0.address, blockNum);
            let tx = await nftStaking.connect(user0).withdrawAndClaim(pools[0], 1, user0.address);
            await expect(tx)
                .to.emit(nftStaking, "WithdrawAndClaim")
                .withArgs(pools[0], user0.address, expectedReward);
            expect(await syCHAD.ownerOf(1)).to.equal(user0.address);
            expect((await nftStaking.userInfo(syCHAD.address, user0.address)).amount).to.equal(0);
            let actualReward = await rewardToken.balanceOf(user0.address);
            expect(expectedReward).to.equal(actualReward);
        });

    });
});
