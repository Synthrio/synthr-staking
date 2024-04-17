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

let owner: any, addr1: any, addr2: any, addr3: any, addr4: any, addr5: any;
let votingEscrow: any,
  lpTtoken: any,
  rewardToken: any,
  rewardToken1: any,
  voter: any;
async function setUp() {
  // Contracts are deployed using the first signer/account by default
  [owner, addr1, addr2, addr3, addr4, addr5] = await ethers.getSigners();

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
    "vot",
    "vt",
    "v.0.1"
  );

  const Voter = await ethers.getContractFactory("Voter");
  voter = await Voter.deploy(addr2.address, votingEscrow.address);
}

async function setUpVotingAndGauge() {

  await lpTtoken
    .connect(addr1)
    .approve(votingEscrow.address, parseUnits("1000", 18));

  const blockNum = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  const timestamp = block.timestamp;
  let time1 = timestamp + 1000000;
  expect(
    await votingEscrow.connect(addr1).createLock(parseUnits("1000", 18), time1)
  );
  let userLockedInfo = await votingEscrow.locked(addr1.address);
  let calUnlockTime = BigNumber.from(time1)
    .div(BigNumber.from(604800))
    .mul(BigNumber.from(604800));

  expect(userLockedInfo.end).to.equal(calUnlockTime);
  expect(userLockedInfo.amount).to.equal(parseUnits("1000", 18));
}

