import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
interface RewardInfo {
  token: string;
  rewardPerBlock: BigNumber;
  accRewardPerShare: number;
}

let owner: any, addr1: any, addr2: any;
let gaugeController: any,
  votingEscrow: any,
  lpTtoken: any,
  rewardToken: any,
  rewardToken1: any,
  voter:any;
async function setUp() {
  // Contracts are deployed using the first signer/account by default
  [owner, addr1, addr2] = await ethers.getSigners();

  const GaugeController = await ethers.getContractFactory("GaugeController");
  gaugeController = await GaugeController.deploy(owner.address);

  const LpToken = await ethers.getContractFactory("MockToken");
  lpTtoken = await LpToken.deploy();

  const RewardToken = await ethers.getContractFactory("MockToken");
  rewardToken = await RewardToken.deploy();
  const RewardToken1 = await ethers.getContractFactory("MockToken");
  rewardToken1 = await RewardToken1.deploy();
  await lpTtoken.mint(addr1.address, parseUnits("100000", 18));
  await lpTtoken.mint(addr2.address, parseUnits("100000", 18));

  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  votingEscrow = await VotingEscrow.deploy(
    lpTtoken.address,
    gaugeController.address,
    "vot",
    "vt",
    "v.0.1"
  );

  const Voter = await ethers.getContractFactory("Voter");
  voter = await Voter.deploy(addr2.address, votingEscrow.address);
}

async function addPoolFunc() {
  const epoch = 0;

  let reward: RewardInfo[] = [
    {
      token: rewardToken.address,
      rewardPerBlock: parseUnits("1000", 18),
      accRewardPerShare: 0,
    },
  ];

  let tx = await gaugeController.addPool(
    epoch,
    lpTtoken.address,
    votingEscrow.address,
    reward
  );
  return tx;
}

