import { expect, assert } from "chai";
import { prepare, deploy, getBigNumber } from "../utilities";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { parseUnits } from "ethers/lib/utils";

describe("DerivedDexLpFarming", function () {
  before(async function () {
    await prepare(this, [
      "DerivedDexLpFarming",
      "MockToken",
      "NonfungiblePositionManager",
    ]);
  });

  let owner: any, addr1: any, addr2: any;
  beforeEach(async function () {
    await deploy(this, [["rewardToken", this.MockToken]]);
    await deploy(this, [["tokenTracker", this.NonfungiblePositionManager]]);
    await deploy(this, [["nativeToken", this.MockToken]]);

    [owner, addr1, addr2] = await ethers.getSigners();
    await deploy(this, [
      [
        "chef",
        this.DerivedDexLpFarming,
        [
          this.rewardToken.address,
          this.tokenTracker.address,
          addr1.address,
          this.nativeToken.address,
        ],
      ],
    ]);

    await this.rewardToken.mint(
      owner.address,
      parseUnits("100000000000000000000000000000000000", 18)
    );
    await this.tokenTracker.safeMint(owner.address, getBigNumber(1));
    await this.rewardToken.approve(this.chef.address, parseUnits("403", 18));
    await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
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
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000000282);

      let log2 = await this.chef.updatePool(0);

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;

      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = await this.tokenTracker.positions(getBigNumber(1));
      let lpSupply = await this.nativeToken.balanceOf(addr1.address);
      expectedrewardToken = expectedrewardToken
        .mul(parseUnits("1", 18))
        .div(lpSupply);
      expectedrewardToken = expectedrewardToken
        .mul(liqAmount.liquidity)
        .div(parseUnits("1", 18));
      let pendingrewardToken = await this.chef.pendingReward(
        0,
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(expectedrewardToken);
    });
    it("When time is lastRewardTime", async function () {
      await this.chef.add(10);
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000001280);
      let log2 = await this.chef.updatePool(0);
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = await this.tokenTracker.positions(getBigNumber(1));
      let lpSupply = await this.nativeToken.balanceOf(addr1.address);
      expectedrewardToken = expectedrewardToken
        .mul(parseUnits("1", 18))
        .div(lpSupply);
      expectedrewardToken = expectedrewardToken
        .mul(liqAmount.liquidity)
        .div(parseUnits("1", 18));
      let pendingrewardToken = await this.chef.pendingReward(
        0,
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(expectedrewardToken);
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
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      let lpSupply = await this.nativeToken.balanceOf(addr1.address);
      await time.increaseTo(30000011280);
      await expect(this.chef.updatePool(0))
        .to.emit(this.chef, "LogUpdatePool")
        .withArgs(
          0,
          (
            await this.chef.poolInfo(0)
          ).lastRewardBlock,
          lpSupply,
          (
            await this.chef.poolInfo(0)
          ).accRewardPerShare
        );
    });
  });

  describe("Deposit", function () {
    it("Depositing amount", async function () {
      await this.chef.add(10);
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        owner.address
      );
      await expect(this.chef.deposit(0, getBigNumber(1)))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, 0, getBigNumber(1));
      let liqAmount = await this.tokenTracker.positions(getBigNumber(1));
      expect((await this.chef.userInfo(0, this.alice.address)).amount).to.equal(
        liqAmount.liquidity
      );
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        this.chef.address
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
      await this.chef.add(10);
      await expect(this.chef.withdraw(0, getBigNumber(1))).to.revertedWith(
        "DexLpFarming: can not withdraw"
      );
    });

    it("Withdraw amount", async function () {
      await this.chef.add(10);
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        owner.address
      );
      await expect(this.chef.deposit(0, getBigNumber(1)))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, 0, getBigNumber(1));

      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        this.chef.address
      );
      await expect(this.chef.withdraw(0, getBigNumber(1)))
        .to.emit(this.chef, "Withdraw")
        .withArgs(owner.address, 0, getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        owner.address
      );
    });
  });

  describe("Harvest", function () {
    it("Should give back the correct amount of rewardToken and reward", async function () {
      await this.chef.add(10);
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000021280);

      let precision = await this.chef.ACC_REWARD_PRECISION();
      let log2 = await this.chef.withdraw(0, getBigNumber(1));
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = await this.tokenTracker.positions(getBigNumber(1));
      let lpSupply = await this.nativeToken.balanceOf(addr1.address);
      expectedrewardToken = expectedrewardToken.mul(precision).div(lpSupply);

      expectedrewardToken = expectedrewardToken
        .mul(liqAmount.liquidity)
        .div(precision);
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
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000121280);
      let log2 = await this.chef.withdraw(0, getBigNumber(1));
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = await this.tokenTracker.positions(getBigNumber(1));
      let lpSupply = await this.nativeToken.balanceOf(addr1.address);
      expectedrewardToken = expectedrewardToken
        .mul(parseUnits("1", 18))
        .div(lpSupply);
      expectedrewardToken = expectedrewardToken
        .mul(liqAmount.liquidity)
        .div(parseUnits("1", 18));
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
      await this.tokenTracker.safeMint(owner.address, getBigNumber(2));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(2));
      await this.chef.deposit(0, getBigNumber(2));
      expect(await this.tokenTracker.balanceOf(owner.address)).to.equal(1);
      expect(await this.tokenTracker.ownerOf(getBigNumber(2))).to.equal(
        this.chef.address
      );
      let liqAmount = await this.tokenTracker.positions(getBigNumber(2));
      //await this.chef.emergencyWithdraw(0, this.alice.address)
      await expect(this.chef.emergencyWithdraw(0, owner.address))
        .to.emit(this.chef, "EmergencyWithdraw")
        .withArgs(owner.address, 0, liqAmount.liquidity, owner.address);
      expect(await this.tokenTracker.balanceOf(owner.address)).to.equal(2);
      expect(await this.tokenTracker.ownerOf(getBigNumber(2))).to.equal(
        owner.address
      );
    });
  });

  describe("Withdraw and Harvest", function () {
    it("Should transfer and reward and deposited token", async function () {
      await this.chef.add(10);
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      let log = await this.chef.deposit(0, getBigNumber(1));
      await time.increaseTo(30000121310);

      let beforeBalance = await this.rewardToken.balanceOf(owner.address);
      expect(await this.rewardToken.balanceOf(this.chef.address)).to.be.equal(
        parseUnits("403", 18)
      );
      let log2 = await this.chef.withdrawAndHarvest(
        0,
        getBigNumber(1),
        owner.address
      );

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = await this.tokenTracker.positions(getBigNumber(1));
      let lpSupply = await this.nativeToken.balanceOf(addr1.address);
      expectedrewardToken = expectedrewardToken
        .mul(parseUnits("1", 18))
        .div(lpSupply);
      expectedrewardToken = expectedrewardToken
        .mul(liqAmount.liquidity)
        .div(parseUnits("1", 18));

      expect(await this.rewardToken.balanceOf(owner.address)).to.be.equal(
        expectedrewardToken.add(beforeBalance)
      );
      expect(await this.rewardToken.balanceOf(this.chef.address)).to.be.equal(
        parseUnits("403", 18).sub(expectedrewardToken)
      );
    });
  });
});
