import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { notDeepEqual } from "assert";
import exp from "constants";

interface RewardInfo {
  token: string;
  rewardPerBlock: BigNumber;
  accRewardPerShare: number;
}

let owner: any,
  addr1: any,
  addr2: any,
  Alice: any,
  Bob: any,
  Joy: any,
  Roy: any,
  Matt: any;
let nftStaking: any, rewardToken: any;

let syCHAD: any, syBULL: any, syHODL: any, syDIAMOND: any, syMAXI: any;
let pools: any;
let totalLockAmount: any;

let gaugeController: any, votingEscrow: any, lpTtoken: any;
async function setUp() {
  // Contracts are deployed using the first signer/account by default
  [owner, addr1, addr2, Alice, Bob, Joy, Roy, Matt] = await ethers.getSigners();
  const RewardToken = await ethers.getContractFactory("MockToken");
  rewardToken = await RewardToken.deploy();

  const LpTtoken = await ethers.getContractFactory("MockToken");
  lpTtoken = await LpTtoken.deploy();

  await lpTtoken.mint(addr1.address, parseUnits("100000", 18));
  await lpTtoken.mint(
    addr2.address,
    parseUnits("100000000000000000000000", 18)
  );

  await rewardToken.mint(
    addr2.address,
    parseUnits("10000000000000000000000", 18)
  );

  const GaugeController = await ethers.getContractFactory("GaugeController");
  gaugeController = await GaugeController.deploy(owner.address);

  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  votingEscrow = await VotingEscrow.deploy(
    lpTtoken.address,
    "vot",
    "vt",
    "v.0.1"
  );

  const NFTStaking = await ethers.getContractFactory("NftStaking");
  nftStaking = await NFTStaking.deploy(
    owner.address,
    rewardToken.address,
    votingEscrow.address
  );
  let pauseRole = await nftStaking.PAUSE_ROLE();
  await nftStaking.grantRole(pauseRole, owner.address);

  const SynthrNFT = await ethers.getContractFactory("SynthrNFT");
  syCHAD = await SynthrNFT.deploy("syCHAD", "syCHAD", owner.address);
  syBULL = await SynthrNFT.deploy("syBULL", "syBULL", owner.address);
  syHODL = await SynthrNFT.deploy("syHODL", "syHODL", owner.address);
  syDIAMOND = await SynthrNFT.deploy("syDIAMOND", "syDIAMOND", owner.address);
  syMAXI = await SynthrNFT.deploy("syMAXI", "syMAXI", owner.address);

  pools = [
    syCHAD.address,
    syBULL.address,
    syHODL.address,
    syDIAMOND.address,
    syMAXI.address,
  ];

  await rewardToken.mint(owner.address, parseUnits("1000000000", 18));

}

async function mintNFTsToLpProviders() {
  const lpAmount = {
    Alice: ethers.utils.parseEther("100"), // 100 * 10^18
    Bob: ethers.utils.parseEther("2000"),
    Joy: ethers.utils.parseEther("30000"),
    Roy: ethers.utils.parseEther("400000"),
  };
  let times = await time.latestBlock();

  await syCHAD
    .connect(owner)
    .safeMint(Alice.address);
  await syCHAD.connect(owner).safeMint(Roy.address);
  await syBULL
    .connect(owner)
    .safeMint(Bob.address);
  await syHODL
    .connect(owner)
    .safeMint(Joy.address);
  await syDIAMOND
    .connect(owner)
    .safeMint(Roy.address);
  return lpAmount.Alice.add(
    lpAmount.Bob.add(lpAmount.Joy.add(lpAmount.Roy.mul(2)))
  ); //sum of above lpAmount.user
}

async function addPoolFunc() {
  let tx = await nftStaking.addPool(pools);
  await rewardToken
    .connect(owner)
    .approve(nftStaking.address, ethers.utils.parseEther("100000"));
  let tx1 = await nftStaking.updateEpoch(
    owner.address,
    ethers.utils.parseEther("100000"),
    pools,
    [1000, 1000, 1000, 1000, 1000]
  );
  return [tx, tx1];
}

