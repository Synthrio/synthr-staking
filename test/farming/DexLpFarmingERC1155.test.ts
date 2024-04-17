import { expect, assert } from "chai";
import { prepare, deploy, getBigNumber } from "../utilities";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { parseUnits } from "ethers/lib/utils";
import { get } from "http";

describe("DerivedDexLpFarmingERC1155", function () {
  before(async function () {
    await prepare(this, [
      "DerivedDexLpFarmingERC1155",
      "LBPair",
      "MockToken",
      "LibTest",
    ]);
  });

  let owner: any, addr1: any, addr2: any;
  beforeEach(async function () {
    await deploy(this, [["rewardToken", this.MockToken]]);
    await deploy(this, [["lbPair", this.LBPair]]);
    await deploy(this, [["libTest", this.LibTest]]);

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
      parseUnits("403", 18),
      owner.address
    );
  });

  describe("PoolInfo", function () {
    it("Should set pool info", async function () {
      await this.rewardToken.approve(this.chef.address, parseUnits("503", 18));

      let log = await this.chef.setRewardPerBlock(
        "20000000000000000",
        parseUnits("503", 18),
        owner.address
      );

      expect((await this.chef.pool()).lastRewardBlock).to.be.equal(
        log.blockNumber
      );
      expect((await this.chef.pool()).currentEpoch).to.be.equal(2);
      expect((await this.chef.pool()).rewardPerBlock).to.be.equal(
        BigNumber.from("20000000000000000")
      );
    });
  });

  describe("PendingrewardToken", function () {
    it("PendingrewardToken should equal ExpectedrewardToken", async function () {
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("1000", 18)
      );
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(
        parseUnits("100", 18)
      );

      let lastedTime = await time.latest();
      await time.increaseTo(lastedTime + 3000282);
      let log2 = await this.chef.updatePool();

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;

      let rewardAmount = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = (await this.lbPair.getBin(1))[1];
      let lpSupply = (await this.lbPair.getReserves())[1];
      let expectedrewardToken = rewardAmount
        .mul(parseUnits("1", 18))
        .div(lpSupply);

      expectedrewardToken = expectedrewardToken
        .mul(liqAmount)
        .div(parseUnits("1", 18));
      let pendingrewardToken = await this.chef.pendingReward(
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
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      let prevACCPerShare = (await this.chef.pool()).accRewardPerShare;

      let userRewardDebt = parseUnits("1300", 18)
        .mul(prevACCPerShare)
        .div(parseUnits("1", 18));
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(
        parseUnits("100", 18)
      );
      let lastedTime = await time.latest();
      await time.increaseTo(lastedTime + 3000282);
      let accPerShare = (await this.chef.pool()).accRewardPerShare;
      let log2 = await this.chef.updatePool();

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;

      let rewardAmount = BigNumber.from("10000000000000000").mul(
        block2 - block
      );

      let liqAmount = (await this.lbPair.getBin(1))[1];

      let lpSupply = (await this.lbPair.getReserves())[1];

      accPerShare = accPerShare.add(
        rewardAmount.mul(parseUnits("1", 18)).div(lpSupply)
      );

      let expectedrewardToken = accPerShare
        .mul(liqAmount)
        .div(parseUnits("1", 18));

      let pendingrewardToken = await this.chef.pendingReward(
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(
        expectedrewardToken.sub(userRewardDebt)
      );
    });
  });

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      let lastedTime = await time.latest();
      await time.increaseTo(lastedTime + 3000282);
      await expect(this.chef.updatePool())
        .to.emit(this.chef, "LogUpdatePool")
        .withArgs(
          (
            await this.chef.pool()
          ).lastRewardBlock,
          parseUnits("13000", 18),
          (
            await this.chef.pool()
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
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("1000", 18)
      );
      await expect(this.chef.depositBatch([1], [parseUnits("100", 18)]))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, [1]);
      let liqAmount = (await this.lbPair.getBin(1))[1];
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(
        parseUnits("100", 18)
      );
      expect((await this.chef.userInfo(this.alice.address)).amount).to.equal(
        liqAmount
      );
    });

    it("Should update liquidity of user, if deposit again", async function () {
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      let reserveX = (await this.lbPair.getBin(1))[0];
      let reserveY = (await this.lbPair.getBin(1))[1];
      let amountInBin = await this.lbPair.balanceOf(owner.address, 1);
      let binReserves = await this.libTest.encodeTest(reserveX, reserveY);
      let supply = await this.lbPair.totalSupply(1);

      let amountsOutFromBin = await this.libTest.getAmount(
        binReserves,
        amountInBin,
        supply
      );
      let liquidity = (await this.libTest.decodeTest(amountsOutFromBin))[1];
      let pricision = await this.chef.ACC_REWARD_PRECISION();
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);

      expect((await this.chef.userInfo(owner.address)).amount).to.be.equal(
        liquidity
      );

      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1500", 18)
      );

      let lastedTime = await time.latest();
      await time.increaseTo(lastedTime + 3000282);

      let befRewardDebt = (await this.chef.userInfo(owner.address)).rewardDebt;
      let befAcc = (await this.chef.pool()).accRewardPerShare;

      reserveX = (await this.lbPair.getBin(1))[0];
      reserveY = (await this.lbPair.getBin(1))[1];
      amountInBin = await this.lbPair.balanceOf(owner.address, 1);
      binReserves = await this.libTest.encodeTest(reserveX, reserveY);
      supply = await this.lbPair.totalSupply(1);

      amountsOutFromBin = await this.libTest.getAmount(
        binReserves,
        amountInBin,
        supply
      );
      let afterLiquidity = (
        await this.libTest.decodeTest(amountsOutFromBin)
      )[1];
      let log2 = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      expect((await this.chef.userInfo(owner.address)).amount).to.be.equal(
        afterLiquidity
      );

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );

      let lpSupply = (await this.lbPair.getReserves())[1];

      expectedrewardToken = expectedrewardToken
        .mul(pricision)
        .div(lpSupply)
        .add(befAcc);
      expectedrewardToken = expectedrewardToken
        .mul(afterLiquidity.sub(liquidity))
        .div(pricision);

      expect((await this.chef.userInfo(owner.address)).rewardDebt).to.be.equal(
        expectedrewardToken.add(befRewardDebt)
      );
    });

    it("Should return true if token is deposited", async function () {
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("1000", 18)
      );
      await expect(this.chef.depositBatch([1], [parseUnits("100", 18)]))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, [1]);
      let liqAmount = (await this.lbPair.getBin(1))[1];
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("900", 18)
      );
      expect(await this.lbPair.balanceOf(this.chef.address, 1)).to.equal(
        parseUnits("100", 18)
      );
      expect((await this.chef.userInfo(this.alice.address)).amount).to.equal(
        liqAmount
      );
      expect(await this.chef.isTokenDeposited(owner.address, 1)).to.equal(true);
    });
  });

  describe("Withdraw", function () {
    it("Should revert if user not deposit token", async function () {
      await expect(this.chef.withdrawBatch([0])).to.revertedWith(
        "Farming: can not withdraw"
      );
    });

    it("Withdraw amount", async function () {
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
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("2000", 18)
      );
      await expect(
        this.chef.depositBatch(
          [1, 2],
          [parseUnits("100", 18), parseUnits("100", 18)]
        )
      )
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, [1, 2]);

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

      await expect(this.chef.withdrawBatch([2, 1]))
        .to.emit(this.chef, "Withdraw")
        .withArgs(owner.address, [2, 1]);

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
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      let pricision = await this.chef.ACC_REWARD_PRECISION();
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      let befAcc = (await this.chef.pool()).accRewardPerShare;
      let befRewardDebt = (await this.chef.userInfo(owner.address)).rewardDebt;
      let lastedTime = await time.latest();
      await time.increaseTo(lastedTime + 3000282);
      let reserveX = (await this.lbPair.getBin(1))[0];
      let reserveY = (await this.lbPair.getBin(1))[1];
      let amountInBin = await this.lbPair.balanceOf(owner.address, 1);
      let binReserves = await this.libTest.encodeTest(reserveX, reserveY);
      let supply = await this.lbPair.totalSupply(1);

      let amountsOutFromBin = await this.libTest.getAmount(
        binReserves,
        amountInBin,
        supply
      );
      let liqAmount = (await this.libTest.decodeTest(amountsOutFromBin))[1];
      let log2 = await this.chef.withdrawBatch([1]);
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );

      let lpSupply = (await this.lbPair.getReserves())[1];

      expectedrewardToken = expectedrewardToken.mul(pricision).div(lpSupply);
      expectedrewardToken = expectedrewardToken.add(befAcc);
      let pendingReward = expectedrewardToken.mul(liqAmount).div(pricision);
      pendingReward = befRewardDebt.sub(pendingReward);

      expect((await this.chef.userInfo(owner.address)).rewardDebt).to.be.equal(
        pendingReward
      );

      let expectedrewardToken1 = BigNumber.from("10000000000000000");
      expectedrewardToken1 = expectedrewardToken1.mul(pricision).div(lpSupply);
      befRewardDebt = (await this.chef.userInfo(owner.address)).rewardDebt;
      expectedrewardToken1 = expectedrewardToken1.add(expectedrewardToken);
      let pendingReward1 = expectedrewardToken1
        .mul(BigNumber.from("130000000000000000000"))
        .div(pricision);
      pendingReward1 = pendingReward1.sub(befRewardDebt);

      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await expect(this.chef.harvest(this.alice.address))
        .to.emit(this.chef, "Harvest")
        .withArgs(owner.address, pendingReward1);
      let afterBalance = await this.rewardToken.balanceOf(this.alice.address);
      expect(afterBalance).to.be.equal(pendingReward1.add(beforeBalance));
    });

    it("Harvest with empty user balance", async function () {
      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await this.chef.harvest(this.alice.address);
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.equal(
        beforeBalance
      );
    });

    it("Harvest for rewardToken-only pool", async function () {
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.approveForAll(this.chef.address, true);
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      let pricision = await this.chef.ACC_REWARD_PRECISION();
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      let befAcc = (await this.chef.pool()).accRewardPerShare;
      let befRewardDebt = (await this.chef.userInfo(owner.address)).rewardDebt;
      let lastedTime = await time.latest();
      await time.increaseTo(lastedTime + 3000282);
      let reserveX = (await this.lbPair.getBin(1))[0];
      let reserveY = (await this.lbPair.getBin(1))[1];
      let amountInBin = await this.lbPair.balanceOf(owner.address, 1);
      let binReserves = await this.libTest.encodeTest(reserveX, reserveY);
      let supply = await this.lbPair.totalSupply(1);

      let amountsOutFromBin = await this.libTest.getAmount(
        binReserves,
        amountInBin,
        supply
      );
      let liqAmount = (await this.libTest.decodeTest(amountsOutFromBin))[1];
      let log2 = await this.chef.withdrawBatch([1]);
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );

      let lpSupply = (await this.lbPair.getReserves())[1];

      expectedrewardToken = expectedrewardToken.mul(pricision).div(lpSupply);
      expectedrewardToken = expectedrewardToken.add(befAcc);
      let pendingReward = expectedrewardToken.mul(liqAmount).div(pricision);
      pendingReward = befRewardDebt.sub(pendingReward);

      expect((await this.chef.userInfo(owner.address)).rewardDebt).to.be.equal(
        pendingReward
      );
      let expectedrewardToken1 = BigNumber.from("10000000000000000");
      let liq = (await this.chef.userInfo(owner.address)).amount;
      expectedrewardToken1 = expectedrewardToken1.mul(pricision).div(lpSupply);
      befRewardDebt = (await this.chef.userInfo(owner.address)).rewardDebt;
      expectedrewardToken1 = expectedrewardToken1.add(expectedrewardToken);
      let pendingReward1 = expectedrewardToken1
        .mul(BigNumber.from("130000000000000000000"))
        .div(pricision);
      pendingReward1 = pendingReward1.sub(befRewardDebt);

      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await expect(this.chef.harvest(this.alice.address))
        .to.emit(this.chef, "Harvest")
        .withArgs(owner.address, pendingReward1);
      let afterBalance = await this.rewardToken.balanceOf(this.alice.address);
      expect(afterBalance).to.be.equal(pendingReward1.add(beforeBalance));
    });
  });

  describe("Withdraw and Harvest", function () {
    it("Should transfer and reward and deposited token", async function () {
      await this.lbPair.mint(owner.address, 1, parseUnits("1000", 18));
      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1300", 18)
      );
      await this.lbPair.setReserves(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      await this.lbPair.approveForAll(this.chef.address, true);
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      let lastedTime = await time.latest();
      await time.increaseTo(lastedTime + 3000282);

      let beforeBalance = await this.rewardToken.balanceOf(owner.address);
      expect(await this.rewardToken.balanceOf(this.chef.address)).to.be.equal(
        parseUnits("403", 18)
      );
      let log2 = await this.chef.withdrawAndHarvest([1], owner.address);
      expect(log2)
        .to.emit(this.chef, "withdrawAndHarvest")
        .withArgs(owner.address, [getBigNumber(1)]);

      let precision = await this.chef.ACC_REWARD_PRECISION();
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = (await this.lbPair.getBin(1))[1];
      let lpSupply = (await this.lbPair.getReserves())[1];
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
