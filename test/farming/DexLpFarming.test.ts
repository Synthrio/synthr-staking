import { expect, assert } from "chai";
import { prepare, deploy, getBigNumber } from "../utilities";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { parseUnits, parseEther } from "ethers/lib/utils";
import { get } from "http";


describe("DerivedDexLpFarming", function () {
  before(async function () {
    await prepare(this, [
      "DerivedDexLpFarming",
      "MockToken",
      "NonfungiblePositionManager",
      "LZEndpointMock1",
      "LZEndpointMock1",
      "CrossClaim"
    ]);
  });
  
  let owner: any, addr1: any, addr2: any;
  let srcChainId = 1;
  let dstChainId = 2;
  beforeEach(async function () {
    await deploy(this, [["rewardToken", this.MockToken]]);
    await deploy(this, [["tokenTracker",  this.NonfungiblePositionManager]]);
    await deploy(this, [["nativeToken", this.MockToken]]);
    await deploy(this, [["lzEndPoint", this.LZEndpointMock1,[srcChainId]]]);
    await deploy(this, [["lzEndPointDst", this.LZEndpointMock1,[dstChainId]]]);
    await deploy(this, [["crossClaim", this.CrossClaim,[this.lzEndPointDst.address]]]);
    
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
          this.lzEndPoint.address
        ],
      ],
    ]);

      let mockEstimatedNativeFee = ethers.utils.parseEther("0.001");
      let mockEstimatedZroFee = ethers.utils.parseEther("0.00025");
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
    await this.tokenTracker.safeMint(owner.address, getBigNumber(1));
    await this.rewardToken.approve(this.chef.address, parseUnits("403", 18));
    await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
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
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      let log = await this.chef.deposit(getBigNumber(1));
      await time.increaseTo(30000000282);

      let log2 = await this.chef.updatePool();

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
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(expectedrewardToken);
    });

    it("When time is lastRewardTime", async function () {
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));

      let log = await this.chef.deposit(getBigNumber(1));
      await time.increaseTo(30000001280);
      let log2 = await this.chef.updatePool();
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
        this.alice.address
      );
      expect(pendingrewardToken).to.be.equal(expectedrewardToken);
    });
  });

  describe("UpdatePool", function () {
    it("Should emit event LogUpdatePool", async function () {
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      let lpSupply = await this.nativeToken.balanceOf(addr1.address);
      await time.increaseTo(30000011280);
      await expect(this.chef.updatePool())
        .to.emit(this.chef, "LogUpdatePool")
        .withArgs(
          (
            await this.chef.pool()
          ).lastRewardBlock,
          lpSupply,
          (
            await this.chef.pool()
          ).accRewardPerShare
        );
    });
  });

  describe("Deposit", function () {
    it("Depositing amount", async function () {
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        owner.address
      );
      await expect(this.chef.deposit(getBigNumber(1)))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, getBigNumber(1));
      let liqAmount = await this.tokenTracker.positions(getBigNumber(1));
      expect((await this.chef.userInfo(this.alice.address)).amount).to.equal(
        liqAmount.liquidity
      );
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        this.chef.address
      );
    });

    it("Should return true if token is deposited", async function () {
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        owner.address
      );
      await expect(this.chef.deposit(getBigNumber(1)))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, getBigNumber(1));
      let liqAmount = await this.tokenTracker.positions(getBigNumber(1));
      expect((await this.chef.userInfo(this.alice.address)).amount).to.equal(
        liqAmount.liquidity
      );
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        this.chef.address
      );

      expect(await this.chef.isTokenDeposited(owner.address, getBigNumber(1))).to.equal(true);
    });

  });

  describe("Withdraw", function () {
    it("Should revert if user not deposit token", async function () {
      await expect(this.chef.withdraw(getBigNumber(1))).to.revertedWith(
        "Farming: can not withdraw"
      );
    });

    it("Withdraw amount", async function () {
      let aa:any = [];
      aa.push(getBigNumber(1));
      for(let i = 1; i < 6; i++) {
        await this.tokenTracker.safeMint(owner.address, getBigNumber(i + 1));
        await this.tokenTracker.approve(this.chef.address, getBigNumber(i + 1));
        expect(await this.tokenTracker.ownerOf(getBigNumber(i + 1))).to.equal(
          owner.address
        );
        aa.push(getBigNumber(i + 1))
      }

      await expect(this.chef.depositBatch(aa))
        .to.emit(this.chef, "Deposit")
        .withArgs(owner.address, getBigNumber(1));

      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        this.chef.address
      );
      expect(await this.tokenTracker.ownerOf(getBigNumber(4))).to.equal(
        this.chef.address
      );

      await expect(this.chef.withdrawBatch([getBigNumber(1),getBigNumber(6)]))
        .to.emit(this.chef, "Withdraw")
        .withArgs(owner.address, getBigNumber(1));

      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        owner.address
      );
      expect(await this.tokenTracker.ownerOf(getBigNumber(6))).to.equal(
        owner.address
      );
    });
  });

  describe("Harvest", function () {
    it("Should give back the correct amount of rewardToken and reward", async function () {
      
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      let log = await this.chef.deposit(getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        this.chef.address
      );
      await time.increaseTo(30000021280);

      let precision = await this.chef.ACC_REWARD_PRECISION();
      let log2 = await this.chef.withdraw(getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        owner.address
      );
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
        (await this.chef.userInfo(owner.address)).rewardDebt
      ).to.be.equal("-" + expectedrewardToken);
      await this.chef.harvest(this.alice.address,{value: parseEther("0.1")});
      expect(await this.crossClaim.balanceOf(owner.address)).to.equal(expectedrewardToken);
    });
    it("Harvest with empty user balance", async function () {
      
      let beforeBalance = await this.rewardToken.balanceOf(this.alice.address);
      await this.chef.harvest(this.alice.address, {value: parseEther("0.1")});
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.equal(beforeBalance);
    });

    it("Harvest for rewardToken-only pool", async function () {
      
      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        owner.address
      );
      let log = await this.chef.deposit(getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
        this.chef.address
      );
      await time.increaseTo(30000121280);
      let log2 = await this.chef.withdraw(getBigNumber(1));
      expect(await this.tokenTracker.ownerOf(getBigNumber(1))).to.equal(
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
          await this.chef.harvest(this.alice.address,{value: parseEther("0.1")});
          expect(await this.crossClaim.balanceOf(owner.address)).to.equal(expectedrewardToken);
    });
  });

  describe("Withdraw and Harvest", function () {
    it("Should transfer and reward and deposited token", async function () {

      this.nativeToken.mint(addr1.address, parseUnits("10000", 18));
      await this.tokenTracker.approve(this.chef.address, getBigNumber(1));
      let log = await this.chef.deposit(getBigNumber(1));
      await time.increaseTo(30000121310);

      let beforeBalance = await this.rewardToken.balanceOf(owner.address);
      expect(await this.rewardToken.balanceOf(this.chef.address)).to.be.equal(
        parseUnits("403", 18)
      );
      let log2 = await this.chef.withdrawAndHarvest(getBigNumber(1), owner.address, {value: parseEther("0.101")})

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
