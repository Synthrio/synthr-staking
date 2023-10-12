import { expect, assert } from "chai";
import { prepare, deploy, getBigNumber } from "../utilities";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { parseUnits, parseEther } from "ethers/lib/utils";
import { get } from "http";

describe("DerivedDexLpFarmingERC1155", function () {
  before(async function () {
    await prepare(this, ["DerivedDexLpFarmingERC1155", "LBPair", "MockToken", "LZEndpointMock1","LZEndpointMock1",
    "CrossClaim"]);
  });

  let owner: any, addr1: any, addr2: any;
  let srcChainId = 1;
  let dstChainId = 2;
  beforeEach(async function () {
    await deploy(this, [["rewardToken", this.MockToken]]);
    await deploy(this, [["lbPair", this.LBPair]]);
    await deploy(this, [["lzEndPoint", this.LZEndpointMock1,[srcChainId]]]);
    await deploy(this, [["lzEndPointDst", this.LZEndpointMock1,[dstChainId]]]);
    await deploy(this, [["crossClaim", this.CrossClaim,[this.lzEndPointDst.address]]]);

    [owner, addr1, addr2] = await ethers.getSigners();
    await deploy(this, [
      [
        "chef",
        this.DerivedDexLpFarmingERC1155,
        [this.rewardToken.address, this.lbPair.address, this.lzEndPoint.address],
      ],
    ]);

    let mockEstimatedNativeFee = parseEther("0.001");
        let mockEstimatedZroFee = parseEther("0.00025");
        await this.lzEndPoint.setEstimatedFees(mockEstimatedNativeFee,  mockEstimatedZroFee);
        await this.lzEndPointDst.setEstimatedFees( mockEstimatedNativeFee,  mockEstimatedZroFee);
        await this.chef.setDstChainId( dstChainId);
        await this.chef.setTrustedRemote( dstChainId, this.crossClaim.address);
        await this.chef.setMinDstGas(dstChainId, 1 , parseUnits("1",18));
        await this.crossClaim.setTrustedRemote( srcChainId, this.chef.address);
        await this.lzEndPoint.setDestLzEndpoint( this.crossClaim.address,  this.lzEndPointDst.address);
        await this.lzEndPointDst.setDestLzEndpoint( this.chef.address,  this.lzEndPoint.address);

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
      expect((await this.chef.pool()).lastRewardBlock).to.be.equal(0);
      expect((await this.chef.pool()).currentEpoch).to.be.equal(1);
      expect((await this.chef.pool()).rewardPerBlock).to.be.equal(BigNumber.from("10000000000000000"));
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
      await this.lbPair.setReserve(
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
      let lpSupply = (await this.lbPair.getReserve())[1];
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
      await this.lbPair.setReserve(
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

      let lpSupply = (await this.lbPair.getReserve())[1];

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
      await this.lbPair.setReserve(
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
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );
      expect(await this.lbPair.balanceOf(owner.address, 1)).to.equal(
        parseUnits("1000", 18)
      );
      await expect(this.chef.depositBatch([1], [parseUnits("100", 18)]))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, 1);
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

    it("Should return true if token is deposited", async function () {
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
      await expect(this.chef.depositBatch([1], [parseUnits("100", 18)]))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, 1);
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
      await this.lbPair.setReserve(
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
        .withArgs(owner.address, 1);

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
        .withArgs(owner.address, 1);

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
      await this.lbPair.setReserve(
        parseUnits("12000", 18),
        parseUnits("13000", 18)
      );

      let pricision = await this.chef.ACC_REWARD_PRECISION();
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      await time.increaseTo(30000125431);
      let log2 = await this.chef.withdrawBatch([1]);
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
        (await this.chef.userInfo(owner.address)).rewardDebt
      ).to.be.equal("-" + expectedrewardToken);

      await this.chef.harvest(this.alice.address,{value: parseEther("0.1")});
      expect(await this.crossClaim.balanceOf(owner.address)).to.equal(expectedrewardToken);
    });

    it("Harvest with empty user balance", async function () {
      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await this.chef.harvest(this.alice.address,{value: parseEther("0.1")});
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.equal(beforeBalance);
    });

    it("Harvest for rewardToken-only pool", async function () {
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
      let log = await this.chef.depositBatch([1], [parseUnits("100", 18)]);
      await time.increaseTo(30000126431);

      let log2 = await this.chef.withdrawBatch([1]);

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
        (await this.chef.userInfo(owner.address)).rewardDebt
      ).to.be.equal("-" + expectedrewardToken);
      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await this.chef.harvest(this.alice.address,{value: parseEther("0.1")});
      expect(await this.crossClaim.balanceOf(owner.address)).to.equal(expectedrewardToken);

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
      await this.lbPair.setReserve(
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
      let log2 = await this.chef.withdrawAndHarvest([1], owner.address,{value: parseEther("0.1")});
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

      expect(await this.crossClaim.balanceOf(owner.address)).to.equal(expectedrewardToken);

      expect(log2).to.emit(this.chef, "WithdrawAndHarvest")
        .withArgs(
          owner.address,
          getBigNumber(1),
          expectedrewardToken
        );

    });
  });
});