async function approveNFT() {
  await syCHAD.connect(Alice).approve(nftStaking.address, 1);
  await syCHAD.connect(Roy).approve(nftStaking.address, 2);
  await syBULL.connect(Bob).approve(nftStaking.address, 1);
  await syHODL.connect(Joy).approve(nftStaking.address, 1);
  await syDIAMOND.connect(Roy).approve(nftStaking.address, 1);
  expect(await syCHAD.getApproved(1)).to.equal(nftStaking.address);
  expect(await syBULL.getApproved(1)).to.equal(nftStaking.address);
  expect(await syHODL.getApproved(1)).to.equal(nftStaking.address);
  expect(await syDIAMOND.getApproved(1)).to.equal(nftStaking.address);
}

async function depositNfts() {
  await createLockTx(Alice);
  await createLockTx(Roy);
  await createLockTx(Joy);
  await createLockTx(Bob);

  let tx1 = await nftStaking.connect(Alice).deposit(syCHAD.address, 1);
  let tx5 = await nftStaking.connect(Roy).deposit(syCHAD.address, 2);
  let tx2 = await nftStaking.connect(Bob).deposit(syBULL.address, 1);
  let tx3 = await nftStaking.connect(Joy).deposit(syHODL.address, 1);
  let tx4 = await nftStaking.connect(Roy).deposit(syDIAMOND.address, 1);
  return [tx1, tx2, tx3, tx4, tx5];
}

async function pauseUser() {
  let tx = await nftStaking.pauseUserReward(syCHAD.address, [
    Roy.address,
    Alice.address,
  ]);
  return tx;
}

async function createLockTx(user:any) {
  await lpTtoken.mint(
    user.address,
    parseUnits("100000000000000000000000", 18)
  );

  await lpTtoken
    .connect(user)
    .approve(votingEscrow.address, parseUnits("10000", 18));
  const blockNum = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  const timestamp = block.timestamp;
  await votingEscrow
    .connect(user)
    .createLock(parseUnits("10000", 18), timestamp + 1000000);
}

async function unpauesTx() {

  await votingEscrow
    .connect(Alice)
    .withdraw();

  await lpTtoken.mint(
    Alice.address,
    parseUnits("100000000000000000000000", 18)
  );

  await lpTtoken
    .connect(Alice)
    .approve(votingEscrow.address, parseUnits("1000", 18));
  const blockNum = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  const timestamp = block.timestamp;
  await votingEscrow
    .connect(Alice)
    .createLock(parseUnits("1000", 18), timestamp + 1000000);

  let tx = await nftStaking.connect(Alice).unpauseReward(syCHAD.address);

  return tx;
}

function calAccRewardPerShare(
  _accRewardPerShare: BigNumber,
  _amount: BigNumber
): BigNumber {
  const ACC_REWARD_PRECISION: BigNumber = ethers.utils.parseEther("1");
  return _amount.mul(_accRewardPerShare).div(ACC_REWARD_PRECISION);
}

function calAccPerShare(
  rewardAmount: BigNumber,
  lpSupply: BigNumber
): BigNumber {
  const ACC_REWARD_PRECISION: BigNumber = ethers.utils.parseEther("1");
  return rewardAmount.mul(ACC_REWARD_PRECISION).div(lpSupply);
}

