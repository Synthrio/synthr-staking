import { expect, assert } from "chai";
import { prepare, deploy, getBigNumber } from "../utilities";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { parseUnits } from "ethers/lib/utils";

describe("DexLpFarming", function () {
  before(async function () {
    await prepare(this, ["DexLpFarming", "MockToken", "LpToken"]);
  });

  let owner: any;
  beforeEach(async function () {
    await deploy(this, [["rewardToken", this.MockToken]]);

    await deploy(this, [
      ["lp", this.LpToken, []],
      ["dummy", this.MockToken, []],
      ["chef", this.DexLpFarming, [this.rewardToken.address]],
    ]);

    [owner] = await ethers.getSigners();
    await this.rewardToken.mint(
      owner.address,
      parseUnits("100000000000000000000000000000000000", 18)
    );
    await this.lp.safeMint(owner.address, getBigNumber(1));
    await this.rewardToken.approve(this.chef.address, parseUnits("403", 18));
    await this.lp.approve(this.chef.address, getBigNumber(1));
    await this.chef.setRewardPerBlock("10000000000000000", owner.address, parseUnits("403", 18));
  });

  describe("PoolLength", function () {
    it("PoolLength should execute", async function () {
      await this.chef.add(10, this.lp.address);
      expect(await this.chef.poolLength()).to.be.equal(1);
    });
  });

  describe("Set", function () {
    it("Should emit event LogSetPool", async function () {
      await this.chef.add(10, this.lp.address);
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
      await this.chef.add(10, this.lp.address);
      await this.lp.approve(this.chef.address, getBigNumber(1));
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000000279);
      let log2 = await this.chef.updatePool(0);
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let pendingrewardToken = await this.chef.pendingReward(
        0,
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(expectedrewardToken);
    });
    it("When time is lastRewardTime", async function () {
      await this.chef.add(10, this.lp.address);
      await this.lp.approve(this.chef.address, getBigNumber(1));
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000001280);
      let log2 = await this.chef.updatePool(0);
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let pendingrewardToken = await this.chef.pendingReward(
        0,
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(expectedrewardToken);
    });
  });

  describe("Add", function () {
    it("Should add pool with reward token multiplier", async function () {
      await expect(this.chef.add(10, this.lp.address))
        .to.emit(this.chef, "LogPoolAddition")
        .withArgs(0, 10, this.lp.address);
    });
  });

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {
      await this.chef.add(10, this.lp.address);
      await time.increaseTo(30000011280);
      await expect(this.chef.updatePool(0))
        .to.emit(this.chef, "LogUpdatePool")
        .withArgs(
          0,
          (
            await this.chef.poolInfo(0)
          ).lastRewardBlock,
          await this.lp.balanceOf(this.chef.address),
          (
            await this.chef.poolInfo(0)
          ).accRewardPerShare
        );
    });
  });

  describe("Deposit", function () {
    it("Depositing 0 amount", async function () {
      await this.chef.add(10, this.lp.address);
      await this.lp.approve(this.chef.address, getBigNumber(1));
      await expect(this.chef.deposit(0, getBigNumber(1)))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, 0, getBigNumber(1));
      expect((await this.chef.userInfo(0, this.alice.address)).amount).to.equal(
        1
      );
    });

    it("Depositing into non-existent pool should fail", async function () {
      let err;
      try {
        await this.chef.deposit(1001, getBigNumber(0));
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
      await this.chef.add(10, this.lp.address);
      await expect(this.chef.withdraw(0, getBigNumber(1))).to.revertedWith(
        "DexLpFarming: can not withdraw"
      );
    });
  });

  describe("Harvest", function () {
    it("Should give back the correct amount of rewardToken and reward", async function () {
      await this.chef.add(10, this.lp.address);
      await this.lp.approve(this.chef.address, getBigNumber(1));
      expect(await this.chef.lpToken(0)).to.be.equal(this.lp.address);
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000021280);
      let log2 = await this.chef.withdraw(0, getBigNumber(1));
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      console.log(expectedrewardToken);
      expect(
        (await this.chef.userInfo(0, owner.address)).rewardDebt
        ).to.be.equal("-" + expectedrewardToken);
        let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
        await this.chef.harvest(0, this.alice.address);
        let afterBalance = await this.rewardToken.balanceOf(this.alice.address);
      expect(afterBalance).to.be.equal(
        expectedrewardToken.add(beforeBalance)
      );
    });
    it("Harvest with empty user balance", async function () {
      await this.chef.add(10, this.lp.address);
      await this.chef.harvest(0, this.alice.address);
    });

    it("Harvest for rewardToken-only pool", async function () {
      await this.chef.add(10, this.lp.address);
      await this.lp.approve(this.chef.address, getBigNumber(1));
      expect(await this.chef.lpToken(0)).to.be.equal(this.lp.address);
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000121280);
      let log2 = await this.chef.withdraw(0, getBigNumber(1));
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
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
      await this.chef.add(10, this.lp.address);
      await this.lp.safeMint(owner.address, getBigNumber(2));
      await this.lp.approve(this.chef.address, getBigNumber(2));
      await this.chef.deposit(0, getBigNumber(2));
      //await this.chef.emergencyWithdraw(0, this.alice.address)
      await expect(this.chef.emergencyWithdraw(0, owner.address))
        .to.emit(this.chef, "EmergencyWithdraw")
        .withArgs(owner.address, 0, 1, owner.address);
    });
  });
});
