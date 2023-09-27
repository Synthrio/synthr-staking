import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Address } from "cluster";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { before } from "mocha";
import internal from "stream";
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
  rewardToken1: any;
async function setUp() {
  // Contracts are deployed using the first signer/account by default
  [owner, addr1, addr2] = await ethers.getSigners();

  const GaugeController = await ethers.getContractFactory("GaugeController");
  gaugeController = await GaugeController.deploy(owner.address);

  const LpToken = await ethers.getContractFactory("MyToken");
  lpTtoken = await LpToken.deploy();

  const RewardToken = await ethers.getContractFactory("MyToken");
  rewardToken = await RewardToken.deploy();
  const RewardToken1 = await ethers.getContractFactory("MyToken");
  rewardToken1 = await RewardToken1.deploy();
  await lpTtoken.mint(addr1.address, parseUnits("100000", 18));
  await lpTtoken.mint(addr2.address, parseUnits("100000", 18));

  await rewardToken.mint(addr2.address, parseUnits("1000000000", 18));
  await rewardToken1.mint(addr2.address, parseUnits("1000000000", 18));

  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  votingEscrow = await VotingEscrow.deploy(
    lpTtoken.address,
    gaugeController.address,
    "vot",
    "vt",
    "v.0.1"
  );
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

describe("GaugeController", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.

  beforeEach(async () => {
    await setUp();
  });

  describe("Funtions", function () {
    it("Should add pool in controller", async function () {
      let tx = await addPoolFunc();
      expect(tx)
        .to.emit(gaugeController, "LogPoolAddition")
        .withArgs(votingEscrow.address, lpTtoken.address);
      const blockNum = await ethers.provider.getBlockNumber();
      let poolInfo = await gaugeController.poolInfo(votingEscrow.address);
      expect(poolInfo.epoch).to.equal(0);
      expect(poolInfo.index).to.equal(0);
      expect(poolInfo.lastRewardBlock).to.equal(blockNum);
    });

    it("Should update user reward in controller", async function () {
      await addPoolFunc();
      await lpTtoken
        .connect(addr1)
        .approve(votingEscrow.address, parseUnits("1000", 18));
      await time.increaseTo(10000000000);
      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;

      await votingEscrow
        .connect(addr1)
        .createLock(parseUnits("1000", 18), timestamp + 1000000);
      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(parseUnits("1000", 18));
      expect(await lpTtoken.balanceOf(votingEscrow.address)).to.equal(
        parseUnits("1000", 18)
      );
    });

    it("Should have pending reward zero if uesr has not deposited in pool", async function () {
      await addPoolFunc();
      await time.increaseTo(20000000000);
      expect(
        await gaugeController.pendingReward(votingEscrow.address, addr1.address)
      ).to.equal(0);
    });

    it("Should update rewardDebt and amount of user if he has withdraw from pool", async function () {
      await addPoolFunc();
      await lpTtoken
        .connect(addr1)
        .approve(votingEscrow.address, parseUnits("1000", 18));
      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      await votingEscrow
        .connect(addr1)
        .createLock(parseUnits("1000", 18), timestamp + 1000000);
      await time.increaseTo(30000000100);

      expect(await votingEscrow.connect(addr1).withdraw())
        .to.emit(votingEscrow, "Withdrew")
        .withArgs(addr1.address, parseUnits("10000000", 18), timestamp);
      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(0);
    });

    it("Should update epoch for given pool", async function () {
      await addPoolFunc();
      await time.increaseTo(30000000115);
      await rewardToken
        .connect(addr2)
        .approve(gaugeController.address, parseUnits("10000000", 18));
      expect(
        await gaugeController.updateEpoch(
          votingEscrow.address,
          addr2.address,
          [0],
          [parseUnits("1000", 18)],
          [parseUnits("10000000", 18)]
        )
      )
        .to.emit(gaugeController, "EpochUpdated")
        .withArgs(votingEscrow.address, 1);
      expect(
        (await gaugeController.poolInfo(votingEscrow.address)).epoch
      ).to.equal(1);
      expect(await rewardToken.balanceOf(gaugeController.address)).to.equal(
        parseUnits("10000000", 18)
      );
    });

    it("Should claim reward", async function () {
      await addPoolFunc();
      await rewardToken
        .connect(addr2)
        .approve(gaugeController.address, parseUnits("10000000", 18));

      expect(
        await gaugeController.updateEpoch(
          votingEscrow.address,
          addr2.address,
          [0],
          [parseUnits("1000", 18)],
          [parseUnits("10000000", 18)]
        )
      )
        .to.emit(gaugeController, "EpochUpdated")
        .withArgs(votingEscrow.address, 1);

      await lpTtoken
        .connect(addr1)
        .approve(votingEscrow.address, parseUnits("1000", 18));

      let blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;

      await votingEscrow
        .connect(addr1)
        .createLock(parseUnits("1000", 18), timestamp + 1000000);
      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(parseUnits("1000", 18));

      await time.increaseTo(30000000132);
      blockNum = await ethers.provider.getBlockNumber();

      let ACC_REWARD_PRECISION = await gaugeController.ACC_REWARD_PRECISION();
      let lastRewardBlock = (
        await gaugeController.poolInfo(votingEscrow.address)
      ).lastRewardBlock;
      let lpSupply = await lpTtoken.balanceOf(votingEscrow.address);
      let rewardPerBlock = (
        await gaugeController.reward(votingEscrow.address, 0)
      ).rewardPerBlock;
      let rewardAmount = (blockNum + 1 - lastRewardBlock) * rewardPerBlock;
      let pendingAccRewardPerShare =
        (rewardAmount * ACC_REWARD_PRECISION) / lpSupply;
      let accRewardPerShare = (
        await gaugeController.reward(votingEscrow.address, 0)
      ).accRewardPerShare.add(
        BigNumber.from(pendingAccRewardPerShare.toString())
      );
      let userAmount: any = parseUnits("1000", 18);
      let userRewardDebt = (
        await gaugeController.userRewards(votingEscrow.address, addr1.address)
      )[0];
      let accumulatedReward = userAmount
        .mul(accRewardPerShare)
        .div(ACC_REWARD_PRECISION);
      let pendingReward = accumulatedReward.sub(userRewardDebt);
      expect(
        await gaugeController
          .connect(addr1)
          .claim(votingEscrow.address, addr1.address)
      )
        .to.emit(gaugeController, "Claimed")
        .withArgs(addr1.address, votingEscrow.address, pendingReward);
      expect(await rewardToken.balanceOf(addr1.address)).to.equal(
        pendingReward
      );
      expect(
        await gaugeController.pendingReward(votingEscrow.address, addr1.address)
      ).to.equal(0);
    });

    it("Should add reward tokens in pool", async function () {
      await addPoolFunc();
      await time.increaseTo(30000000144);

      let reward: RewardInfo[] = [
        {
          token: rewardToken1.address,
          rewardPerBlock: parseUnits("1000", 18),
          accRewardPerShare: 0,
        },
      ];

      expect(await gaugeController.addRewardToken(votingEscrow.address, reward))
        .to.emit(gaugeController, "LogSetPool")
        .withArgs(votingEscrow.address, reward);
      expect(
        (await gaugeController.poolInfo(votingEscrow.address)).index
      ).to.equal(1);
      expect(
        (await gaugeController.reward(votingEscrow.address, 1)).token
      ).to.equal(rewardToken1.address);
    });

    it("Should update pool and accRewardPerShare for reward token in pool by anyone", async function () {
      await addPoolFunc();
      await time.increaseTo(30000000156);
      const blockNum = await ethers.provider.getBlockNumber();
      expect(
        await gaugeController.connect(addr1).updatePool(votingEscrow.address)
      )
        .to.emit(gaugeController, "LogUpdatePool")
        .withArgs(votingEscrow.address, blockNum + 1);
      expect(
        (await gaugeController.poolInfo(votingEscrow.address)).lastRewardBlock
      ).to.equal(blockNum + 1);
      expect(
        (await gaugeController.poolInfo(votingEscrow.address)).lastRewardBlock
      ).to.equal(blockNum + 1);
    });

    it("Should update user rewardDept as calculated", async function () {
      await addPoolFunc();
      await lpTtoken
        .connect(addr1)
        .approve(votingEscrow.address, parseUnits("1000", 18));

      let blockNum = await ethers.provider.getBlockNumber();
      let block = await ethers.provider.getBlock(blockNum);
      let timestamp = block.timestamp;

      await votingEscrow
        .connect(addr1)
        .createLock(parseUnits("1000", 18), timestamp + 1000000);

      await lpTtoken
        .connect(addr2)
        .approve(votingEscrow.address, parseUnits("1000", 18));

      await time.increaseTo(30000000171);
      blockNum = await ethers.provider.getBlockNumber();
      block = await ethers.provider.getBlock(blockNum);
      timestamp = block.timestamp;

      let ACC_REWARD_PRECISION = await gaugeController.ACC_REWARD_PRECISION();

      let lastRewardBlock = (
        await gaugeController.poolInfo(votingEscrow.address)
      ).lastRewardBlock;

      let lpSupply = (await lpTtoken.balanceOf(votingEscrow.address)) * 2;

      let rewardPerBlock = (
        await gaugeController.reward(votingEscrow.address, 0)
      ).rewardPerBlock;

      let rewardAmount = (blockNum + 1 - lastRewardBlock) * rewardPerBlock;

      let pendingAccRewardPerShare =
        (rewardAmount * ACC_REWARD_PRECISION) / lpSupply;

      let accRewardPerShare = (
        await gaugeController.reward(votingEscrow.address, 0)
      ).accRewardPerShare;

      let updatedAccRewardPerShare = accRewardPerShare.add(
        BigNumber.from(pendingAccRewardPerShare.toString())
      );

      let userAmount = parseUnits("1000", 18);
      let userRewardDebt = userAmount
        .mul(updatedAccRewardPerShare)
        .div(ACC_REWARD_PRECISION);

      let userRewardDebtBefore = (
        await gaugeController.userRewards(votingEscrow.address, addr2.address)
      )[0];

      await votingEscrow
        .connect(addr2)
        .createLock(parseUnits("1000", 18), timestamp + 2000000);

      let userRewardDebtAfter = (
        await gaugeController.userRewards(votingEscrow.address, addr2.address)
      )[0];
      let calUserRewardDebtAfter = userRewardDebtBefore.add(
        BigNumber.from(userRewardDebt.toString())
      );
      expect(userRewardDebtAfter).to.equal(calUserRewardDebtAfter);
    });

    it("Should revert if non controller try to add reward tokens in pool", async function () {
      await addPoolFunc();

      let reward: RewardInfo[] = [
        {
          token: rewardToken1.address,
          rewardPerBlock: parseUnits("1000", 18),
          accRewardPerShare: 0,
        },
      ];

      await expect(
        gaugeController
          .connect(addr2)
          .addRewardToken(votingEscrow.address, reward)
      ).to.be.revertedWith("GaugeController: not authorized");
    });

    it("Should revert if controller try to add reward tokens more than max limit", async function () {
      await addPoolFunc();

      let reward: RewardInfo[] = [
        {
          token: rewardToken1.address,
          rewardPerBlock: parseUnits("1000", 18),
          accRewardPerShare: 0,
        },
      ];
      for (let i = 0; i < 7; i++) {
        expect(
          await gaugeController.addRewardToken(votingEscrow.address, reward)
        )
          .to.emit(gaugeController, "LogSetPool")
          .withArgs(votingEscrow.address, reward);
      }

      await expect(
        gaugeController.addRewardToken(votingEscrow.address, reward)
      ).to.be.revertedWith("GaugeController: excced reward tokens");
    });

    it("Should revert if non controller try to update epoch", async function () {
      await addPoolFunc();

      await expect(
        gaugeController
          .connect(addr1)
          .updateEpoch(
            votingEscrow.address,
            addr2.address,
            [0],
            [parseUnits("1000", 18)],
            [parseUnits("10000000", 18)]
          )
      ).to.be.revertedWith("GaugeController: not authorized");
    });

    it("Should revert if non controller try to add pool in GaugeController", async function () {
      const epoch = 0;

      let reward: RewardInfo[] = [
        {
          token: rewardToken.address,
          rewardPerBlock: parseUnits("1000", 18),
          accRewardPerShare: 0,
        },
      ];

      await expect(
        gaugeController
          .connect(addr1)
          .addPool(epoch, lpTtoken.address, votingEscrow.address, reward)
      ).to.be.revertedWith("GaugeController: not authorized");
    });

    it("Should revert if non controller try to updateReward of user", async function () {
      await addPoolFunc();

      await expect(
        gaugeController
          .connect(addr1)
          .updateReward(
            votingEscrow.address,
            addr2.address,
            parseUnits("1000", 18),
            true
          )
      ).to.be.revertedWith("GaugeController: not authorized");
    });
  });
});