describe("Voter", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.

  beforeEach(async () => {
    await setUp();
  });

  describe("Funtions", function () {
    it("Should vote", async function () {
      await setUpVotingAndGauge();
      
      
      let t = await time.latest();
      await voter.connect(owner).whitelistUser([owner.address], [true]);
      await voter.addPool(1);
      const blockNum1 = await ethers.provider.getBlockNumber();
      const block1 = await ethers.provider.getBlock(blockNum1);
      const timestamp1 = block1.timestamp;
      let voteAmount = await votingEscrow.balanceOfAtTime(
        addr1.address,
        timestamp1 + 1
      );
      await expect(voter.connect(addr1).vote([1], [1000]))
        .to.emit(voter, "Voted")
        .withArgs(
          addr1.address,
          1,
          addr1.address,
          voteAmount,
          voteAmount,
          timestamp1 + 1
        );
      expect(await voter.usedWeights(addr1.address)).to.equal(voteAmount);
      expect(await voter.voted(addr1.address)).to.equal(true);
    });
    
    it("Should whilist multiper user", async function () {
      await setUpVotingAndGauge();

      let t = await time.latest();
      await voter.connect(owner).whitelistUser([owner.address, addr3.address, addr4.address, addr5.address], [true, true, true, true]);
      expect(await voter.isWhitelistedUser(owner.address)).to.equal(true);
      expect(await voter.isWhitelistedUser(addr3.address)).to.equal(true);
      expect(await voter.isWhitelistedUser(addr4.address)).to.equal(true);
      expect(await voter.isWhitelistedUser(addr5.address)).to.equal(true);
      await voter.addPool(1);
      const blockNum1 = await ethers.provider.getBlockNumber();
      const block1 = await ethers.provider.getBlock(blockNum1);
      const timestamp1 = block1.timestamp;
      let voteAmount = await votingEscrow.balanceOfAtTime(
        addr1.address,
        timestamp1 + 1
      );
      await expect(voter.connect(addr1).vote([1], [1000]))
        .to.emit(voter, "Voted")
        .withArgs(
          addr1.address,
          1,
          addr1.address,
          voteAmount,
          voteAmount,
          timestamp1 + 1
        );
      expect(await voter.usedWeights(addr1.address)).to.equal(voteAmount);
      expect(await voter.voted(addr1.address)).to.equal(true);
      expect(await voter.voted(addr2.address)).to.equal(false);
    });

    it("Should vote for multiple pools", async function () {
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
      let calUnlockTime = BigNumber.from(time1)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));

      expect(userLockedInfo.end).to.equal(calUnlockTime);
      expect(userLockedInfo.amount).to.equal(parseUnits("1000", 18));

      let t = await time.latest();
      await voter.connect(owner).whitelistUser([owner.address], [true]);
      await voter.addPool(5);
      expect(await voter.isAlive(1)).to.equal(true);
      expect(await voter.isAlive(2)).to.equal(true);
      expect(await voter.isAlive(3)).to.equal(true);
      expect(await voter.isAlive(4)).to.equal(true);
      expect(await voter.isAlive(5)).to.equal(true);
      const blockNum1 = await ethers.provider.getBlockNumber();
      const block1 = await ethers.provider.getBlock(blockNum1);
      const timestamp1 = block1.timestamp;
      let voteAmount = await votingEscrow.balanceOfAtTime(
        addr1.address,
        timestamp1 + 1
      );
      let voteOnSecond = BigNumber.from(100)
        .mul(voteAmount)
        .div(BigNumber.from(600));

      await expect(voter.connect(addr1).vote([2, 3, 4], [100, 200, 300]))
        .to.emit(voter, "Voted")
        .withArgs(
          addr1.address,
          2,
          addr1.address,
          voteOnSecond,
          voteOnSecond,
          timestamp1 + 1
        );
      expect(await voter.weights(1)).to.equal(0);
      let voteOnThird = BigNumber.from(200)
        .mul(voteAmount)
        .div(BigNumber.from(600));
      expect(await voter.weights(3)).to.equal(voteOnThird);
      let voteOnFourth = BigNumber.from(300)
        .mul(voteAmount)
        .div(BigNumber.from(600));
      expect(await voter.weights(4)).to.equal(voteOnFourth);
      expect(await voter.voted(addr1.address)).to.equal(true);
    });

    it("Should reset vote", async function () {
      await setUpVotingAndGauge();

      await voter.connect(owner).whitelistUser([owner.address], [true]);
      await voter.addPool(1);
      const blockNum1 = await ethers.provider.getBlockNumber();
      const block1 = await ethers.provider.getBlock(blockNum1);
      const timestamp1 = block1.timestamp;
      let voteAmount = await votingEscrow.balanceOfAtTime(
        addr1.address,
        timestamp1 + 1
      );
      await expect(voter.connect(addr1).vote([1], [1000]))
        .to.emit(voter, "Voted")
        .withArgs(
          addr1.address,
          1,
          addr1.address,
          voteAmount,
          voteAmount,
          timestamp1 + 1
        );
      expect(await voter.usedWeights(addr1.address)).to.equal(voteAmount);
      expect(await voter.voted(addr1.address)).to.equal(true);
      let x = await time.latest();
      await time.increase(x + 100000);

      const blockNum2 = await ethers.provider.getBlockNumber();
      const block2 = await ethers.provider.getBlock(blockNum2);
      const timestamp2 = block2.timestamp + 1;
      await expect(voter.connect(addr1).reset())
        .to.emit(voter, "Abstained")
        .withArgs(addr1.address, 1, addr1.address, voteAmount, 0, timestamp2);
      expect(await voter.voted(addr1.address)).to.equal(false);
      expect(await voter.usedWeights(addr1.address)).to.equal(0);
    });

    it("Should poke vote", async function () {
      await setUpVotingAndGauge();
      await voter.connect(owner).whitelistUser([owner.address], [true]);
      await voter.addPool(1);
      const blockNum1 = await ethers.provider.getBlockNumber();
      const block1 = await ethers.provider.getBlock(blockNum1);
      const timestamp1 = block1.timestamp;
      let voteAmount = await votingEscrow.balanceOfAtTime(
        addr1.address,
        timestamp1 + 1
      );
      await expect(voter.connect(addr1).vote([1], [1000]))
        .to.emit(voter, "Voted")
        .withArgs(
          addr1.address,
          1,
          addr1.address,
          voteAmount,
          voteAmount,
          timestamp1 + 1
        );
      expect(await voter.usedWeights(addr1.address)).to.equal(voteAmount);
      expect(await voter.voted(addr1.address)).to.equal(true);
      let x = await time.latest();

      const blockNum2 = await ethers.provider.getBlockNumber();
      const block2 = await ethers.provider.getBlock(blockNum2);
      const timestamp2 = block2.timestamp + 1;
      let voteAmount1 = await votingEscrow.balanceOfAtTime(addr1.address, timestamp2);

      await expect(voter.connect(addr1).poke())
        .to.emit(voter, "Voted")
        .withArgs(
          addr1.address,
          1,
          addr1.address,
          voteAmount1,
          voteAmount1,
          timestamp2
        );
      expect(await voter.voted(addr1.address)).to.equal(true);
      expect(await voter.usedWeights(addr1.address)).to.equal(voteAmount1);
    });

    it("Should revert if voter vote again not", async function () {
      await setUpVotingAndGauge();
      await voter.connect(owner).whitelistUser([owner.address], [true]);
      await voter.addPool(1);
      const blockNum1 = await ethers.provider.getBlockNumber();
      const block1 = await ethers.provider.getBlock(blockNum1);
      const timestamp1 = block1.timestamp;
      let voteAmount = await votingEscrow.balanceOfAtTime(
        addr1.address,
        timestamp1 + 1
      );
      await expect(voter.connect(addr1).vote([1], [1000]))
        .to.emit(voter, "Voted")
        .withArgs(
          addr1.address,
          1,
          addr1.address,
          voteAmount,
          voteAmount,
          timestamp1 + 1
        );

      await expect(voter.connect(addr1).vote([1],[1000])).to.be.revertedWithCustomError(voter, "AlreadyVotedOrDeposited");
    });

    it("Should revert if voter vote for not alive pool", async function () {
      await setUpVotingAndGauge();
      await voter.connect(owner).whitelistUser([owner.address], [true]);
      await voter.addPool(1);
      const blockNum1 = await ethers.provider.getBlockNumber();
      const block1 = await ethers.provider.getBlock(blockNum1);
      const timestamp1 = block1.timestamp;
      let voteAmount = await votingEscrow.balanceOfAtTime(
        addr1.address,
        timestamp1 + 1
      );

      await expect(voter.connect(addr1).vote([2],[1000])).to.be.revertedWithCustomError(voter, "PoolNotAlive");
    });
  });
});
