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

describe("VotingEscrow", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.

  beforeEach(async () => {
    await setUp();
  });

  describe("Funtions", function () {
    it("Should create lock", async function () {
      await addPoolFunc();

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
      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(parseUnits("1000", 18));
    });

    it("Should increase lock amount and unlock time", async function () {
      await addPoolFunc();

      await lpTtoken
        .connect(addr1)
        .approve(votingEscrow.address, parseUnits("2000", 18));

      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      const timestamp = block.timestamp;
      let time1 = timestamp + 1000000;
      expect(
        await votingEscrow
          .connect(addr1)
          .createLock(parseUnits("1000", 18), time1)
      );

      let calUnlockTime = BigNumber.from(time1)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));

      expect(await votingEscrow.lockedEnd(addr1.address)).to.equal(
        calUnlockTime
      );

      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(parseUnits("1000", 18));
      await votingEscrow
        .connect(addr1)
        .increaseAmountAndUnlockTime(parseUnits("1000", 18), time1 + 1000000);

      let calUnlockTime1 = BigNumber.from(time1)
        .add(1000000)
        .div(BigNumber.from(604800))
        .mul(BigNumber.from(604800));
      let userLockedInfo = await votingEscrow.locked(addr1.address);

      expect(userLockedInfo.end).to.equal(calUnlockTime1);
      expect(userLockedInfo.amount).to.equal(parseUnits("2000", 18));
      expect(
        await gaugeController.userInfo(votingEscrow.address, addr1.address)
      ).to.equal(parseUnits("2000", 18));
    });
  });
});