describe.only("NFTStaking Pause functionality", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.

  beforeEach(async () => {
    await setUp();
    totalLockAmount = await mintNFTsToLpProviders();
    await nftStaking.setTotalLockAmount(totalLockAmount);
    expect(await nftStaking.totalLockAmount()).to.equal(totalLockAmount);
  });

  describe("Funtions", function () {
    it("Should pause user reward if lock time expires", async function () {
      await addPoolFunc();
      await approveNFT();
      let txs = await depositNfts();
      await mine(1296000);

      let rewardPerBlk = (await nftStaking.poolInfo(syCHAD.address))
        .rewardPerBlock;
      let oldAccPerShare = (await nftStaking.poolInfo(syCHAD.address))
        .accRewardPerShare;

      let lpSupp = await nftStaking.totalLockAmount();

      let userInfAlice = await nftStaking.userInfo(
        syCHAD.address,
        Alice.address
      );
      let userInfRoy = await nftStaking.userInfo(syCHAD.address, Roy.address);

      let userAmountAlice = userInfAlice.amount;
      let userAmountRoy = userInfRoy.amount;
      let tx = await pauseUser();

      let newUserInfoAlice = await nftStaking.userInfo(
        syCHAD.address,
        Alice.address
      );
      let newUserInfoRoy = await nftStaking.userInfo(
        syCHAD.address,
        Roy.address
      );

      expect(newUserInfoAlice.isPause).to.equal(true);
      expect(newUserInfoRoy.isPause).to.equal(true);

      let blkDiff = tx.blockNumber - txs[4].blockNumber;

      let accPerShare = calAccPerShare(rewardPerBlk.mul(blkDiff), lpSupp);
      let rewardAmountAlice = calAccRewardPerShare(
        accPerShare,
        userAmountAlice
      );
      let rewardAmountRoy = calAccRewardPerShare(accPerShare, userAmountRoy);

      let newAccPerShare = oldAccPerShare.add(accPerShare);
      let rewardDebtAlice = calAccRewardPerShare(
        newAccPerShare,
        userAmountAlice
      );
      let rewardDebtRoy = calAccRewardPerShare(newAccPerShare, userAmountRoy);

      expect(newUserInfoAlice.pendingReward).to.equal(rewardAmountAlice);
      expect(newUserInfoRoy.pendingReward).to.equal(rewardAmountRoy);

      expect(newUserInfoAlice.rewardDebt).to.equal(rewardDebtAlice);
      expect(newUserInfoRoy.rewardDebt).to.equal(rewardDebtRoy);
    });

    it("Should not claim reward if user is paused", async function () {
      await addPoolFunc();
      await approveNFT();
      let txs = await depositNfts();
      await mine(1296000);

      let tx = await pauseUser();

      await expect(
        nftStaking.connect(Alice).claim(syCHAD.address, Alice.address)
      ).to.be.revertedWith("NftStaking: reward paused");
    });

    it("Should not allow withdraw with claim if user is paused", async function () {
      await addPoolFunc();
      await approveNFT();
      let txs = await depositNfts();
      await mine(1296000);

      let tx = await pauseUser();

      await expect(
        nftStaking
          .connect(Alice)
          .withdrawAndClaim(syCHAD.address, Alice.address)
      ).to.be.revertedWith("NftStaking: reward paused");
    });

    it("Should not allow to unpause if user dosn't increase lock time", async function () {
      await addPoolFunc();
      await approveNFT();
      let txs = await depositNfts();
      await mine(1296000);

      let tx = await pauseUser();

      await expect(
        nftStaking.connect(Alice).unpauseReward(syCHAD.address)
      ).to.be.revertedWith("NftStaking: lock time expired");
    });

    it("Should not allow to pause if user lock time not end", async function () {
        await addPoolFunc();
        await approveNFT();
        await depositNfts();  

        let tx = nftStaking.pauseUserReward(syCHAD.address, [
            Roy.address,
            Alice.address,
          ]);
        await expect(tx).to.revertedWith("NftStaking: lock time not expired");
      });

    it("Should allow to unpause if user increase lock time", async function () {
      await addPoolFunc();
      await approveNFT();
      let txs = await depositNfts();
      await mine(1296000);

      let tx = await pauseUser();

      await mine(100);

      let rewardPerBlk = (await nftStaking.poolInfo(syCHAD.address))
        .rewardPerBlock;
      let oldAccPerShare = (await nftStaking.poolInfo(syCHAD.address))
        .accRewardPerShare;

      let tx1 = await unpauesTx();
      let userInfo = await nftStaking.userInfo(syCHAD.address, Alice.address);

      expect(userInfo.isPause).to.equal(false);

      let blkDiff = tx1.blockNumber - tx.blockNumber;
      let lpSupp = await nftStaking.totalLockAmount();
      let accPerShare = calAccPerShare(rewardPerBlk.mul(blkDiff), lpSupp);

      let newAccPerShare = oldAccPerShare.add(accPerShare);
      let rewardDebtAlice = calAccRewardPerShare(
        newAccPerShare,
        userInfo.amount
      );

      expect(rewardDebtAlice).to.equal(userInfo.rewardDebt);
    });

    it("Should transfer pending reward after pause", async function () {
      await addPoolFunc();
      await approveNFT();
      let txs = await depositNfts();
      await mine(1296000);

      let tx = await pauseUser();
      let userInfo = await nftStaking.userInfo(syCHAD.address, Alice.address);

      let befBalance = await rewardToken.balanceOf(Alice.address);

      await expect(
        await nftStaking.connect(Alice).withdrawPendingReward(syCHAD.address)
      )
        .to.emit(nftStaking, "WithdrawPendingRewardAmount")
        .withArgs(syCHAD.address, Alice.address, userInfo.pendingReward);

      expect(await rewardToken.balanceOf(Alice.address)).to.equal(
        befBalance.add(userInfo.pendingReward)
      );
    });

    it("Should withdraw zero pending reward if user has not paused", async function () {
      await addPoolFunc();
      await approveNFT();
      let txs = await depositNfts();
      await mine(1296000);

      let befBalance = await rewardToken.balanceOf(Alice.address);

      await expect(
        await nftStaking.connect(Alice).withdrawPendingReward(syCHAD.address)
      )
        .to.emit(nftStaking, "WithdrawPendingRewardAmount")
        .withArgs(syCHAD.address, Alice.address, 0);

      expect(await rewardToken.balanceOf(Alice.address)).to.equal(
        befBalance.add(0)
      );
    });

    it("Should not allow to unpause after withdraw and pause", async function () {
        await addPoolFunc();
        await approveNFT();
        await depositNfts();
        await mine(1296000);
  
        await pauseUser();
  
        let tx1 = await nftStaking.connect(Alice).withdraw(syCHAD.address);

        await votingEscrow
    .connect(Alice)
    .withdraw();

  await lpTtoken.mint(
    Alice.address,
    parseUnits("100000000000000000000000", 18)
  );

  await lpTtoken
    .connect(Alice)
    .approve(votingEscrow.address, parseUnits("1000", 18));
  const blockNum = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  const timestamp = block.timestamp;
  await votingEscrow
    .connect(Alice)
    .createLock(parseUnits("1000", 18), timestamp + 1000000);
        
        await expect(nftStaking.connect(Alice).unpauseReward(syCHAD.address)).to.revertedWith("NftStaking: token id not deposited")
    });

    it("Should allow to claim reward after unpause", async function () {
      await addPoolFunc();
      await approveNFT();
      await depositNfts();
      await mine(1296000);
      let cur = await time.latest();
      await time.increaseTo(cur + 1296001);

      await pauseUser();

      let tx1 = await unpauesTx();

      await mine(100);

      let rewardPerBlk = (await nftStaking.poolInfo(syCHAD.address))
        .rewardPerBlock;

      let befBeforeBalance = await rewardToken.balanceOf(Alice.address);

      let tx2 = await nftStaking
        .connect(Alice)
        .claim(syCHAD.address, Alice.address);
      let userInfo = await nftStaking.userInfo(syCHAD.address, Alice.address);

      let blkDiff = tx2.blockNumber - tx1.blockNumber;
      let lpSupp = await nftStaking.totalLockAmount();
      let accPerShare = calAccPerShare(rewardPerBlk.mul(blkDiff), lpSupp);
      let rewardAmount = calAccRewardPerShare(accPerShare, userInfo.amount);

      expect(tx2)
        .to.emit(nftStaking, "Claimed")
        .withArgs(syCHAD.address, Alice.address, rewardAmount);

      expect(await rewardToken.balanceOf(Alice.address)).to.equal(
        befBeforeBalance.add(rewardAmount)
      );
    });

  });
});
