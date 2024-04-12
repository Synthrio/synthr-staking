import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { mine } from "@nomicfoundation/hardhat-network-helpers";


let owner: any, addr1: any, addr2: any, Alice: any, Bob: any, Joy: any, Roy: any, Matt: any;
let nftStaking: any,
    rewardToken: any;

let syCHAD: any, syBULL: any, syHODL: any, syDIAMOND: any, syMAXI: any;
let pools: any;
let totalLockAmount: any;
let synthrStaking: any;
async function setUp() {
    // Contracts are deployed using the first signer/account by default
    [owner, addr1, addr2, Alice, Bob, Joy, Roy, Matt] = await ethers.getSigners();
    const RewardToken = await ethers.getContractFactory("MockToken");
    rewardToken = await RewardToken.deploy()

    
    let lockValue: any = [{
        maxPoolSize: parseUnits("1000000", 18),
        penalty: 40,
        coolDownPeriod: 60*60*24,
        totalStaked: 0,
        exist: true,
    }, {
        maxPoolSize: parseUnits("1000000", 18),
        penalty: 35,
        coolDownPeriod: 60*60*24,
        totalStaked: 0,
        exist: true,
    }, {maxPoolSize: parseUnits("1000000", 18),
        penalty: 30,
        coolDownPeriod: 60*60*24,
        totalStaked: 0,
        exist: true,
    }, {maxPoolSize: parseUnits("1000000", 18),
        penalty: 25,
        coolDownPeriod: 60*60*24,
        totalStaked: 0,
        exist: true,
    }];

    let lockAmount = [60*60*24*30*6, 60*60*24*30*9, 60*60*24*30*12, 60*60*24*30*18];

    const SynthrStaking = await ethers.getContractFactory("SynthrStaking");
    
    synthrStaking = await SynthrStaking.deploy(owner.address, rewardToken.address, lockAmount, lockValue);

    const NFTStaking = await ethers.getContractFactory("NftStaking");
    nftStaking = await NFTStaking.deploy(owner.address, rewardToken.address, synthrStaking.address);

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
        Alice: parseUnits("1000", 18), // 100 * 10^18
        Bob: parseUnits("1000", 18),
        Joy: parseUnits("1000", 18),
        Roy: parseUnits("1000", 18),
    }
    let times = await time.latestBlock();
    const tokenURI = "https://qn-shared.quicknode-ipfs.com/ipfs/QmeVHZzKGEDbEbG5MVz4hUucNf4qZTRfW18AgdJNTrv22m";

    await syCHAD.connect(owner).safeMint(Alice.address, tokenURI);
    await syCHAD.connect(owner).safeMint(Roy.address, tokenURI);
    await syBULL.connect(owner).safeMint(Bob.address, tokenURI);
    await syHODL.connect(owner).safeMint(Joy.address, tokenURI);
    await syDIAMOND.connect(owner).safeMint(Roy.address, tokenURI);
    return lpAmount.Alice.add(lpAmount.Bob.add(lpAmount.Joy.add(lpAmount.Roy.mul(2))));//sum of above lpAmount.user
}


async function addPoolFunc() {
    let tx = await nftStaking.addPool(pools);
    await rewardToken.connect(owner).approve(nftStaking.address, ethers.utils.parseEther("100000"));
    let tx1 = await nftStaking.updateEpoch(owner.address, ethers.utils.parseEther("100000"), pools, [1000, 1000, 1000, 1000, 1000]);
    return [tx, tx1];
}

async function approveNFT() {
    await syCHAD.connect(Alice).approve(nftStaking.address, 1);
    await syBULL.connect(Bob).approve(nftStaking.address, 1);
    await syHODL.connect(Joy).approve(nftStaking.address, 1);
    await syDIAMOND.connect(Roy).approve(nftStaking.address, 1);
    expect(await syCHAD.getApproved(1)).to.equal(nftStaking.address);
    expect(await syBULL.getApproved(1)).to.equal(nftStaking.address);
    expect(await syHODL.getApproved(1)).to.equal(nftStaking.address);
    expect(await syDIAMOND.getApproved(1)).to.equal(nftStaking.address);
}

