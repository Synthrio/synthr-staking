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

      await time.increaseTo(30000122335);
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
      await time.increaseTo(30000123348);
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
      await time.increaseTo(30000124368);
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

      let pricision = await this.chef.ACC_REWARD_PRECISION();
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      expect((await this.chef.userInfo(owner.address)).amount).to.be.equal(
        parseUnits("1300", 18)
      );

      await this.lbPair.setBin(
        1,
        parseUnits("1200", 18),
        parseUnits("1500", 18)
      );

      await time.increaseTo(30000125431);

      let befRewardDebt = (await this.chef.userInfo(owner.address)).rewardDebt;
      let befAcc = (await this.chef.pool()).accRewardPerShare;
      let log2 = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      expect((await this.chef.userInfo(owner.address)).amount).to.be.equal(
        parseUnits("1500", 18)
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
        .mul(parseUnits("200", 18))
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
      let x = await time.latest();
      await time.increaseTo(x + 10);
      let log2 = await this.chef.withdrawBatch([1]);
      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = (await this.lbPair.getBin(1))[1];
      let lpSupply = (await this.lbPair.getReserves())[1];

      expectedrewardToken = expectedrewardToken.mul(pricision).div(lpSupply);

      expectedrewardToken = expectedrewardToken.mul(liqAmount).div(pricision);

      expect((await this.chef.userInfo(owner.address)).rewardDebt).to.be.equal(
        "-" + expectedrewardToken
      );

      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await expect(this.chef.harvest(this.alice.address))
        .to.emit(this.chef, "Harvest")
        .withArgs(owner.address, expectedrewardToken);
      let afterBalance = await this.rewardToken.balanceOf(this.alice.address);
      expect(afterBalance).to.be.equal(expectedrewardToken.add(beforeBalance));
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
      await time.increaseTo(30000126431);

      let log2 = await this.chef.withdrawBatch([1]);

      let block2 = (await ethers.provider.getBlock(log2.blockNumber)).number;
      let block = (await ethers.provider.getBlock(log.blockNumber)).number;
      let expectedrewardToken = BigNumber.from("10000000000000000").mul(
        block2 - block
      );
      let liqAmount = (await this.lbPair.getBin(1))[1];
      let lpSupply = (await this.lbPair.getReserves())[1];
      expectedrewardToken = expectedrewardToken.mul(pricision).div(lpSupply);
      expectedrewardToken = expectedrewardToken.mul(liqAmount).div(pricision);
      expect((await this.chef.userInfo(owner.address)).rewardDebt).to.be.equal(
        "-" + expectedrewardToken
      );
      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await this.chef.harvest(this.alice.address);
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.equal(
        expectedrewardToken.add(beforeBalance)
      );
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
      await time.increaseTo(30000131295);

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
