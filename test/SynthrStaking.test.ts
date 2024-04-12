import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import exp from "constants";


let owner: any, addr1: any, addr2: any, Alice: any, Bob: any, Joy: any, Roy: any, Matt: any;
let synthrStaking: any,
    rewardToken: any;

let syCHAD: any, syBULL: any, syHODL: any, syDIAMOND: any, syMAXI: any;
let pools: any;
let totalLockAmount: any;

interface LockInfo {
    maxPoolSize: Number;
    penalty: Number;
    coolDownPeriod: Number;
    totalStaked: Number;
    exist: boolean;
}

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
        lastRewardBlock: 0,
        rewardPerBlock: 0,
        accRewardPerShare: 0,
        epoch: 0,
    }, {
        maxPoolSize: parseUnits("1000000", 18),
        penalty: 35,
        coolDownPeriod: 60*60*24,
        totalStaked: 0,
        exist: true,
        lastRewardBlock: 0,
        rewardPerBlock: 0,
        accRewardPerShare: 0,
        epoch: 0,
    }, {maxPoolSize: parseUnits("1000000", 18),
        penalty: 30,
        coolDownPeriod: 60*60*24,
        totalStaked: 0,
        exist: true,
        lastRewardBlock: 0,
        rewardPerBlock: 0,
        accRewardPerShare: 0,
        epoch: 0,
    }, {maxPoolSize: parseUnits("1000000", 18),
        penalty: 25,
        coolDownPeriod: 60*60*24,
        totalStaked: 0,
        exist: true,
        lastRewardBlock: 0,
        rewardPerBlock: 0,
        accRewardPerShare: 0,
        epoch: 0,
    }];

    let lockAmount = [60*60*24*30*6, 60*60*24*30*9, 60*60*24*30*12, 60*60*24*30*18];

    const SynthrStaking = await ethers.getContractFactory("SynthrStaking");
    
    synthrStaking = await SynthrStaking.deploy(owner.address, rewardToken.address, lockAmount, lockValue);

    await rewardToken.mint(owner.address, parseUnits("10000000000000000000000000000", 18));

    await rewardToken.approve(synthrStaking.address, parseUnits("10000000000000000000000000000", 18))

    let rewardPerBlock: any = [parseUnits("100000000000", 18), parseUnits("100000000000", 18), parseUnits("100000000000", 18), parseUnits("100000000000", 18)]

    await synthrStaking.updateEpoch(owner.address, parseUnits("10000000000000000000000000000", 18), rewardPerBlock, lockAmount);

}


async function depositTx() {

    await rewardToken.mint(Alice.address, parseUnits("100", 18));
    await rewardToken.mint(Bob.address, parseUnits("100", 18));
    await rewardToken.mint(Joy.address, parseUnits("100", 18));
    await rewardToken.mint(Roy.address, parseUnits("100", 18));

    await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("100", 18));
    await rewardToken.connect(Bob).approve(synthrStaking.address, parseUnits("100", 18));
    await rewardToken.connect(Joy).approve(synthrStaking.address, parseUnits("100", 18));
    await rewardToken.connect(Roy).approve(synthrStaking.address, parseUnits("100", 18));
    

    let tx1 = await synthrStaking.connect(Alice).deposit(parseUnits("100", 18), 60*60*24*30*6);
    let tx2 = await synthrStaking.connect(Bob).deposit(parseUnits("100", 18), 60*60*24*30*9);
    let tx3 = await synthrStaking.connect(Joy).deposit(parseUnits("100", 18), 60*60*24*30*12);
    let tx4 = await synthrStaking.connect(Roy).deposit(parseUnits("100", 18), 60*60*24*30*18);

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