async function depositInSynthStaking() {

    await rewardToken.mint(Alice.address, parseUnits("1000", 18));
    await rewardToken.mint(Bob.address, parseUnits("1000", 18));
    await rewardToken.mint(Joy.address, parseUnits("1000", 18));
    await rewardToken.mint(Roy.address, parseUnits("1000", 18));

    await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("1000", 18));
    await rewardToken.connect(Bob).approve(synthrStaking.address, parseUnits("1000", 18));
    await rewardToken.connect(Joy).approve(synthrStaking.address, parseUnits("1000", 18));
    await rewardToken.connect(Roy).approve(synthrStaking.address, parseUnits("1000", 18));
    

    let tx1 = await synthrStaking.connect(Alice).deposit(parseUnits("1000", 18), 60*60*24*30*6);
    let tx2 = await synthrStaking.connect(Bob).deposit(parseUnits("1000", 18), 60*60*24*30*9);
    let tx3 = await synthrStaking.connect(Joy).deposit(parseUnits("1000", 18), 60*60*24*30*12);
    let tx4 = await synthrStaking.connect(Roy).deposit(parseUnits("1000", 18), 60*60*24*30*18);

    return [tx1, tx2, tx3, tx4];
}

async function depositNfts() {
    await depositInSynthStaking();

    let tx1 = await nftStaking.connect(Alice).deposit(syCHAD.address, 1);
    let tx2 = await nftStaking.connect(Bob).deposit(syBULL.address, 1);
    let tx3 = await nftStaking.connect(Joy).deposit(syHODL.address, 1);
    let tx4 = await nftStaking.connect(Roy).deposit(syDIAMOND.address, 1);
    return [tx1, tx2, tx3, tx4];

}

function calAccRewardPerShare(_accRewardPerShare: BigNumber, _amount: BigNumber): BigNumber {
    const ACC_REWARD_PRECISION: BigNumber = ethers.utils.parseEther("1");
    return _amount.mul(_accRewardPerShare).div(ACC_REWARD_PRECISION);
}

function calAccPerShare(rewardAmount: BigNumber, lpSupply: BigNumber): BigNumber {
    const ACC_REWARD_PRECISION: BigNumber = ethers.utils.parseEther("1");
    return rewardAmount.mul(ACC_REWARD_PRECISION).div(lpSupply);
}