describe("VotingEscrow", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.

  beforeEach(async () => {
    await setUp();
  });

  describe("Funtions", function () {
    it("Should vote", async function () {
        await addPoolFunc();
  
        await lpTtoken
          .connect(addr1)
          .approve(votingEscrow.address, parseUnits("1000", 18));
  
        const blockNum = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNum);
        const timestamp = block.timestamp;
        let time1 = timestamp + 1000000;
        expect(
          await votingEscrow
            .connect(addr1)
            .createLock(parseUnits("1000", 18), time1)
        );
        let userLockedInfo = await votingEscrow.locked(addr1.address);
        let calUnlockTime = (BigNumber.from(time1).div(BigNumber.from(604800))).mul(BigNumber.from(604800));
  
        expect(userLockedInfo.end).to.equal(calUnlockTime);
        expect(userLockedInfo.amount).to.equal(parseUnits("1000", 18));
        expect(
          await gaugeController.userInfo(votingEscrow.address, addr1.address)
        ).to.equal(parseUnits("1000", 18));
        
        let t = await time.latest();
        await voter.connect(owner).whitelistUser(owner.address,true);
        await voter.setGauge(addr2.address, 1);
        const blockNum1 = await ethers.provider.getBlockNumber();
        const block1 = await ethers.provider.getBlock(blockNum1);
        const timestamp1 = block1.timestamp;
        let voteAmount = await votingEscrow.balanceOf(addr1.address, timestamp1 + 1);
        await expect( voter.connect(addr1).vote([addr2.address],[1000])).to.emit(voter, "Voted").withArgs(addr1.address, addr2.address,addr1.address,voteAmount,voteAmount, timestamp1 + 1);
        expect(await voter.voteOnUser(addr1.address)).to.equal(voteAmount);
        expect(await voter.voted(addr1.address)).to.equal(true);
      });

      it("Should reset vote", async function () {
        await addPoolFunc();
  
        await lpTtoken
          .connect(addr1)
          .approve(votingEscrow.address, parseUnits("1000", 18));
  
        const blockNum = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNum);
        const timestamp = block.timestamp;
        let time1 = timestamp + 1000000;
        expect(
          await votingEscrow
            .connect(addr1)
            .createLock(parseUnits("1000", 18), time1)
        );
        let userLockedInfo = await votingEscrow.locked(addr1.address);
        let calUnlockTime = (BigNumber.from(time1).div(BigNumber.from(604800))).mul(BigNumber.from(604800));
  
        expect(userLockedInfo.end).to.equal(calUnlockTime);
        expect(userLockedInfo.amount).to.equal(parseUnits("1000", 18));
        expect(
          await gaugeController.userInfo(votingEscrow.address, addr1.address)
        ).to.equal(parseUnits("1000", 18));
        
        await voter.connect(owner).whitelistUser(owner.address,true);
        await voter.setGauge(addr2.address, 1);
        const blockNum1 = await ethers.provider.getBlockNumber();
        const block1 = await ethers.provider.getBlock(blockNum1);
        const timestamp1 = block1.timestamp;
        let voteAmount = await votingEscrow.balanceOf(addr1.address, timestamp1 + 1);
        await expect( voter.connect(addr1).vote([addr2.address],[1000])).to.emit(voter, "Voted").withArgs(addr1.address, addr2.address,addr1.address,voteAmount,voteAmount, timestamp1 + 1);
        expect(await voter.voteOnUser(addr1.address)).to.equal(voteAmount);
        expect(await voter.voted(addr1.address)).to.equal(true);
        let x = await time.latest();    
        await time.increase(x + 100000);

        const blockNum2 = await ethers.provider.getBlockNumber();
        const block2= await ethers.provider.getBlock(blockNum2);
        const timestamp2 = block2.timestamp + 1;
        await expect( voter.connect(addr1).reset()).to.emit(voter, "Abstained").withArgs(addr1.address, addr2.address, addr1.address, voteAmount,0, timestamp2);
        expect(await voter.voted(addr1.address)).to.equal(false);
        expect(await voter.usedWeights(addr1.address)).to.equal(0);
        expect(await voter.voteOnUser(addr1.address)).to.equal(0);
      });

      it.only("Should poke vote", async function () {
        await addPoolFunc();
  
        await lpTtoken
          .connect(addr1)
          .approve(votingEscrow.address, parseUnits("1000", 18));
  
        const blockNum = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNum);
        const timestamp = block.timestamp;
        let time1 = timestamp + 1000000;
        expect(
          await votingEscrow
            .connect(addr1)
            .createLock(parseUnits("1000", 18), time1)
        );
        let userLockedInfo = await votingEscrow.locked(addr1.address);
        let calUnlockTime = (BigNumber.from(time1).div(BigNumber.from(604800))).mul(BigNumber.from(604800));
  
        expect(userLockedInfo.end).to.equal(calUnlockTime);
        expect(userLockedInfo.amount).to.equal(parseUnits("1000", 18));
        expect(
          await gaugeController.userInfo(votingEscrow.address, addr1.address)
        ).to.equal(parseUnits("1000", 18));
        
        await voter.connect(owner).whitelistUser(owner.address,true);
        await voter.setGauge(addr2.address, 1);
        const blockNum1 = await ethers.provider.getBlockNumber();
        const block1 = await ethers.provider.getBlock(blockNum1);
        const timestamp1 = block1.timestamp;
        let voteAmount = await votingEscrow.balanceOf(addr1.address, timestamp1 + 1);
        await expect( voter.connect(addr1).vote([addr2.address],[1000])).to.emit(voter, "Voted").withArgs(addr1.address, addr2.address,addr1.address,voteAmount,voteAmount, timestamp1 + 1);
        expect(await voter.voteOnUser(addr1.address)).to.equal(voteAmount);
        expect(await voter.voted(addr1.address)).to.equal(true);
        let x = await time.latest();    

        const blockNum2 = await ethers.provider.getBlockNumber();
        const block2= await ethers.provider.getBlock(blockNum2 );
        const timestamp2 = block2.timestamp + 1;
        let voteAmount1 = await votingEscrow.balanceOf(addr1.address, timestamp2);

        await expect( voter.connect(addr1).poke()).to.emit(voter, "Voted").withArgs(addr1.address, addr2.address, addr1.address, voteAmount1,voteAmount1, timestamp2);
        expect(await voter.voteOnUser(addr1.address)).to.equal(voteAmount1);
        expect(await voter.voted(addr1.address)).to.equal(true);
      });
  });
});