describe("SynthrStaking", function () {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.

    beforeEach(async () => {
        await setUp();
    });

    describe("Funtions", function () {

        it("Should have pending reward zero if user has not deposited in pool", async function () {
            const currentTime = await time.latest();
            await time.increaseTo(currentTime + 1000);
            expect(
                await synthrStaking.pendingReward(Alice.address)
            ).to.equal(0);
            expect(
                await synthrStaking.pendingReward(Bob.address)
            ).to.equal(0);
            expect(
                await synthrStaking.pendingReward(Joy.address)
            ).to.equal(0);
            expect(
                await synthrStaking.pendingReward(Roy.address)
            ).to.equal(0);
        });

        it("Should deposit user's token", async function () {

            let txns = await depositTx();
            await expect(txns[0])
                .to.emit(synthrStaking, "Deposit")
                .withArgs(Alice.address, parseUnits("100", 18));
            await expect(txns[1])
                .to.emit(synthrStaking, "Deposit")
                .withArgs(Bob.address, parseUnits("100", 18));
            await expect(txns[2])
                .to.emit(synthrStaking, "Deposit")
                .withArgs(Joy.address, parseUnits("100", 18));
            await expect(txns[3])
                .to.emit(synthrStaking, "Deposit")
                .withArgs(Roy.address, parseUnits("100", 18));
        })
        it("Should update user reward debt after deposits", async function () {

            mine(10000);
            await rewardToken.mint(Alice.address, parseUnits("100", 18));

            await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("100", 18));
            let tx1 = await synthrStaking.connect(Alice).deposit(parseUnits("100", 18), 60*60*24*30*6);

            let poolInfo = await synthrStaking.lockInfo(60*60*24*30*6)

            const lockAmount = {
                Alice: ethers.utils.parseEther("100"), // 100 * 10^18
                Bob: ethers.utils.parseEther("100"),
                Joy: ethers.utils.parseEther("100"),
                Roy: ethers.utils.parseEther("100"),
            }

            let amt0 = calAccRewardPerShare(poolInfo.accRewardPerShare, lockAmount.Alice);

            let AliceInfo = await synthrStaking.userInfo(Alice.address)

            expect(AliceInfo.amount).to.equal(lockAmount.Alice);
            console.log(AliceInfo.lockType," ",AliceInfo.unlockEnd);
            expect(AliceInfo.rewardDebt).to.equal(amt0);

        })

        it("Should transfer reward amount after user triggered claim", async function () {
            await depositTx();
            await mine(1000);
            let latedTime = await time.latest();
            await time.increaseTo(latedTime + 60*60*24*30*6);
            const blockNum = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock(Alice.address, blockNum + 1);
            let tx = await synthrStaking.connect(Alice).claim(Alice.address);
            await expect(tx)
                .to.emit(synthrStaking, "Claimed")
                .withArgs(Alice.address, expectedReward);
            let actualReward = await rewardToken.balanceOf(Alice.address);
            expect(expectedReward).to.equal(actualReward);
        });

        it("Should withdraw token to user", async function () {

            await depositTx();
            await mine(100000000);
            await synthrStaking.connect(Alice).withdrawRequest();
            let latedTime = await time.latest();
            await time.increaseTo(latedTime + 60*60*24);
            const blockNum = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock(Alice.address, blockNum + 1);
            let tx = await synthrStaking.connect(Alice).withdraw(Alice.address);
            await expect(tx)
                .to.emit(synthrStaking, "Withdraw")
                .withArgs(Alice.address, parseUnits("100", 18).add(expectedReward));
            expect((await synthrStaking.userInfo(Alice.address)).amount).to.equal(0);
        });

        it("Should revert if claim is triggered without depositing", async function () {
            await mine(1000);
            await expect(synthrStaking.connect(Matt).claim(Matt.address)).to.revertedWith("SynthrStaking: lock type not exist");
        });

        it("Should claim reward after withdraw is triggged", async function () {

            await depositTx();
            await mine(100000000);
            await synthrStaking.connect(Alice).withdrawRequest();
            let latedTime = await time.latest();
            await time.increaseTo(latedTime + 60*60*24);
            const blockNum1 = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock(Alice.address, blockNum1 + 1);
            let tx = await synthrStaking.connect(Alice).withdraw(Alice.address);
            await expect(tx)
                .to.emit(synthrStaking, "Withdraw")
                .withArgs(Alice.address, parseUnits("100", 18).add(expectedReward));
            expect((await synthrStaking.userInfo(Alice.address)).amount).to.equal(0);
            await mine(10); // 10 blocks are mined after the withdraw is triggged
            
            await expect(synthrStaking.connect(Alice).claim(Alice.address)).to.revertedWith("SynthrStaking: lock type not exist");
        });

        it("Should claim reward after withdraw is triggged with custom configurations", async function () {
            await synthrStaking.setLockInfo(60*60*24*30*6, parseUnits("1000",18), 50, 60*60);
            let rewardPerBlock = [parseUnits("5", 18), parseUnits("5", 18), parseUnits("5", 18), parseUnits("5", 18)]
            let lockAmount = [60*60*24*30*6, 60*60*24*30*9, 60*60*24*30*12, 60*60*24*30*18];
            await rewardToken.mint(owner.address, parseUnits("1000000000000000000000000000000", 18));

              await rewardToken.approve(synthrStaking.address, parseUnits("1000000000000000000000000000000", 18))
            await synthrStaking.updateEpoch(owner.address,parseUnits("20", 18), rewardPerBlock, lockAmount);

            await depositTx();
            await mine(10);
            await synthrStaking.connect(Alice).withdrawRequest();
            let latedTime = await time.latest();
            //increasing the time to bypass the 1 hour cooling period after withdrawRequest()
            await time.increaseTo(latedTime + 60*60 + 60); // 1-hr + 1 minute
            const blockNum1 = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock(Alice.address, blockNum1 + 1);
            let tx = await synthrStaking.connect(Alice).withdraw(Alice.address);
            let expectedReward2 = await synthrStaking.pendingRewardAtBlock(Alice.address, blockNum1 + 1);
            await expect(tx)
                .to.emit(synthrStaking, "Withdraw")
                .withArgs(Alice.address, parseUnits("50", 18).add(expectedReward)); // penalty 50%
            expect((await synthrStaking.userInfo(Alice.address)).amount).to.equal(0);
            await mine(10); // 10 blocks are mined after the withdraw is triggged
            await expect(synthrStaking.connect(Alice).claim(Alice.address)).to.revertedWith("SynthrStaking: lock type not exist");
        });


        it("Should update rewardDebt & AccumulatedUnoPerShare as calculated", async function () {

            await rewardToken.mint(Alice.address, parseUnits("100", 18));

            await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("100", 18));
            let tx1 = await synthrStaking.connect(Alice).deposit(parseUnits("100", 18), 60*60*24*30*6);
            let accumulatedPerShareBeforeWithdraw = (await synthrStaking.lockInfo(60*60*24*30*6)).accRewardPerShare;
            await mine(100000000);
            const rewardPerBlock = (await synthrStaking.lockInfo(60*60*24*30*6)).rewardPerBlock;
            let totalLockAmount = await synthrStaking.totalSupply();
            await synthrStaking.connect(Alice).withdrawRequest();
            let latedTime = await time.latest();
            await time.increaseTo(latedTime + 60*60*24);
            const blockNum1 = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock(Alice.address, blockNum1 + 1);
            let tx = await synthrStaking.connect(Alice).withdraw(Alice.address);
            let block2 = tx.blockNumber;
            let block = tx1.blockNumber;
            let expectedRewardAmount = BigNumber.from(rewardPerBlock).mul(block2 - block);
            console.log("Reward amount: ", block2 - block);
            let expectedAccRewardPerShareCalculated = calAccPerShare(expectedRewardAmount, totalLockAmount).add(BigNumber.from(accumulatedPerShareBeforeWithdraw));
            await expect(tx)
                .to.emit(synthrStaking, "Withdraw")
                .withArgs(Alice.address, parseUnits("100", 18).add(expectedReward));

            let accumulatedPerShareAfterWithdraw = (await synthrStaking.lockInfo(60*60*24*30*6)).accRewardPerShare;
            expect(expectedAccRewardPerShareCalculated).to.equal(accumulatedPerShareAfterWithdraw);
        });

        it("Should withdraw to user and claim reward", async function () {
            await depositTx();
            await mine(100000000);
            await synthrStaking.connect(Alice).withdrawRequest();
            let latedTime = await time.latest();
            await time.increaseTo(latedTime + 60*60*24);
            const blockNum = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock( Alice.address, blockNum + 1);
            let tx = await synthrStaking.connect(Alice).withdraw( Alice.address);
            await expect(tx)
                .to.emit(synthrStaking, "Withdraw")
                .withArgs(Alice.address, parseUnits("100", 18).add(expectedReward));
            expect((await synthrStaking.userInfo(Alice.address)).amount).to.equal(0);
            let actualReward = await rewardToken.balanceOf(Alice.address);
            expect(expectedReward.add(parseUnits("100", 18))).to.equal(actualReward);

        });

        it("Should not withdraw without withdraw request", async function () {
            await depositTx();
            await mine(1000 * 100000);
            
            await expect(synthrStaking.connect(Alice).withdraw(Alice.address)).to.revertedWith("SynthrStaking: request for withdraw");
        });

        it("Should not recieve full amount if withdraw before unlock time", async function () {
             await rewardToken.mint(Alice.address, parseUnits("100", 18));
            
            await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("100", 18));
            let tx1 = await synthrStaking.connect(Alice).deposit(parseUnits("100", 18), 60*60*24*30*6);

            await synthrStaking.connect(Alice).withdrawRequest();
            let latedTime = await time.latest();
            await time.increaseTo(latedTime + 60*60*24);
            const blockNum = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock( Alice.address, blockNum + 1);
            let tx = await synthrStaking.connect(Alice).withdraw( Alice.address);
            
            let pendaltyAmount = (parseUnits("100", 18).mul(100 - 40)).div(100);

            await expect(tx)
                .to.emit(synthrStaking, "Withdraw")
                .withArgs(Alice.address, pendaltyAmount.add(expectedReward));

            expect(await synthrStaking.penaltyAmount()).to.equal(parseUnits("100", 18).sub(pendaltyAmount));
        });

        it("Should withdraw penalty amount", async function () {
            await rewardToken.mint(Alice.address, parseUnits("100", 18));
           
           await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("100", 18));
           let tx1 = await synthrStaking.connect(Alice).deposit(parseUnits("100", 18), 60*60*24*30*6);

           await synthrStaking.connect(Alice).withdrawRequest();
           let latedTime = await time.latest();
           await time.increaseTo(latedTime + 60*60*24);
           const blockNum = await ethers.provider.getBlockNumber();
           let expectedReward = await synthrStaking.pendingRewardAtBlock( Alice.address, blockNum + 1);
           await synthrStaking.connect(Alice).withdraw( Alice.address);
           
           let pendaltyAmount = (parseUnits("100", 18).mul(100 - 40)).div(100);

           let tx = await synthrStaking.withdrawPenalty(owner.address);

           await expect(tx)
                .to.emit(synthrStaking, "WithdrawPenalty")
                .withArgs(owner.address, owner.address, parseUnits("100", 18).sub(pendaltyAmount));
       });

       it("Should not allow user to deposit if pool is paused", async function () {
            await synthrStaking.pausePool();
            await rewardToken.mint(Alice.address, parseUnits("100", 18));
            await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("100", 18));
            await expect(synthrStaking.connect(Alice).deposit(parseUnits("100", 18), 60*60*24*30*6)).to.revertedWithCustomError(synthrStaking, "EnforcedPause");
        });

        it("Should not allow user to withdraw if pool is paused", async function () {
            await depositTx();
            await mine(100000000);
            await synthrStaking.pausePool();
            await expect(synthrStaking.connect(Alice).withdrawRequest()).to.revertedWithCustomError(synthrStaking, "EnforcedPause");
        });

        it("Should allow user to withdraw if pool is kiiled", async function () {
            await depositTx();
            await mine(100000000);

            await synthrStaking.killPool();
            await synthrStaking.connect(Alice).withdrawRequest();
            let latedTime = await time.latest();
            await time.increaseTo(latedTime + 60*60*24);
            const blockNum = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock( Alice.address, blockNum + 1);
            let tx = await synthrStaking.connect(Alice).withdraw( Alice.address);
        });

        it("Should not allow emergency withdrawals by the user", async function () {
            // Deposit some tokens for testing
            await rewardToken.mint(Alice.address, parseUnits("100", 18));

            // Check the user's balance before emergency withdrawal
            let userBalanceBefore = await rewardToken.balanceOf(Alice.address);

            await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("100", 18));
            await synthrStaking.connect(Alice).deposit(parseUnits("100", 18), 60 * 60 * 24 * 30 * 6);
        
        
            // Check if the EmergencyWithdraw event was emitted
            await expect(synthrStaking.connect(Alice).emergencyWithdraw())
                .to.be.revertedWith('SynthrStaking: emergency withdraw not allowed');
        
        });
        
     it("Should not withdraw token to user before cooldown", async function () {
            await depositTx();
            await synthrStaking.connect(Alice).withdrawRequest();
            let latedTime = await time.latest();
            // await time.increaseTo(latedTime + 60*60*24);
            const blockNum = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock(Alice.address, blockNum + 1);
          
            await expect(synthrStaking.connect(Alice)
                .withdraw(Alice.address))
                .to.be.revertedWith("SynthrStaking: lock time not end")
          
        });  

        it("Should deposit tokens with multiple lock types and verify lock details", async function () {
            await depositTx();

            // Check user's lock type and unlock end time
            let userLockType = await synthrStaking.userInfo(Alice.address);
            let locktype1 =userLockType.lockType;
            let userLockType2 = await synthrStaking.userInfo(Bob.address);
            let locktype2 =userLockType2.lockType;
            let userLockType3 = await synthrStaking.userInfo(Joy.address);
            let locktype3 =userLockType3.lockType;
            let userLockType4 = await synthrStaking.userInfo(Roy.address);
            let locktype4 =userLockType4.lockType;

            expect(locktype1*1.5).to.be.equal(locktype2);
            expect(locktype1*2).to.be.equal(locktype3);
            expect(locktype1*3).to.be.equal(locktype4);
        });
        
        it("Should revert on depositing tokens more than max allowed", async function () {
            await rewardToken.mint(Alice.address, parseUnits("1000001", 18));
            await rewardToken.connect(Alice)
                .approve(synthrStaking.address, parseUnits("1000001", 18)
            );

            // let tx = await synthrStaking.connect(Alice).deposit(parseUnits("1000001", 18), 60*60*24*30*6);
            
            await expect(
                synthrStaking.connect(Alice)
                    .deposit(parseUnits("1000001", 18), 60*60*24*30*6)
                ).to.be.revertedWith('SynthrStaking: max amount limit exceed');
        });

        it("Should allow contract owner to recover tokens sent to the contract address", async function () {

            // Send tokens to the contract address (simulating accidental transfer)
            await rewardToken.mint(owner.address, parseUnits("100", 18));
            const tokenAmount = parseUnits("100", 18);
            await rewardToken.connect(owner).transfer(synthrStaking.address, tokenAmount);
        
            // Check the contract's token balance before recovery
            const contractBalanceBefore = await rewardToken.balanceOf(synthrStaking.address);

            const ownerBalBef = await rewardToken.balanceOf(owner.address);
            expect(ownerBalBef).to.be.equal(0);
            // Call the recover function as the contract owner
            await synthrStaking.connect(owner).recoverToken(rewardToken.address,owner.address,tokenAmount);
            const ownerBalAft = await rewardToken.balanceOf(owner.address);
            expect(ownerBalAft).to.be.equal(ethers.utils.parseEther("100"));
           
        });
        
        it("Should set lock info with a valid lock type, max pool size, penalty, and cooldown period", async function () {
            await synthrStaking.setLockInfo(1, 2000, 20, 20);
            const lockInfo = await synthrStaking.lockInfo(1);
            expect(lockInfo.maxPoolSize).to.equal(2000);
            expect(lockInfo.penalty).to.equal(20);
            expect(lockInfo.coolDownPeriod).to.equal(20);
          });
        
        
        it("Should allow emergency withdrawal before lock expiry and claim rewards repeatedly without penalty", async function () {
            // Deposit some tokens for testing
            await rewardToken.mint(Alice.address, parseUnits("100", 18));
            let initialBalance = await rewardToken.balanceOf(Alice.address);
            // Check the user's balance before emergency withdrawal
            let userBalanceBefore = await rewardToken.balanceOf(Alice.address);

            await rewardToken.connect(Alice).approve(synthrStaking.address, parseUnits("100", 18));
            await synthrStaking.connect(Alice).deposit(parseUnits("100", 18), 60 * 60 * 24 * 30 * 6);
        
            mine(10000);
            let latedTime = await time.latest();
            await time.increaseTo(latedTime + 60 * 60 * 24 * 30 * 5);


            const blockNum = await ethers.provider.getBlockNumber();
            let expectedReward = await synthrStaking.pendingRewardAtBlock( Alice.address, blockNum + 1);
            let beforeClaim = await rewardToken.balanceOf(Alice.address);
            let claimTx0 = await synthrStaking.connect(Alice).claim(Alice.address);
            let finalBal = await rewardToken.balanceOf(Alice.address);
            console.log("expected reward ",expectedReward," before claim",beforeClaim," after claim",finalBal);
            // Perform an emergency withdrawal as the owner
            let tx = await synthrStaking.connect(Alice).emergencyWithdraw();
            let final = await rewardToken.balanceOf(Alice.address);
           console.log("initial bal ",initialBalance," final balance is ",final);
           
        });
           
    });
});