describe.only("NFTStaking", function () {
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
                await nftStaking.pendingReward(pools[0], Alice.address)
            ).to.equal(0);
            expect(
                await nftStaking.pendingReward(pools[1], Bob.address)
            ).to.equal(0);
            expect(
                await nftStaking.pendingReward(pools[2], Joy.address)
            ).to.equal(0);
            expect(
                await nftStaking.pendingReward(pools[3], Roy.address)
            ).to.equal(0);
        });

        it("Should deposit user's nft", async function () {
            await addPoolFunc();
            await approveNFT();
            let txns = await depositNfts();
            await expect(txns[0])
                .to.emit(nftStaking, "Deposit")
                .withArgs(syCHAD.address, Alice.address, 1);
            await expect(txns[1])
                .to.emit(nftStaking, "Deposit")
                .withArgs(syBULL.address, Bob.address, 1);
            await expect(txns[2])
                .to.emit(nftStaking, "Deposit")
                .withArgs(syHODL.address, Joy.address, 1);
            await expect(txns[3])
                .to.emit(nftStaking, "Deposit")
                .withArgs(syDIAMOND.address, Roy.address, 1);
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
                Alice: ethers.utils.parseEther("1000"), // 100 * 10^18
                Bob: ethers.utils.parseEther("1000"),
                Joy: ethers.utils.parseEther("1000"),
                Roy: ethers.utils.parseEther("1000"),
            }

            let amt0 = calAccRewardPerShare(poolInfoSyCHAD.accRewardPerShare, lockAmount.Alice);
            let amt1 = calAccRewardPerShare(poolInfoSyBULL.accRewardPerShare, lockAmount.Bob);
            let amt2 = calAccRewardPerShare(poolInfoSyHODL.accRewardPerShare, lockAmount.Joy);
            let amt3 = calAccRewardPerShare(poolInfoSyDIAMOND.accRewardPerShare, lockAmount.Roy);

            let AliceInfo = await nftStaking.userInfo(pools[0], Alice.address)
            let BobInfo = await nftStaking.userInfo(pools[1], Bob.address)
            let JoyInfo = await nftStaking.userInfo(pools[2], Joy.address)
            let RoyInfo = await nftStaking.userInfo(pools[3], Roy.address)

            expect(AliceInfo.amount).to.equal(lockAmount.Alice);
            expect(BobInfo.amount).to.equal(lockAmount.Bob);
            expect(JoyInfo.amount).to.equal(lockAmount.Joy);
            expect(RoyInfo.amount).to.equal(lockAmount.Roy);

            expect(AliceInfo.rewardDebt).to.equal(amt0);
            expect(BobInfo.rewardDebt).to.equal(amt1);
            expect(JoyInfo.rewardDebt).to.equal(amt2);
            expect(RoyInfo.rewardDebt).to.equal(amt3);



        })

        it("Should have reward amount after user triggered claim", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000);
            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            let expectedReward = await nftStaking.pendingRewardAtBlock(pools[0], Alice.address, blockNum);
            let tx = await nftStaking.connect(Alice).claim(pools[0], Alice.address);
            await expect(tx)
                .to.emit(nftStaking, "Claimed")
                .withArgs(Alice.address, pools[0], expectedReward);
            let actualReward = await rewardToken.balanceOf(Alice.address);
            expect(expectedReward).to.equal(actualReward);


        });

        it("Should withdraw nft to user", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000);
            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            let tx = await nftStaking.connect(Alice).withdraw(pools[0]);
            await expect(tx)
                .to.emit(nftStaking, "Withdraw")
                .withArgs(pools[0], Alice.address, 1);
            expect(await syCHAD.ownerOf(1)).to.equal(Alice.address);
            expect((await nftStaking.userInfo(syCHAD.address, Alice.address)).amount).to.equal(0);
        });

        it("Should revert if claim is triggered without depositing nft", async function () {
            await addPoolFunc();
            await approveNFT();
            await mine(1000);
            const blockNum = await ethers.provider.getBlockNumber();
            let expectedReward = await nftStaking.pendingRewardAtBlock(pools[0], Matt.address, blockNum);
            let tx = await nftStaking.connect(Matt).claim(pools[0], Matt.address);
            await expect(tx)
                .to.emit(nftStaking, "Claimed")
                .withArgs(Matt.address, pools[0], expectedReward);
            let actualReward = await rewardToken.balanceOf(Alice.address);
            expect(expectedReward).to.equal(actualReward);
        });

        it("Should claim reward after withdraw is triggged", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000);
            let tx = await nftStaking.connect(Alice).withdraw(pools[0]);
            await expect(tx)
                .to.emit(nftStaking, "Withdraw")
                .withArgs(pools[0], Alice.address, 1);
            expect(await syCHAD.ownerOf(1)).to.equal(Alice.address);
            expect((await nftStaking.userInfo(syCHAD.address, Alice.address)).amount).to.equal(0);
            await mine(10); // 10 blocks are mined after the withdraw is triggged
            const blockNum = await ethers.provider.getBlockNumber();
            let pendingRewardBeforeClaim = await nftStaking.pendingRewardAtBlock(pools[0], Alice.address, blockNum);
            let claimTx0 = await nftStaking.connect(Alice).claim(pools[0], Alice.address);
            let pendingRewardAfterClaim = await nftStaking.pendingRewardAtBlock(pools[0], Alice.address, blockNum);
            expect(pendingRewardAfterClaim).to.equal(BigNumber.from(0));
        });


        it("Should update rewardDebt & AccumulatedUnoPerShare as calculated", async function () {
            await addPoolFunc();
            await approveNFT();
            await rewardToken.mint(Alice.address, parseUnits("1000", 18));
            await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("1000", 18));
            await synthrStaking.connect(Alice).deposit(parseUnits("1000", 18), 60*60*24*30*6);
            let tx1 = await nftStaking.connect(Alice).deposit(syCHAD.address, 1);

            let accumulatedPerShareBeforeWithdraw = (await nftStaking.poolInfo(pools[0])).accRewardPerShare;
            await mine(1000);
            const rewardPerBlock = "1000";
            let totalLockAmount = await nftStaking.totalLockAmount();
            let tx = await nftStaking.connect(Alice).withdraw(pools[0]);
            await expect(tx)
                .to.emit(nftStaking, "Withdraw")
                .withArgs(pools[0], Alice.address, 1);
            let block2 = (await ethers.provider.getBlock(tx.blockNumber)).number;
            let block = (await ethers.provider.getBlock(tx1.blockNumber)).number;

            let expectedRewardAmount = BigNumber.from(rewardPerBlock).mul(block2 - block);
            let expectedAccRewardPerShareCalculated = calAccPerShare(expectedRewardAmount, totalLockAmount).add(BigNumber.from(accumulatedPerShareBeforeWithdraw));
            let accumulatedPerShareAfterWithdraw = (await nftStaking.poolInfo(pools[0])).accRewardPerShare;
            expect(expectedAccRewardPerShareCalculated).to.equal(accumulatedPerShareAfterWithdraw);
        });

        it("Should withdraw nft to user and claim reward", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000);
            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            let expectedReward = await nftStaking.pendingRewardAtBlock(pools[0], Alice.address, blockNum);
            let tx = await nftStaking.connect(Alice).withdrawAndClaim(pools[0], Alice.address);
            await expect(tx)
                .to.emit(nftStaking, "WithdrawAndClaim")
                .withArgs(pools[0], Alice.address, expectedReward);
            expect(await syCHAD.ownerOf(1)).to.equal(Alice.address);
            expect((await nftStaking.userInfo(syCHAD.address, Alice.address)).amount).to.equal(0);
            let actualReward = await rewardToken.balanceOf(Alice.address);
            expect(expectedReward).to.equal(actualReward);
        });

        it("Should not recieve exess reward", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000 * 100000);
            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            let expectedReward = await nftStaking.pendingRewardAtBlock(pools[0], Alice.address, blockNum);
            let tx = await nftStaking.connect(Alice).claim(pools[0], Alice.address);
            await expect(tx)
                .to.emit(nftStaking, "Claimed")
                .withArgs(Alice.address, pools[0], expectedReward);
            let actualReward = await rewardToken.balanceOf(Alice.address);
            expect(expectedReward).to.equal(actualReward);
        });

        it("Should not recieve excess reward after acc uno per share updated", async function () {
            await addPoolFunc();
            await approveNFT();
            await depositNfts();
            await mine(1000 * 100000);
            const blockNum1 = await ethers.provider.getBlockNumber();
            const block1 = await ethers.provider.getBlock(blockNum1);
            let expectedReward1 = await nftStaking.pendingRewardAtBlock(pools[0], Roy.address, blockNum1);
            let tx1 = await nftStaking.connect(Roy).claim(pools[0], Roy.address);
            await expect(tx1)
                .to.emit(nftStaking, "Claimed")
                .withArgs(Roy.address, pools[0], expectedReward1);
            let actualReward1 = await rewardToken.balanceOf(Roy.address);
            expect(expectedReward1).to.equal(actualReward1);


            const blockNum = await ethers.provider.getBlockNumber();
            const block = await ethers.provider.getBlock(blockNum);
            let expectedReward = await nftStaking.pendingRewardAtBlock(pools[0], Alice.address, blockNum);
            let tx = await nftStaking.connect(Alice).claim(pools[0], Alice.address);
            await expect(tx)
                .to.emit(nftStaking, "Claimed")
                .withArgs(Alice.address, pools[0], expectedReward);
            let actualReward = await rewardToken.balanceOf(Alice.address);
            expect(expectedReward).to.equal(actualReward);

            await mine(1000);

            const blockNum2 = await ethers.provider.getBlockNumber();
            const block2 = await ethers.provider.getBlock(blockNum2);
            let expectedReward2 = await nftStaking.pendingRewardAtBlock(pools[0], Alice.address, blockNum2);
            let tx2 = await nftStaking.connect(Alice).claim(pools[0], Alice.address);
            await expect(tx2)
                .to.emit(nftStaking, "Claimed")
                .withArgs(Alice.address, pools[0], expectedReward2);
            let actualReward2 = await rewardToken.balanceOf(Alice.address);
            expect(expectedReward2).to.equal(actualReward2 - actualReward);
        });

    });
});
