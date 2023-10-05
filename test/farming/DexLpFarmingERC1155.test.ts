import { expect, assert } from "chai";
import { prepare, deploy, getBigNumber } from "../utilities";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { parseUnits } from "ethers/lib/utils";
import { get } from "http";

describe("DerivedDexLpFarmingERC1155", function () {
  before(async function () {
    await prepare(this, ["DerivedDexLpFarmingERC1155", "LBPair", "MockToken"]);
  });

  let owner: any, addr1: any, addr2: any;
  beforeEach(async function () {
    await deploy(this, [["rewardToken", this.MockToken]]);
    await deploy(this, [["lbPair", this.LBPair]]);

    [owner, addr1, addr2] = await ethers.getSigners();
    await deploy(this, [
      [
        "chef",
        this.DerivedDexLpFarmingERC1155,
        [this.rewardToken.address, this.lbPair.address],
      ],
    ]);

    await this.rewardToken.mint(
      owner.address,
      parseUnits("100000000000000000000000000000000000", 18)
    );
    await this.lbPair.mint(
      owner.address,
      getBigNumber(1),
      parseUnits("1000", 18)
    );
    await this.lbPair.approveForAll(this.chef.address, true);
    await this.rewardToken.approve(this.chef.address, parseUnits("403", 18));
    await this.chef.setRewardPerBlock(
      "10000000000000000",
      owner.address,
      parseUnits("403", 18)
    );
  });

  describe("PoolLength", function () {
    it("PoolLength should execute", async function () {
      await this.chef.add(10);
      expect(await this.chef.poolLength()).to.be.equal(1);
    });
  });

  describe("Set", function () {
    it("Should emit event LogSetPool", async function () {
      await this.chef.add(10);
      await expect(this.chef.set(0, 10))
        .to.emit(this.chef, "LogSetPool")
        .withArgs(0, 10);
      await expect(this.chef.set(0, 11))
        .to.emit(this.chef, "LogSetPool")
        .withArgs(0, 11);
    });

    it("Should revert if invalid pool", async function () {
      let err;
      try {
        await this.chef.set(0, 10);
      } catch (e) {
        err = e;
      }
      // change
      assert.equal(
        err.toString(),
        "Error: VM Exception while processing transaction: reverted with panic code 0x32 (Array accessed at an out-of-bounds or negative index)"
      );
    });
  });

  describe("PendingrewardToken", function () {
    it("PendingrewardToken should equal ExpectedrewardToken", async function () {
      await this.chef.add(10);
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("1000", 18)
      );
      let log = await this.chef.depositBatch(0, [1], [parseUnits("100", 18)]);
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(
        parseUnits("100", 18)
      );

      await time.increaseTo(30000122335);
      let log2 = await this.chef.updatePool(0);

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;

      let rewardAmount = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = (await this.lbPair.getBin(1))[1];
      let lpSupply = (await this.lbPair.getReserve())[1];
      let expectedrewardToken = rewardAmount
        .mul(parseUnits("1", 18))
        .div(lpSupply);

      expectedrewardToken = expectedrewardToken
        .mul(liqAmount)
        .div(parseUnits("1", 18));
      let pendingrewardToken = await this.chef.pendingReward(
        0,
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(expectedrewardToken);
    });

    it("When time is lastRewardTime", async function () {
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      await this.chef.add(10);
      let log = await this.chef.depositBatch(0, [1], [parseUnits("100", 18)]);
      let prevACCPerShare = (await this.chef.poolInfo(0)).accRewardPerShare;

      let userRewardDebt = parseUnits("1300", 18)
        .mul(prevACCPerShare)
        .div(parseUnits("1", 18));
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(
        parseUnits("100", 18)
      );
      await time.increaseTo(30000123348);
      let accPerShare = (await this.chef.poolInfo(0)).accRewardPerShare;
      let log2 = await this.chef.updatePool(0);

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;

      let rewardAmount = BigNumber.from("10000000000000000").mul(
        block2 - block
      );

      let liqAmount = (await this.lbPair.getBin(1))[1];

      let lpSupply = (await this.lbPair.getReserve())[1];

      accPerShare = accPerShare.add(
        rewardAmount.mul(parseUnits("1", 18)).div(lpSupply)
      );

      let expectedrewardToken = accPerShare
        .mul(liqAmount)
        .div(parseUnits("1", 18));

      let pendingrewardToken = await this.chef.pendingReward(
        0,
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(
        expectedrewardToken.sub(userRewardDebt)
      );
    });
  });

  describe("Add", function () {
    it("Should add pool with reward token multiplier", async function () {
      await expect(this.chef.add(10))
        .to.emit(this.chef, "LogPoolAddition")
        .withArgs(0, 10);
    });
  });

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {
      await this.chef.add(10);
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      await time.increaseTo(30000124368);
      await expect(this.chef.updatePool(0))
        .to.emit(this.chef, "LogUpdatePool")
        .withArgs(
          0,
          (
            await this.chef.poolInfo(0)
          ).lastRewardBlock,
          parseUnits("13000", 18),
          (
            await this.chef.poolInfo(0)
          ).accRewardPerShare
        );
    });
  });

  describe("Deposit", function () {
    it("Depositing amount", async function () {
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      await this.chef.add(10);
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("1000", 18)
      );
      await expect(this.chef.depositBatch(0, [1], [parseUnits("100", 18)]))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, 0, 1);
      let liqAmount = (await this.lbPair.getBin(1))[1];
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(
        parseUnits("100", 18)
      );
      expect((await this.chef.userInfo(0, this.alice.address)).amount).to.equal(
        liqAmount
      );
    });

    it("Depositing into non-existent pool should fail", async function () {
      let err;
      try {
        await this.chef.depositBatch(
          1001,
          [getBigNumber(1)],
          [parseUnits("100", 18)]
        );
      } catch (e) {
        err = e;
      }

      assert.equal(
        err.toString(),
        "Error: VM Exception while processing transaction: reverted with panic code 0x32 (Array accessed at an out-of-bounds or negative index)"
      );
    });
  });

  describe("Withdraw", function () {
    it("Withdraw 0 amount", async function () {
      await this.chef.add(10);
      await expect(this.chef.withdrawBatch(0, [0])).to.revertedWith(
        "DexLpFarming: can not withdraw"
      );
    });

    it("Withdraw amount", async function () {
      await this.chef.add(10);
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.mint(owner.address, 2, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setBin(
        2,
        parseUnits("1200", 18),
        parseUnits("1400", 18)
      );
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("2000", 18)
      );
      await expect(
        this.chef.depositBatch(
          0,
          [1, 2],
          [parseUnits("100", 18), parseUnits("100", 18)]
        )
      )
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, 0, 1);

      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(
        parseUnits("100", 18)
      );
      expect(await this.lbPair.balanceOf(owner.address, 2)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 2)).to.equal(
        parseUnits("100", 18)
      );

      await expect(this.chef.withdrawBatch(0, [0, 1]))
        .to.emit(this.chef, "Withdraw")
        .withArgs(owner.address, 0, 1);

      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("1000", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(0);

      expect(await this.lbPair.balanceOf(owner.address, 2)).to.equal(
        parseUnits("1000", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 2)).to.equal(0);
    });
  });

  describe("Harvest", function () {
    it("Should give back the correct amount of rewardToken and reward", async function () {
      await this.chef.add(10);
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      let pricision = await this.chef.ACC_REWARD_PRECISION();
      let log = await this.chef.depositBatch(0, [1], [parseUnits("100", 18)]);
      await time.increaseTo(30000125431);
      let log2 = await this.chef.withdrawBatch(0, [0]);
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = (await this.lbPair.getBin(1))[1];
      let lpSupply = (await this.lbPair.getReserve())[1];

      expectedrewardToken = expectedrewardToken.mul(pricision).div(lpSupply);

      expectedrewardToken = expectedrewardToken.mul(liqAmount).div(pricision);

      expect(
        (await this.chef.userInfo(0, owner.address)).rewardDebt
      ).to.be.equal("-" + expectedrewardToken);

      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await this.chef.harvest(0, this.alice.address);
      let afterBalance = await this.rewardToken.balanceOf(this.alice.address);
      expect(afterBalance).to.be.equal(expectedrewardToken.add(beforeBalance));
    });

    it("Harvest with empty user balance", async function () {
      await this.chef.add(10);
      await this.chef.harvest(0, this.alice.address);
    });

    it("Harvest for rewardToken-only pool", async function () {
      await this.chef.add(10);
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      let pricision = await this.chef.ACC_REWARD_PRECISION();
      let log = await this.chef.depositBatch(0, [1], [parseUnits("100", 18)]);
      await time.increaseTo(30000126431);

      let log2 = await this.chef.withdrawBatch(0, [0]);

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = (await this.lbPair.getBin(1))[1];
      let lpSupply = (await this.lbPair.getReserve())[1];
      expectedrewardToken = expectedrewardToken.mul(pricision).div(lpSupply);
      expectedrewardToken = expectedrewardToken.mul(liqAmount).div(pricision);
      expect(
        (await this.chef.userInfo(0, owner.address)).rewardDebt
      ).to.be.equal("-" + expectedrewardToken);
      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await this.chef.harvest(0, this.alice.address);
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        expectedrewardToken.add(beforeBalance)
      );
    });
  });

  describe("EmergencyWithdraw", function () {
    it("Should emit event EmergencyWithdraw", async function () {
      await this.chef.add(10);
      await this.lbPair.mint(owner.address, 2, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        2,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      await this.chef.depositBatch(0, [2], [parseUnits("100", 18)]);
      await time.increaseTo(30000127431);

      expect(await this.lbPair.balanceOf(owner.address, 2)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 2)).to.equal(
        parseUnits("100", 18)
      );
      let liqAmount = (await this.lbPair.getBin(2))[1];
      await expect(this.chef.emergencyWithdraw(0, owner.address))
        .to.emit(this.chef, "EmergencyWithdraw")
        .withArgs(owner.address, 0, liqAmount, owner.address);
      expect(await this.lbPair.balanceOf(owner.address, 2)).to.equal(
        parseUnits("1000", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 2)).to.equal(0);
    });
  });

  describe("Withdraw and Harvest", function () {
    it("Should transfer and reward and deposited token", async function () {
      await this.chef.add(10);
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      await this.lbPair.approveForAll(this.chef.address, true);
      let log = await this.chef.depositBatch(0, [1], [parseUnits("100", 18)]);
      await time.increaseTo(30000131295);

      let beforeBalance = await this.rewardToken.balanceOf(owner.address);
      expect(await this.rewardToken.balanceOf(this.chef.address)).to.be.equal(
        parseUnits("403", 18)
      );
      let log2 = await this.chef.withdrawAndHarvest(0, [0], owner.address);
      let precision = await this.chef.ACC_REWARD_PRECISION();
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = (await this.lbPair.getBin(1))[1];
      let lpSupply = (await this.lbPair.getReserve())[1];
      expectedrewardToken = expectedrewardToken.mul(precision).div(lpSupply);
      expectedrewardToken = expectedrewardToken.mul(liqAmount).div(precision);

      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        expectedrewardToken.add(beforeBalance)
      );
      expect(await this.rewardToken.balanceOf(this.chef.address)).to.be.equal(
        parseUnits("403", 18).sub(expectedrewardToken)
      );
    });
  });
});
